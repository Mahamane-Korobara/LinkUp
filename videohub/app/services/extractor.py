"""Accès yt-dlp : métadonnées, sous-titres, téléchargement.

Toutes les fonctions sont SYNCHRONES (yt-dlp est bloquant) : les routes les
appellent via `starlette.concurrency.run_in_threadpool` pour ne pas geler la
boucle async.
"""

import logging
import tempfile
from pathlib import Path

from yt_dlp import YoutubeDL

from app.config import settings

logger = logging.getLogger(__name__)

# On ne traite jamais une playlist : un lien = une vidéo.
_BASE_OPTS = {"quiet": True, "no_warnings": True, "noplaylist": True}


def _build_opts(extra: dict | None = None) -> dict:
    """Options yt-dlp communes : base + cookies (si configurés) + surcharge."""
    opts = dict(_BASE_OPTS)
    if settings.yt_cookies_file:
        opts["cookiefile"] = settings.yt_cookies_file
    if extra:
        opts |= extra
    return opts


def _friendly(msg: str) -> str:
    """Traduit les erreurs yt-dlp verbeuses en message court et lisible pour l'app."""
    low = msg.lower()
    if "sign in to confirm" in low or "not a bot" in low:
        return (
            "YouTube bloque ce serveur (vérification anti-robot). Les autres "
            "plateformes (TikTok, Instagram, Vimeo, X…) fonctionnent. Activer "
            "YouTube nécessite des cookies configurés sur le serveur."
        )
    if "private video" in low or "video is private" in low:
        return "Cette vidéo est privée."
    if "video unavailable" in low or "has been removed" in low or "removed by" in low:
        return "Vidéo indisponible ou supprimée."
    if "unsupported url" in low or "no video" in low or "unable to extract" in low:
        return "Lien non reconnu ou sans vidéo exploitable."
    if "requested format is not available" in low:
        return "Aucun format téléchargeable disponible pour cette vidéo."
    # Repli : message yt-dlp nettoyé de son préfixe technique.
    return msg.replace("ERROR: ", "").strip()


class ExtractionError(RuntimeError):
    """Lien invalide, vidéo privée/supprimée, ou plateforme non supportée."""


def resolve(url: str) -> dict:
    """Métadonnées sans téléchargement (aperçu + disponibilité des sous-titres)."""
    try:
        with YoutubeDL(_build_opts({"skip_download": True})) as ydl:
            info = ydl.extract_info(url, download=False)
    except Exception as exc:
        raise ExtractionError(_friendly(str(exc))) from exc

    manual = info.get("subtitles") or {}
    auto = info.get("automatic_captions") or {}
    if manual:
        source, langs = "manual", sorted(manual.keys())
    elif auto:
        source, langs = "auto", sorted(auto.keys())
    else:
        source, langs = "none", []

    return {
        "title": info.get("title") or "Vidéo",
        "uploader": info.get("uploader") or info.get("channel") or "",
        "duration": info.get("duration"),  # secondes (peut être None pour les lives)
        "thumbnail": info.get("thumbnail"),
        "extractor": info.get("extractor_key") or info.get("extractor") or "",
        "has_subtitles": source != "none",
        "subtitle_source": source,
        "subtitle_langs": langs,
    }


def _pick_track(tracks: dict[str, list], lang: str) -> tuple[str, list] | None:
    """Choisit la piste de sous-titres : langue demandée d'abord, sinon une variante,
    sinon la première disponible."""
    if not tracks:
        return None
    if lang in tracks:
        return lang, tracks[lang]
    for key in tracks:  # ex. "fr-FR", "fr-orig" quand on demande "fr"
        if key.split("-")[0] == lang:
            return key, tracks[key]
    first = next(iter(tracks))
    return first, tracks[first]


def fetch_subtitle_vtt(url: str, lang: str = "fr") -> dict:
    """Récupère le VTT brut en préférant les sous-titres MANUELS (déjà ponctués).

    Renvoie {available, vtt, source, lang, title, reason}. `available=False`
    si la vidéo n'a aucun sous-titre.
    """
    try:
        with YoutubeDL(_build_opts({"skip_download": True})) as ydl:
            info = ydl.extract_info(url, download=False)
    except Exception as exc:
        raise ExtractionError(_friendly(str(exc))) from exc

    title = info.get("title") or "Transcript"
    manual = info.get("subtitles") or {}
    auto = info.get("automatic_captions") or {}

    chosen = _pick_track(manual, lang)
    source = "manual"
    if chosen is None:
        chosen = _pick_track(auto, lang)
        source = "auto"
    if chosen is None:
        return {
            "available": False,
            "title": title,
            "reason": "Sous-titres non présents sur cette vidéo.",
        }

    used_lang, _formats = chosen

    # On laisse yt-dlp télécharger le sous-titre dans un dossier temporaire : il
    # gère les cas où la piste « vtt » est en réalité un manifeste HLS (Vimeo),
    # du json3/srv3 (YouTube), etc., et convertit en VTT via ffmpeg si besoin.
    # (Le fetch httpx direct récupérait le .m3u8 au lieu des sous-titres.)
    with tempfile.TemporaryDirectory() as td:
        opts = _build_opts(
            {
                "skip_download": True,
                "writesubtitles": source == "manual",
                "writeautomaticsub": source == "auto",
                "subtitleslangs": [used_lang],
                "subtitlesformat": "vtt",
                "outtmpl": str(Path(td) / "%(id)s.%(ext)s"),
            }
        )
        try:
            with YoutubeDL(opts) as ydl:
                ydl.extract_info(url, download=True)
        except Exception as exc:
            raise ExtractionError(_friendly(str(exc))) from exc

        vtt_files = sorted(Path(td).glob("*.vtt"))
        if not vtt_files:
            return {
                "available": False,
                "title": title,
                "reason": "Sous-titres présents mais non récupérables.",
            }
        vtt_text = vtt_files[0].read_text(encoding="utf-8", errors="replace")

    return {
        "available": True,
        "vtt": vtt_text,
        "source": source,
        "lang": used_lang,
        "title": title,
    }


def _format_selector(kind: str, quality: int) -> str:
    if kind == "audio":
        return "bestaudio/best"
    # Borne la hauteur pour limiter le poids ; fusion vidéo+audio.
    return f"bv*[height<=?{quality}]+ba/b[height<=?{quality}]/b"


def download(url: str, kind: str, quality: int, dest_dir: Path) -> Path:
    """Télécharge la vidéo (ou l'audio extrait) dans dest_dir → chemin du fichier."""
    opts = _build_opts({
        "format": _format_selector(kind, quality),
        "outtmpl": str(dest_dir / "%(id)s.%(ext)s"),
        "restrictfilenames": True,
    })
    if kind == "audio":
        opts["postprocessors"] = [
            {"key": "FFmpegExtractAudio", "preferredcodec": "m4a"}
        ]
    else:
        opts["merge_output_format"] = "mp4"
    if settings.max_download_mb > 0:
        opts["max_filesize"] = settings.max_download_mb * 1024 * 1024

    try:
        with YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=True)
    except Exception as exc:
        raise ExtractionError(_friendly(str(exc))) from exc

    # Chemin final (après fusion / post-traitement) : yt-dlp le pose dans
    # requested_downloads ; repli sur prepare_filename + recherche par id.
    downloads = info.get("requested_downloads") or []
    if downloads and downloads[-1].get("filepath"):
        return Path(downloads[-1]["filepath"])
    candidates = sorted(dest_dir.glob(f"{info.get('id', '*')}.*"))
    if candidates:
        return candidates[-1]
    raise ExtractionError("Fichier téléchargé introuvable.")
