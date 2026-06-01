"""Ouverture d'un lien envoyé par le tél dans le navigateur du PC (S5).

Sécurité : on n'ouvre QUE des URL http(s). On refuse explicitement `file://`,
`javascript:`, `data:`, etc. qui pourraient exfiltrer un fichier local ou
exécuter du script via le handler par défaut de l'OS.
"""

from __future__ import annotations

import subprocess
import sys
from urllib.parse import urlparse

from app.services.transfer import _desktop_env

_ALLOWED_SCHEMES = {"http", "https"}


class LinkError(Exception):
    """Lien invalide ou non ouvrable."""


def _open_command(url: str) -> list[str]:
    if sys.platform == "darwin":
        return ["open", url]
    if sys.platform.startswith("win"):
        return ["cmd", "/c", "start", "", url]
    return ["xdg-open", url]


def open_url(url: str) -> str:
    """Valide puis ouvre [url] dans le navigateur par défaut du PC.

    Retourne l'URL nettoyée. Throws LinkError si le schéma n'est pas http(s),
    si l'URL n'a pas d'hôte, ou si le lanceur échoue immédiatement.
    """
    cleaned = url.strip()
    parsed = urlparse(cleaned)
    if parsed.scheme.lower() not in _ALLOWED_SCHEMES or not parsed.netloc:
        raise LinkError(f"Lien non autorisé (schéma « {parsed.scheme or '∅'} »).")

    cmd = _open_command(cleaned)
    try:
        proc = subprocess.Popen(  # noqa: S603
            cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, env=_desktop_env()
        )
    except FileNotFoundError as exc:
        raise LinkError(f"Lanceur « {cmd[0]} » introuvable sur ce PC.") from exc

    try:
        _, stderr = proc.communicate(timeout=3)
    except subprocess.TimeoutExpired:
        return cleaned  # navigateur lancé/exec en place = succès

    if proc.returncode != 0:
        detail = stderr.decode(errors="replace").strip() or f"code {proc.returncode}"
        raise LinkError(f"Le PC n'a pas pu ouvrir le lien ({detail}).")
    return cleaned
