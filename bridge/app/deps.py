"""Dépendances FastAPI partagées (auth + accès aux services via app.state).

Extraites de main.py pour être réutilisables par les routers sans import
circulaire (un router importe app.deps, pas app.main).
"""

import base64
import hashlib
import hmac

from fastapi import Header, HTTPException, Request, status

from app.config import settings
from app.services.transfer import TransferService


def _bearer(authorization: str | None) -> str | None:
    if not authorization or not authorization.startswith("Bearer "):
        return None
    return authorization.removeprefix("Bearer ").strip()


def require_agent_token(authorization: str | None = Header(default=None)) -> None:
    """Vérifie le header `Authorization: Bearer <token>` contre settings.agent_token."""
    token = _bearer(authorization)
    if token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Token manquant ou invalide"
        )
    if not hmac.compare_digest(token, settings.agent_token):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token non autorisé")


def transfer_token(transfer_id: str) -> str:
    """Token d'upload scopé à un transfert (cf. TransferTokenSigner côté Laravel).

    base64url(HMAC-SHA256(transfer_id, agent_token)), sans padding.
    """
    mac = hmac.new(settings.agent_token.encode(), transfer_id.encode(), hashlib.sha256).digest()
    return base64.urlsafe_b64encode(mac).rstrip(b"=").decode()


def require_transfer_auth(
    request: Request, authorization: str | None = Header(default=None)
) -> None:
    """Autorise soit le token agent complet (Laravel / sens PC→tel), soit un
    token de transfert qui n'est valide QUE pour son propre transfer_id.

    Le transfer_id est lu du path (`/transfer/{id}/...`) ou du header
    `X-Transfer-Id` (upload). Comparaisons en temps constant (anti-timing)."""
    token = _bearer(authorization)
    if token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Token manquant ou invalide"
        )

    if hmac.compare_digest(token, settings.agent_token):
        return

    transfer_id = request.path_params.get("transfer_id") or request.headers.get("x-transfer-id")
    if transfer_id and hmac.compare_digest(token, transfer_token(transfer_id)):
        return

    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token non autorisé")


def get_transfer_service(request: Request) -> TransferService:
    """Récupère le TransferService créé au démarrage (lifespan)."""
    return request.app.state.transfer_service
