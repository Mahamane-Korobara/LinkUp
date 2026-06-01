"""Accès au presse-papier de l'OS (S5 — module presse-papier).

Cibles : Linux + Windows (cf. CDC). Aucune dépendance Python : on shell-out vers
les outils natifs, en essayant plusieurs backends et en prenant le PREMIER
installé.

- Windows : `clip` (write) / PowerShell `Get-Clipboard` (read) — intégrés à l'OS,
  donc zéro installation.
- Linux   : Wayland `wl-copy`/`wl-paste`, X11 `xclip` ou `xsel`. Au moins UN doit
  être présent (fourni par l'installeur S6.5 : `wl-clipboard | xclip`).

Note : on ne tente PAS GTK/PyGObject. Sous X11/Wayland, le presse-papier
appartient à un process VIVANT qui sert la donnée à la demande ; un endpoint
HTTP synchrone ne peut pas tenir cette propriété, alors que `wl-copy`/`xclip`
forkent un daemon dédié pour ça. Les CLI sont donc le bon choix côté serveur.

L'environnement est nettoyé des variables snap (cf. transfer._desktop_env) :
le bridge peut tourner dans un terminal confiné (VS Code).
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys

from app.services.transfer import _desktop_env

# Le presse-papier n'est pas un canal de transfert de fichier : on plafonne.
MAX_CLIPBOARD_BYTES = 1024 * 1024  # 1 Mo

# Index dans un couple (write_cmd, read_cmd).
_WRITE = 0
_READ = 1


class ClipboardError(Exception):
    """Échec d'accès au presse-papier de l'OS."""


def _candidates() -> list[tuple[list[str], list[str]]]:
    """Backends (write_cmd, read_cmd) par plateforme, par ordre de préférence."""
    if sys.platform.startswith("win"):
        return [(["clip"], ["powershell", "-NoProfile", "-Command", "Get-Clipboard"])]

    wl = (["wl-copy"], ["wl-paste", "--no-newline"])
    xclip = (
        ["xclip", "-selection", "clipboard", "-in"],
        ["xclip", "-selection", "clipboard", "-out"],
    )
    xsel = (["xsel", "--clipboard", "--input"], ["xsel", "--clipboard", "--output"])

    # En session Wayland, wl-clipboard d'abord ; sinon les outils X11.
    if os.environ.get("WAYLAND_DISPLAY"):
        return [wl, xclip, xsel]
    return [xclip, xsel, wl]


def _pick(slot: int) -> list[str]:
    """Première commande dont l'outil est installé (slot = _WRITE ou _READ)."""
    for pair in _candidates():
        cmd = pair[slot]
        if shutil.which(cmd[0]) is not None:
            return cmd
    raise ClipboardError(
        "Aucun outil presse-papier trouvé. Installe l'un de : "
        "wl-clipboard (Wayland), xclip ou xsel (X11)."
    )


def read_clipboard() -> str:
    """Lit le presse-papier courant de l'OS (texte). Chaîne vide si vide."""
    cmd = _pick(_READ)
    try:
        result = subprocess.run(  # noqa: S603
            cmd, capture_output=True, env=_desktop_env(), timeout=5
        )
    except subprocess.TimeoutExpired as exc:
        raise ClipboardError("Lecture du presse-papier expirée.") from exc

    # wl-paste / xclip sortent parfois en erreur quand le presse-papier est vide :
    # on renvoie alors une chaîne vide plutôt qu'une exception.
    return result.stdout.decode("utf-8", errors="replace")


def write_clipboard(text: str) -> None:
    """Écrit [text] dans le presse-papier de l'OS. Throws ClipboardError."""
    data = text.encode("utf-8")
    if len(data) > MAX_CLIPBOARD_BYTES:
        raise ClipboardError(
            f"Contenu trop volumineux ({len(data)} o > {MAX_CLIPBOARD_BYTES} o)."
        )

    cmd = _pick(_WRITE)
    try:
        result = subprocess.run(  # noqa: S603
            cmd, input=data, env=_desktop_env(), timeout=5
        )
    except subprocess.TimeoutExpired as exc:
        raise ClipboardError("Écriture du presse-papier expirée.") from exc

    if result.returncode != 0:
        raise ClipboardError(f"Échec d'écriture du presse-papier (code {result.returncode}).")
