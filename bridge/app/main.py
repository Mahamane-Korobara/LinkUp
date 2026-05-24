import platform
import time

from fastapi import Depends, FastAPI, Header, HTTPException, status

from app import __version__
from app.config import settings

app = FastAPI(
    title="Linkup Bridge",
    version=__version__,
    description="OS bridge for Linkup — clipboard, files, processes, media.",
)

_started_at = time.monotonic()


def require_agent_token(authorization: str | None = Header(default=None)) -> None:
    """Internal auth: only the Laravel agent (same machine) calls this bridge."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    if token != settings.agent_token:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid bearer token")


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "version": __version__,
        "uptime_seconds": round(time.monotonic() - _started_at, 1),
        "os": platform.system(),
        "os_release": platform.release(),
        "python": platform.python_version(),
    }


@app.get("/system/info", dependencies=[Depends(require_agent_token)])
def system_info() -> dict:
    return {
        "os": platform.system(),
        "os_release": platform.release(),
        "machine": platform.machine(),
        "node": platform.node(),
        "python": platform.python_version(),
    }
