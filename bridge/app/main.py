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

# =========================
# GESTION DU CYCLE DE VIE DU SERVEUR
# =========================


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Gère ce qui se passe AU DÉMARRAGE et À L'ARRÊT du serveur.
    """

    # DÉMARRAGE DU SERVEUR
    # ------------------------

    # Crée un service qui annonce cette machine sur le réseau local
    announcer = LinkupAnnouncer(
        port=settings.reverb_port, bridge_port=settings.port, version=__version__
    )

    # Crée un service qui cherche d'autres machines Linkup sur le réseau
    browser = LinkupBrowser(
        heartbeat_interval_seconds=settings.mdns_heartbeat_interval_seconds,
        stale_after_seconds=settings.mdns_stale_after_seconds,
        healthcheck_timeout_seconds=settings.mdns_healthcheck_timeout_seconds,
    )

    # Démarre l'annonce réseau
    await announcer.start()

    # Démarre la recherche réseau
    await browser.start()

    # Stocke les objets dans l'application pour pouvoir les réutiliser ailleurs
    app.state.mdns_announcer = announcer
    app.state.mdns_browser = browser

    # Laisse l'application tourner ici
    try:
        yield

    # ARRÊT DU SERVEUR
    # ---------------------
    finally:
        # Arrête proprement la recherche réseau
        await browser.stop()

        # Arrête proprement l'annonce réseau
        await announcer.stop()


# =========================
# CRÉATION DE L'APPLICATION FASTAPI
# =========================

app = FastAPI(
    title="Linkup Bridge",  # Nom de l'API
    version=__version__,  # Version du projet
    description=("Pont système pour Linkup : clipboard, fichiers, processus et média."),
    lifespan=lifespan,  # Active le cycle de vie (start/stop mDNS)
)

# Ajoute les routes mDNS (ex: /mdns/info, /mdns/services)
app.include_router(mdns_routes.router)


# =========================
# TEMPS DE DÉMARRAGE
# =========================

_started_at = time.monotonic()
# Stocke le moment où le serveur a démarré
# utilisé pour calculer l'uptime


# =========================
# SYSTÈME DE SÉCURITÉ (TOKEN INTERNE)
# =========================


def require_agent_token(authorization: str | None = Header(default=None)) -> None:
    """
    Vérifie que la requête vient d'un client autorisé.

    Le client doit envoyer :
    Authorization: Bearer <token>
    """

    # Vérifie que le header Authorization existe et est correct
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Token manquant ou invalide"
        )

    # Extrait le token après "Bearer "
    token = authorization.removeprefix("Bearer ").strip()

    # Vérifie si le token correspond à celui configuré dans l'app
    if token != settings.agent_token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token non autorisé")


# =========================
# ROUTE DE VÉRIFICATION (HEALTH CHECK)
# =========================


@app.get("/health")
def health(request: Request) -> dict:
    """
    Vérifie si le serveur fonctionne correctement.
    Utilisé pour monitoring ou debug.
    """
    announcer = getattr(request.app.state, "mdns_announcer", None)

    return {
        "status": "alive",  # serveur vivant
        "service": "linkup-bridge",
        "agent_id": getattr(announcer, "agent_id", None),
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "version": __version__,  # version de l'API
        "uptime_seconds": round(time.monotonic() - _started_at, 1),
        # temps depuis le démarrage
        "host": socket.gethostname(),  # nom de la machine (ex: mahamane-VivoBook)
        "user": _safe_username(),  # nom de l'utilisateur connecté (ex: mahamane)
        "os": platform.system(),  # ex: Linux / Windows
        "os_release": platform.release(),  # version OS
        "python": platform.python_version(),  # version Python
    }


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


# =========================
# INFOS SYSTÈME (PROTÉGÉ)
# =========================


@app.get("/system/info", dependencies=[Depends(require_agent_token)])  # sécurité obligatoire
def system_info() -> dict:
    """
    Retourne des informations sur la machine.
    Accessible uniquement avec un token valide.
    """

    return {
        "os": platform.system(),  # système d'exploitation
        "os_release": platform.release(),  # version OS
        "machine": platform.machine(),  # architecture (x86_64 etc.)
        "node": platform.node(),  # nom de la machine
        "python": platform.python_version(),  # version Python
    }
