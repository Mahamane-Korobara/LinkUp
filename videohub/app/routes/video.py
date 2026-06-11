"""Endpoints /video : resolve, download, transcript.

Tous protégés par le token de service + rate-limit par IP. Les appels yt-dlp
(bloquants) tournent dans un threadpool pour ne pas geler la boucle async.
"""

import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask
from starlette.concurrency import run_in_threadpool

from app.config import settings
from app.deps import rate_limit, require_service_token
from app.services import asr, extractor, formatter
from app.services.subtitles import clean_vtt

router = APIRouter(
    prefix="/video",
    dependencies=[Depends(require_service_token), Depends(rate_limit)],
)

# Type MIME par extension pour la réponse de téléchargement.
_MIME = {
    ".mp4": "video/mp4",
    ".webm": "video/webm",
    ".mkv": "video/x-matroska",
    ".m4a": "audio/mp4",
    ".mp3": "audio/mpeg",
    ".opus": "audio/opus",
}


def _require_url(url: str) -> str:
    url = url.strip()
    if not url.startswith(("http://", "https://")):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Lien invalide."
        )
    return url


@router.get("/resolve")
async def resolve(url: str = Query(...)) -> dict:
    """Métadonnées + disponibilité des sous-titres (aperçu, sans téléchargement)."""
    try:
        return await run_in_threadpool(extractor.resolve, _require_url(url))
    except extractor.ExtractionError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Impossible de lire ce lien : {exc}",
        )


@router.get("/transcript")
async def transcript(url: str = Query(...), lang: str = Query("fr")) -> dict:
    """Transcript formaté en document, en CASCADE :
    1) sous-titres (rapide), 2) sinon ASR Gemini sur l'audio, 3) sinon Whisper.
    """
    url = _require_url(url)

    # --- 1) Sous-titres existants (voie rapide) ---
    try:
        sub = await run_in_threadpool(extractor.fetch_subtitle_vtt, url, lang)
    except extractor.ExtractionError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Impossible de lire ce lien : {exc}",
        )

    if sub.get("available"):
        paragraphs = clean_vtt(sub["vtt"])
        if paragraphs:
            document = await formatter.format_transcript(sub["title"], paragraphs)
            return {
                "available": True,
                "transcript_source": "subtitles",
                "subtitle_source": sub["source"],
                "lang": sub["lang"],
                **document,
            }

    title = sub.get("title", "Transcript")

    # --- 2 & 3) Pas de sous-titres exploitables → ASR sur l'audio ---
    work_dir = Path(settings.tmp_dir) / f"asr-{uuid.uuid4().hex}"
    work_dir.mkdir(parents=True, exist_ok=True)
    try:
        audio = await run_in_threadpool(
            extractor.download_audio_compact, url, work_dir
        )

        # 2) Gemini audio (transcrit + met en forme en un appel)
        doc = await asr.transcribe_with_gemini(audio, title)
        if doc:
            return {"available": True, "transcript_source": "gemini_audio", **doc}

        # 3) Whisper (dernier recours, texte brut → mise en forme)
        raw = await run_in_threadpool(asr.transcribe_with_whisper, audio)
        if raw:
            document = await formatter.format_transcript(title, [raw])
            return {"available": True, "transcript_source": "whisper", **document}
    except extractor.ExtractionError:
        pass  # audio indisponible → on tombe sur le message ci-dessous
    finally:
        _cleanup(work_dir)

    return {
        "available": False,
        "title": title,
        "reason": "Transcription impossible : ni sous-titres, ni parole exploitable.",
    }


@router.get("/download")
async def download(
    url: str = Query(...),
    kind: str = Query("video", pattern="^(video|audio)$"),
    quality: int = Query(720, ge=144, le=2160),
) -> FileResponse:
    """Télécharge la vidéo (ou l'audio extrait) et la renvoie en flux.

    Le fichier est mis en staging dans un sous-dossier unique, puis supprimé après
    l'envoi via une BackgroundTask (le sous-dossier entier est nettoyé)."""
    url = _require_url(url)
    work_dir = Path(settings.tmp_dir) / uuid.uuid4().hex
    work_dir.mkdir(parents=True, exist_ok=True)
    try:
        path = await run_in_threadpool(extractor.download, url, kind, quality, work_dir)
    except extractor.ExtractionError as exc:
        _cleanup(work_dir)
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Téléchargement impossible : {exc}",
        )

    media_type = _MIME.get(path.suffix.lower(), "application/octet-stream")
    return FileResponse(
        path,
        media_type=media_type,
        filename=path.name,
        background=BackgroundTask(_cleanup, work_dir),
    )


def _cleanup(work_dir: Path) -> None:
    """Supprime le dossier de staging (best-effort, après envoi du fichier)."""
    import shutil

    shutil.rmtree(work_dir, ignore_errors=True)
