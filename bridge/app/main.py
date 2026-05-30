"""Point d'entrée FastAPI du bridge Linkup.

Lifespan : démarre l'annonce mDNS + le browser de découverte.
Routes publiques : /health.
Routes protégées par token Bearer : /system/info, /mdns/*.
"""

import getpass
import platform
import socket
import time
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException, Request, status

from app import __version__
from app.config import settings
from app.routes import mdns as mdns_routes
from app.services.mdns import LinkupAnnouncer, LinkupBrowser


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Gère le démarrage / arrêt propre du serveur."""
    announcer = LinkupAnnouncer(
        port=settings.reverb_port, bridge_port=settings.port, version=__version__
    )
    browser = LinkupBrowser(
        heartbeat_interval_seconds=settings.mdns_heartbeat_interval_seconds,
        stale_after_seconds=settings.mdns_stale_after_seconds,
        healthcheck_timeout_seconds=settings.mdns_healthcheck_timeout_seconds,
    )
    await announcer.start()
    await browser.start()

    # `_started_at` dans app.state pour qu'un hot reload uvicorn le réinitialise
    # avec le nouveau démarrage (au lieu d'un module-level qui peut survivre).
    app.state.mdns_announcer = announcer
    app.state.mdns_browser = browser
    app.state.started_at = time.monotonic()

    try:
        yield
    finally:
        await browser.stop()
        await announcer.stop()


app = FastAPI(
    title="Linkup Bridge",
    version=__version__,
    description="Pont système pour Linkup : clipboard, fichiers, processus et média.",
    lifespan=lifespan,
)

app.include_router(mdns_routes.router)


def require_agent_token(authorization: str | None = Header(default=None)) -> None:
    """Vérifie le header `Authorization: Bearer <token>` contre `settings.agent_token`."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Token manquant ou invalide"
        )

    token = authorization.removeprefix("Bearer ").strip()
    if token != settings.agent_token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token non autorisé")


def _safe_username() -> str:
    """Retourne le nom user du PC sans planter si l'env est dégradé.

    `getpass.getuser()` lève `KeyError` si `LOGNAME`/`USER`/`USERNAME` sont
    absents, et `OSError` sur Windows quand `os.getlogin()` échoue. Pas de
    raison de catcher autre chose ici.
    """
    try:
        return getpass.getuser()
    except (KeyError, OSError):
        return "unknown"


@app.get("/health")
def health(request: Request) -> dict:
    """Route publique sans token : seule information révélée volontairement au LAN.

    Voir ADR-002 — utilisée par le LAN sweep côté Flutter et par le heartbeat
    inter-PC. Ne retourne rien que mDNS ne broadcast déjà publiquement.
    """
    announcer = getattr(request.app.state, "mdns_announcer", None)
    started_at = getattr(request.app.state, "started_at", time.monotonic())

    return {
        "status": "alive",
        "service": "linkup-bridge",
        "agent_id": getattr(announcer, "agent_id", None),
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "version": __version__,
        "uptime_seconds": round(time.monotonic() - started_at, 1),
        "host": socket.gethostname(),
        "user": _safe_username(),
        "os": platform.system(),
        "os_release": platform.release(),
        "python": platform.python_version(),
    }


@app.get("/system/info", dependencies=[Depends(require_agent_token)])
def system_info() -> dict:
    """Détail système. Token Bearer obligatoire (cf. ADR-002)."""
    return {
        "os": platform.system(),
        "os_release": platform.release(),
        "machine": platform.machine(),
        "node": platform.node(),
        "python": platform.python_version(),
    }
