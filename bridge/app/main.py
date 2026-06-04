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
from pathlib import Path

from fastapi import Depends, FastAPI, Request, Response

from app import __version__
from app.config import settings
from app.deps import require_agent_token
from app.routes import clipboard as clipboard_routes
from app.routes import mdns as mdns_routes
from app.routes import preview as preview_routes
from app.routes import transfer as transfer_routes
from app.services.cert import CertManager
from app.services.mdns import LinkupAnnouncer, LinkupBrowser
from app.services.preview import ProxyManager
from app.services.transfer import TransferService


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Gère le démarrage / arrêt propre du serveur."""
    announcer = LinkupAnnouncer(
        port=settings.reverb_port,
        bridge_port=settings.port,
        laravel_port=settings.laravel_port,
        version=__version__,
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
    # Chunks en staging sous ~/.linkup/transfers, fichiers finalisés rangés par
    # catégorie sous l'inbox configurée (LINKUP_BRIDGE_TRANSFERS_DIR, défaut
    # ~/Linkup/Transfert). L'ancien dossier plat est fouillé en fallback à l'ouverture.
    app.state.transfer_service = TransferService(
        staging_dir=Path.home() / ".linkup" / "transfers",
        inbox_dir=Path(settings.transfers_dir).expanduser(),
        legacy_inbox_dirs=(Path(settings.transfers_dir_legacy).expanduser(),),
    )
    # Dev Preview : CA Linkup + cert serveur (HTTPS obligatoire pour le contexte
    # sécurisé côté tél). La CA est générée une fois sous ~/.linkup/ca, le cert
    # serveur régénéré à chaque démarrage pour suivre l'IP LAN courante.
    cert_manager = CertManager(ca_dir=Path.home() / ".linkup" / "ca")
    cert_manager.ensure()
    app.state.cert_manager = cert_manager
    # Écoute sur la même interface LAN que le bridge pour que le tél joigne les
    # projets proxifiés ; servis en HTTPS via la CA. Listeners fermés à l'arrêt.
    app.state.proxy_manager = ProxyManager(
        host=settings.host, ssl_context=cert_manager.ssl_context()
    )

    try:
        yield
    finally:
        await app.state.proxy_manager.shutdown()
        await browser.stop()
        await announcer.stop()


app = FastAPI(
    title="Linkup Bridge",
    version=__version__,
    description="Pont système pour Linkup : clipboard, fichiers, processus et média.",
    lifespan=lifespan,
)

app.include_router(mdns_routes.router)
app.include_router(transfer_routes.router)
app.include_router(clipboard_routes.router)
app.include_router(preview_routes.router)


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
        # Port HTTP de l'agent Laravel : le tél bâtit /api/agent/info dessus
        # (évite le 8000 codé en dur → marche aussi sur le bundle en 8770).
        "laravel_port": settings.laravel_port,
        "host": socket.gethostname(),
        "user": _safe_username(),
        "os": platform.system(),
        "os_release": platform.release(),
        "python": platform.python_version(),
    }


@app.get("/preview/ca.crt")
def preview_ca(request: Request) -> Response:
    """Certificat PUBLIC de la CA Linkup, à installer/approuver sur le tél.

    Sans token : le tél doit pouvoir le récupérer AVANT toute confiance établie,
    et un certificat de CA est public par nature (la clé privée, elle, ne quitte
    jamais le PC). Le type MIME `application/x-x509-ca-cert` déclenche l'install
    du certificat sur Android.
    """
    cert_manager: CertManager = request.app.state.cert_manager
    return Response(
        content=cert_manager.ca_pem(),
        media_type="application/x-x509-ca-cert",
        headers={"Content-Disposition": 'attachment; filename="linkup-ca.crt"'},
    )


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
