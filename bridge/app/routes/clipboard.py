"""Routes presse-papier + lien rapide (S5).

Appelées par Laravel avec le token agent (Laravel orchestre + journalise, le
bridge touche l'OS). Toutes protégées par `require_agent_token`.
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.deps import require_agent_token
from app.services import clipboard as clip_service
from app.services import links as link_service
from app.services.clipboard import ClipboardError
from app.services.links import LinkError

router = APIRouter(tags=["clipboard"], dependencies=[Depends(require_agent_token)])


class ClipboardWrite(BaseModel):
    text: str


class LinkOpen(BaseModel):
    url: str


@router.get("/clipboard/read")
def clipboard_read() -> dict:
    """Lit le presse-papier du PC (pour l'envoyer au tél)."""
    try:
        return {"text": clip_service.read_clipboard()}
    except ClipboardError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@router.post("/clipboard/write")
def clipboard_write(body: ClipboardWrite) -> dict:
    """Écrit dans le presse-papier du PC (contenu copié depuis le tél)."""
    try:
        clip_service.write_clipboard(body.text)
    except ClipboardError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"ok": True}


@router.post("/link/open")
def link_open(body: LinkOpen) -> dict:
    """Ouvre un lien (http/https) dans le navigateur par défaut du PC."""
    try:
        opened = link_service.open_url(body.url)
    except LinkError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"ok": True, "url": opened}
