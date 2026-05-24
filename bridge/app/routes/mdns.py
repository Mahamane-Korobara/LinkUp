from typing import Annotated

from fastapi import APIRouter, Depends, Request

from app.services.mdns import LinkupAnnouncer, LinkupBrowser

router = APIRouter(prefix="/mdns", tags=["mdns"])


def _announcer(request: Request) -> LinkupAnnouncer:
    return request.app.state.mdns_announcer


def _browser(request: Request) -> LinkupBrowser:
    return request.app.state.mdns_browser


AnnouncerDep = Annotated[LinkupAnnouncer, Depends(_announcer)]
BrowserDep = Annotated[LinkupBrowser, Depends(_browser)]


@router.get("/info")
def mdns_info(announcer: AnnouncerDep) -> dict:
    """What this agent advertises on the LAN."""
    return announcer.info()


@router.get("/services")
def mdns_services(browser: BrowserDep) -> dict:
    """All Linkup agents (including ourselves) discovered on the LAN."""
    return {"count": len(browser.list_agents()), "agents": browser.list_agents()}
