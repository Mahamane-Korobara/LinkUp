"""Routes Dev Preview (localhost mobile).

Plan de contrôle uniquement (lister / exposer / retirer). Le plan de données —
le navigateur du tél qui charge le projet — frappe DIRECTEMENT le listener de
proxy (cf. ``ProxyManager``), pas ces routes.

Protégées par ``require_agent_token`` : c'est Laravel (auth.device côté tél) qui
orchestre et relaie vers le bridge, comme clipboard/transfert.
"""

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from app.config import settings
from app.deps import require_agent_token
from app.services.preview import ProxyError, ProxyManager, scan_listening_ports

router = APIRouter(prefix="/preview", tags=["preview"], dependencies=[Depends(require_agent_token)])


class PortBody(BaseModel):
    port: int = Field(ge=1, le=65535)


def _manager(request: Request) -> ProxyManager:
    return request.app.state.proxy_manager


@router.get("/ports")
def list_ports(request: Request) -> dict:
    """Ports de dev détectés sur le PC, hors port du bridge et proxies actifs."""
    manager = _manager(request)
    exclude = {settings.port} | manager.listen_ports()
    return {"ports": [p.as_dict() for p in scan_listening_ports(exclude=exclude)]}


@router.get("/exposed")
def list_exposed(request: Request) -> dict:
    """Projets actuellement exposés au LAN."""
    return {"exposed": [info.as_dict() for info in _manager(request).list()]}


@router.post("/expose")
async def expose(body: PortBody, request: Request) -> dict:
    """Ouvre un proxy vers ``127.0.0.1:<port>`` ; renvoie le port d'écoute LAN.

    Le tél bâtit l'URL à ouvrir = ``<schéma>://<host-bridge>:<listen_port>`` (il
    connaît déjà l'hôte du bridge auquel il est connecté).
    """
    try:
        info = await _manager(request).expose(body.port)
    except ProxyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return info.as_dict()


@router.post("/unexpose")
async def unexpose(body: PortBody, request: Request) -> dict:
    return {"ok": await _manager(request).unexpose(body.port)}
