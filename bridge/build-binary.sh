#!/usr/bin/env bash
# Construit le bridge en binaire autonome (PyInstaller).
#
# Produit dist/linkup-bridge : un exécutable unique qui n'exige NI Python NI les
# sources sur la machine cible. À lancer une fois par OS cible (le binaire n'est
# pas cross-platform : binaire Linux sur Linux, .exe sur Windows).
#
# Prérequis : un venv avec les dépendances du bridge + pyinstaller.
set -euo pipefail
cd "$(dirname "$0")"

PY="${PY:-.venv/bin/python}"
[ -x "$PY" ] || { echo "venv introuvable ($PY). Crée-le : python3 -m venv .venv && .venv/bin/pip install . pyinstaller"; exit 1; }

"$PY" -m PyInstaller \
  --onefile --noconfirm --clean \
  --name linkup-bridge \
  --collect-all uvicorn \
  --collect-all zeroconf \
  --collect-submodules app \
  --hidden-import app.main \
  run.py

echo "✓ Binaire : $(pwd)/dist/linkup-bridge"
