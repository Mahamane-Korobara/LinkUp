"""Accès au presse-papier de l'OS (S5 — module presse-papier).

Abstraction multi-plateforme via les outils CLI natifs (aucune dépendance Python
supplémentaire) :
- Linux Wayland : wl-copy / wl-paste
- Linux X11     : xclip
- macOS         : pbcopy / pbpaste
- Windows       : clip / PowerShell Get-Clipboard

L'environnement est nettoyé des variables snap (cf. transfer._desktop_env) pour
les mêmes raisons : le bridge peut tourner dans un terminal confiné (VS Code).
"""

from __future__ import annotations

import os
import subprocess
import sys

from app.services.transfer import _desktop_env

# Le presse-papier n'est pas un canal de transfert de fichier : on plafonne.
MAX_CLIPBOARD_BYTES = 1024 * 1024  # 1 Mo


class ClipboardError(Exception):
    """Échec d'accès au presse-papier de l'OS."""


def _is_wayland() -> bool:
    return bool(os.environ.get("WAYLAND_DISPLAY"))


def _read_command() -> list[str]:
    if sys.platform == "darwin":
        return ["pbpaste"]
    if sys.platform.startswith("win"):
        return ["powershell", "-NoProfile", "-Command", "Get-Clipboard"]
    if _is_wayland():
        return ["wl-paste", "--no-newline"]
    return ["xclip", "-selection", "clipboard", "-out"]


def _write_command() -> list[str]:
    if sys.platform == "darwin":
        return ["pbcopy"]
    if sys.platform.startswith("win"):
        return ["clip"]
    if _is_wayland():
        return ["wl-copy"]
    return ["xclip", "-selection", "clipboard", "-in"]


def read_clipboard() -> str:
    """Lit le presse-papier courant de l'OS (texte). Chaîne vide si vide."""
    cmd = _read_command()
    try:
        result = subprocess.run(  # noqa: S603
            cmd, capture_output=True, env=_desktop_env(), timeout=5
        )
    except FileNotFoundError as exc:
        raise ClipboardError(f"Outil presse-papier « {cmd[0]} » introuvable.") from exc
    except subprocess.TimeoutExpired as exc:
        raise ClipboardError("Lecture du presse-papier expirée.") from exc

    # wl-paste / xclip sortent en erreur quand le presse-papier est vide : on
    # renvoie alors une chaîne vide plutôt qu'une exception.
    return result.stdout.decode("utf-8", errors="replace")


def write_clipboard(text: str) -> None:
    """Écrit [text] dans le presse-papier de l'OS. Throws ClipboardError."""
    data = text.encode("utf-8")
    if len(data) > MAX_CLIPBOARD_BYTES:
        raise ClipboardError(
            f"Contenu trop volumineux ({len(data)} o > {MAX_CLIPBOARD_BYTES} o)."
        )

    cmd = _write_command()
    try:
        result = subprocess.run(  # noqa: S603
            cmd, input=data, env=_desktop_env(), timeout=5
        )
    except FileNotFoundError as exc:
        raise ClipboardError(f"Outil presse-papier « {cmd[0]} » introuvable.") from exc
    except subprocess.TimeoutExpired as exc:
        raise ClipboardError("Écriture du presse-papier expirée.") from exc

    if result.returncode != 0:
        raise ClipboardError(f"Échec d'écriture du presse-papier (code {result.returncode}).")
