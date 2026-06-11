"""ASR — transcrire la PAROLE quand il n'y a pas de sous-titres.

Deux moteurs, utilisés en cascade par la route (après l'échec des sous-titres) :
1. **Gemini audio** : on envoie l'audio compact à Gemini qui transcrit ET met en
   forme en un seul appel (réutilise la clé déjà configurée). Envoi direct ≤ ~18 Mo.
2. **Whisper** (faster-whisper, CPU) : dernier recours, 100 % local. Import paresseux
   et optionnel — si le paquet n'est pas installé, ce moteur est simplement ignoré.
"""

import asyncio
import base64
import json
import logging
from pathlib import Path

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

_GEMINI_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
)
# Marge sous la limite de 20 Mo de l'envoi direct (inline_data) de Gemini.
_MAX_INLINE_BYTES = 18 * 1024 * 1024

_AUDIO_PROMPT = (
    "Tu reçois l'AUDIO d'une vidéo. Transcris fidèlement et INTÉGRALEMENT la parole "
    "entendue, mot pour mot, dans la langue parlée (ne traduis pas). Présente-la "
    "ensuite comme un DOCUMENT lisible : ponctuation et majuscules correctes, "
    "paragraphes cohérents, sections thématiques avec un titre court (heading) quand "
    "le sujet change. N'invente rien, ne résume pas, n'ajoute aucune information "
    "absente de l'audio. S'il n'y a aucune parole, renvoie une liste de sections vide.\n"
    "Réponds UNIQUEMENT en JSON : "
    '{"title": "...", "sections": [{"heading": "...", "paragraphs": ["..."]}]}\n'
    "Titre de la vidéo : {title}"
)


def _coerce_doc(payload: object, title: str) -> dict | None:
    """Valide la réponse Gemini → doc structuré, ou None si la forme est inexploitable."""
    if not isinstance(payload, dict):
        return None
    sections = payload.get("sections")
    if not isinstance(sections, list):
        return None
    out: list[dict] = []
    for sec in sections:
        if not isinstance(sec, dict):
            continue
        paras = sec.get("paragraphs")
        if not isinstance(paras, list):
            continue
        clean = [str(p).strip() for p in paras if str(p).strip()]
        if not clean:
            continue
        heading = sec.get("heading")
        out.append(
            {
                "heading": (str(heading).strip() or None) if heading else None,
                "paragraphs": clean,
            }
        )
    if not out:
        return None
    return {
        "title": str(payload.get("title") or title).strip() or title,
        "sections": out,
        "formatted_by": "gemini",
    }


async def transcribe_with_gemini(audio_path: Path, title: str) -> dict | None:
    """Transcrit + met en forme l'audio via Gemini (envoi direct). None si échec."""
    if not settings.gemini_api_key:
        return None
    try:
        data = audio_path.read_bytes()
    except Exception:
        return None
    if not data or len(data) > _MAX_INLINE_BYTES:
        return None  # trop gros pour l'envoi direct → Whisper prendra le relais

    body = {
        "contents": [
            {
                "parts": [
                    {"text": _AUDIO_PROMPT.replace("{title}", title or "(sans titre)")},
                    {
                        "inline_data": {
                            "mime_type": "audio/mpeg",
                            "data": base64.b64encode(data).decode(),
                        }
                    },
                ]
            }
        ],
        "generationConfig": {
            "response_mime_type": "application/json",
            "temperature": 0.2,
            "maxOutputTokens": 16384,
        },
    }
    url = _GEMINI_URL.format(model=settings.gemini_model)
    try:
        async with httpx.AsyncClient(timeout=240.0) as client:
            payload = await _post_with_retry(client, url, body)
        text = payload["candidates"][0]["content"]["parts"][0]["text"]
        return _coerce_doc(json.loads(text), title)
    except Exception as exc:  # réseau, quota, JSON cassé, audio non géré…
        logger.warning("ASR Gemini indisponible : %s", exc)
        return None


# Statuts transitoires fréquents avec Gemini (surtout audio / palier gratuit).
_RETRYABLE = {429, 500, 502, 503, 504}


async def _post_with_retry(client: httpx.AsyncClient, url: str, body: dict) -> dict:
    """POST Gemini avec quelques tentatives sur erreurs transitoires (503/429…)."""
    last: Exception | None = None
    for attempt in range(4):  # 4 essais : ~0 + 2 + 4 + 8 s de backoff
        resp = await client.post(
            url, params={"key": settings.gemini_api_key}, json=body
        )
        if resp.status_code in _RETRYABLE:
            last = httpx.HTTPStatusError(
                f"{resp.status_code}", request=resp.request, response=resp
            )
            await asyncio.sleep(2 ** attempt)
            continue
        resp.raise_for_status()
        return resp.json()
    raise last or RuntimeError("Gemini: échec après retries")


_whisper_model = None


def _get_whisper():
    global _whisper_model
    if _whisper_model is None:
        # Import paresseux : le paquet est lourd et OPTIONNEL (dernier recours).
        from faster_whisper import WhisperModel

        _whisper_model = WhisperModel("base", device="cpu", compute_type="int8")
    return _whisper_model


def transcribe_with_whisper(audio_path: Path) -> str | None:
    """Transcrit l'audio avec faster-whisper (CPU). Texte brut, ou None si indispo/échec."""
    try:
        model = _get_whisper()
        segments, _info = model.transcribe(str(audio_path), vad_filter=True)
        text = " ".join(seg.text.strip() for seg in segments).strip()
        return text or None
    except Exception as exc:  # paquet absent, modèle non téléchargé, erreur d'inférence
        logger.warning("ASR Whisper indisponible : %s", exc)
        return None
