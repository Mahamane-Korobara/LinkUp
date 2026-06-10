"""Point d'entrée FastAPI du service VideoHub Linkup.

Route publique : /health.
Routes protégées (token de service + rate-limit) : /video/*.
"""

import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request

from app import __version__
from app.config import settings
from app.routes import video as video_routes


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.started_at = time.monotonic()
    # Dossier de staging des téléchargements (créé une fois au démarrage).
    Path(settings.tmp_dir).mkdir(parents=True, exist_ok=True)
    yield


app = FastAPI(
    title="Linkup VideoHub",
    version=__version__,
    description="Téléchargeur vidéo multi-plateformes + transcript formaté (standalone).",
    lifespan=lifespan,
)

app.include_router(video_routes.router)


@app.get("/health")
def health(request: Request) -> dict:
    """Route publique sans token — sonde de disponibilité."""
    started_at = getattr(request.app.state, "started_at", time.monotonic())
    return {
        "status": "alive",
        "service": "linkup-videohub",
        "version": __version__,
        "uptime_seconds": round(time.monotonic() - started_at, 1),
    }
