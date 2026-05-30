from typing import Annotated

from fastapi import APIRouter, Depends, Request

from app.services.mdns import LinkupAnnouncer, LinkupBrowser

# ============================================================
# ROUTEUR mDNS
# ============================================================

router = APIRouter(
    prefix="/mdns",
    tags=["mdns"],
)


# ============================================================
# ACCÈS AUX OBJETS SYSTÈME VIA app.state
# ============================================================


def _announcer(request: Request) -> LinkupAnnouncer:
    """
    Récupère l'objet LinkupAnnouncer stocké dans l'application FastAPI.
    Cet objet représente l'agent local (cette machine).
    """
    return request.app.state.mdns_announcer


def _browser(request: Request) -> LinkupBrowser:
    """
    Récupère l'objet LinkupBrowser stocké dans l'application FastAPI.
    Cet objet contient tous les agents détectés sur le réseau local.
    """
    return request.app.state.mdns_browser


# ============================================================
# DEPENDENCIES FASTAPI (INJECTION AUTOMATIQUE)
# ============================================================

AnnouncerDep = Annotated[LinkupAnnouncer, Depends(_announcer)]

BrowserDep = Annotated[LinkupBrowser, Depends(_browser)]


# ============================================================
# ROUTE : INFOS DE CET AGENT (LOCAL)
# ============================================================


@router.get("/info")
def mdns_info(announcer: AnnouncerDep) -> dict:
    """
    Retourne les informations de l'agent local (cette machine).

    Exemple :
    - ID de l'agent
    - IP locale
    - port
    - version
    """
    return announcer.info()


# ============================================================
# ROUTE : AGENTS DÉTECTÉS SUR LE RÉSEAU
# ============================================================


@router.get("/services")
def mdns_services(browser: BrowserDep) -> dict:
    """
    Retourne tous les agents Linkup détectés sur le réseau local.

    - count : nombre d'agents trouvés
    - agents : liste détaillée des agents
    """

    agents = browser.list_agents()

    return {"count": len(agents), "agents": agents}
