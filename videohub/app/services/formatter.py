"""Formatage du transcript en DOCUMENT.

Voie principale : Google Gemini Flash (palier gratuit) restaure ponctuation /
majuscules et regroupe en sections avec titres — sans inventer de contenu.
Repli : si pas de clé, erreur réseau, quota dépassé ou réponse illisible, on
renvoie les paragraphes heuristiques tels quels (une seule section sans titre).

Le résultat est toujours la même forme :
    {"title": str, "sections": [{"heading": str|None, "paragraphs": [str, ...]}],
     "formatted_by": "gemini" | "heuristic"}
"""

import json
import logging

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

_GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

_PROMPT = (
    "Tu reçois le transcript BRUT d'une vidéo (issu de sous-titres). Reformate-le "
    "en un DOCUMENT lisible EN FRANÇAIS sans rien inventer ni résumer :\n"
    "- corrige la ponctuation, les majuscules et les fautes évidentes d'orthographe ;\n"
    "- regroupe en paragraphes cohérents ;\n"
    "- découpe en sections thématiques avec un titre court (heading) quand c'est pertinent ;\n"
    "- garde TOUT le contenu, n'ajoute aucune information absente du texte.\n"
    "Réponds UNIQUEMENT en JSON valide de la forme : "
    '{"title": "...", "sections": [{"heading": "...", "paragraphs": ["...", "..."]}]}\n'
    "Le heading peut être une chaîne vide si une section n'a pas de titre naturel.\n\n"
    "Titre de la vidéo : {title}\n\nTranscript brut :\n{body}"
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
        "generationConfig": {"response_mime_type": "application/json", "temperature": 0.2},
    }
    try:
        async with httpx.AsyncClient(timeout=45.0) as client:
            resp = await client.post(
                url, params={"key": settings.gemini_api_key}, json=body
            )
            resp.raise_for_status()
            data = resp.json()
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        parsed = json.loads(text)
        return _coerce(parsed, title, paragraphs)
    except Exception as exc:  # réseau, quota, JSON cassé, forme inattendue…
        logger.warning("Gemini indisponible, repli heuristique : %s", exc)
        return _heuristic(title, paragraphs)
