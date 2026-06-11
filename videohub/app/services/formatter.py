"""Formatage du transcript en DOCUMENT.

Voie principale : Google Gemini Flash (palier gratuit) restaure ponctuation /
majuscules et regroupe en sections avec titres — sans inventer de contenu.
Repli : si pas de clé, erreur réseau, quota dépassé ou réponse illisible, on
renvoie les paragraphes heuristiques tels quels (une seule section sans titre).

Le résultat est toujours la même forme :
    {"title": str, "sections": [{"heading": str|None, "paragraphs": [str, ...]}],
     "formatted_by": "gemini" | "heuristic"}
"""

import asyncio
import json
import logging

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

# Statuts transitoires fréquents avec Gemini (surcharge, palier gratuit).
_RETRYABLE = {429, 500, 502, 503, 504}


async def _post_with_retry(client: httpx.AsyncClient, url: str, body: dict) -> dict:
    """POST Gemini avec quelques tentatives sur erreurs transitoires (503/429…)."""
    last: Exception | None = None
    for attempt in range(4):  # ~1 + 2 + 4 + 8 s de backoff
        resp = await client.post(
            url, params={"key": settings.gemini_api_key}, json=body
        )
        if resp.status_code in _RETRYABLE:
            last = httpx.HTTPStatusError(
                str(resp.status_code), request=resp.request, response=resp
            )
            await asyncio.sleep(2 ** attempt)
            continue
        resp.raise_for_status()
        return resp.json()
    raise last or RuntimeError("Gemini: échec après retries")

_GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

_PROMPT = (
    "Tu reçois la transcription BRUTE d'une vidéo, issue de sous-titres : souvent "
    "sans ponctuation, avec des répétitions, des hésitations et des erreurs de "
    "reconnaissance vocale. Transforme-la en un DOCUMENT clair, fluide et bien "
    "structuré, FIDÈLE au propos :\n"
    "- restitue une ponctuation et des majuscules correctes, phrase par phrase ;\n"
    "- corrige les fautes d'orthographe et les mots manifestement mal transcrits "
    "(en t'appuyant sur le sens et le contexte) ;\n"
    "- supprime les répétitions involontaires, les hésitations et tics de langage "
    "(« euh », « hum », mots répétés) SANS retirer la moindre information ;\n"
    "- regroupe les phrases en paragraphes cohérents et aérés ;\n"
    "- découpe le texte en sections thématiques avec un titre court et descriptif "
    "(heading) dès que le sujet change réellement ;\n"
    "- rédige dans la MÊME LANGUE que la vidéo (ne traduis pas) ;\n"
    "- ne résume pas, n'invente rien, n'ajoute aucune information absente : tout "
    "le propos doit rester présent, seulement mieux écrit.\n"
    "Réponds UNIQUEMENT en JSON valide de la forme : "
    '{"title": "...", "sections": [{"heading": "...", "paragraphs": ["...", "..."]}]}\n'
    "Le heading peut être une chaîne vide si une section n'a pas de titre naturel.\n\n"
    "Titre de la vidéo : {title}\n\nTranscription brute :\n{body}"
)


def _heuristic(title: str, paragraphs: list[str]) -> dict:
    return {
        "title": title,
        "sections": [{"heading": None, "paragraphs": paragraphs}],
        "formatted_by": "heuristic",
    }


def _coerce(payload: dict, title: str, paragraphs: list[str]) -> dict:
    """Valide/normalise la réponse Gemini ; repli heuristique si la forme cloche."""
    sections = payload.get("sections")
    if not isinstance(sections, list) or not sections:
        return _heuristic(title, paragraphs)
    out_sections = []
    for sec in sections:
        if not isinstance(sec, dict):
            continue
        paras = sec.get("paragraphs")
        if not isinstance(paras, list):
            continue
        clean_paras = [str(p).strip() for p in paras if str(p).strip()]
        if not clean_paras:
            continue
        heading = sec.get("heading")
        out_sections.append(
            {"heading": (str(heading).strip() or None) if heading else None,
             "paragraphs": clean_paras}
        )
    if not out_sections:
        return _heuristic(title, paragraphs)
    return {
        "title": str(payload.get("title") or title).strip() or title,
        "sections": out_sections,
        "formatted_by": "gemini",
    }


async def format_transcript(title: str, paragraphs: list[str]) -> dict:
    """Formate le transcript ; ne lève jamais — repli heuristique sur toute erreur."""
    if not paragraphs:
        return _heuristic(title, paragraphs)
    if not settings.gemini_api_key:
        return _heuristic(title, paragraphs)

    prompt = _PROMPT.replace("{title}", title or "(sans titre)").replace(
        "{body}", "\n\n".join(paragraphs)
    )
    url = _GEMINI_URL.format(model=settings.gemini_model)
    body = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "response_mime_type": "application/json",
            "temperature": 0.2,
            # Transcripts longs : éviter une sortie tronquée (JSON cassé → repli).
            "maxOutputTokens": 16384,
        },
    }
    try:
        async with httpx.AsyncClient(timeout=90.0) as client:
            data = await _post_with_retry(client, url, body)
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        parsed = json.loads(text)
        return _coerce(parsed, title, paragraphs)
    except Exception as exc:  # réseau, quota, JSON cassé, forme inattendue…
        logger.warning("Gemini indisponible, repli heuristique : %s", exc)
        return _heuristic(title, paragraphs)
