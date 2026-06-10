"""Dépendances FastAPI partagées : auth Bearer + rate-limit simple.

Repris du pattern de bridge/app/deps.py (comparaison en temps constant), adapté
au token de service public (un seul secret partagé app↔service).
"""

import hmac
import time
from collections import defaultdict, deque

from fastapi import Header, HTTPException, Request, status

from app.config import settings


def _bearer(authorization: str | None) -> str | None:
    if not authorization or not authorization.startswith("Bearer "):
        return None
    return authorization.removeprefix("Bearer ").strip()


def require_service_token(authorization: str | None = Header(default=None)) -> None:
    """Vérifie `Authorization: Bearer <token>` contre settings.service_token.

    Comparaison en temps constant (anti-timing). NOTE: le token est partagé et
    extractible de l'APK — c'est un garde-fou anti-abus, pas une auth forte.
    """
    token = _bearer(authorization)
    if token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Token manquant ou invalide"
        )
    if not hmac.compare_digest(token, settings.service_token):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token non autorisé")


# Rate-limit in-memory par IP : fenêtre glissante de 60 s. Suffisant pour un
# unique process uvicorn en alpha (pas de Redis). Réinitialisé au redémarrage.
_hits: dict[str, deque[float]] = defaultdict(deque)


def rate_limit(request: Request) -> None:
    """Refuse (429) au-delà de settings.rate_limit_per_min requêtes/IP/minute."""
    now = time.monotonic()
    ip = request.client.host if request.client else "unknown"
    window = _hits[ip]
    # Purge les timestamps de plus de 60 s.
    while window and now - window[0] > 60.0:
        window.popleft()
    if len(window) >= settings.rate_limit_per_min:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Trop de requêtes, réessaie dans une minute.",
        )
    window.append(now)
