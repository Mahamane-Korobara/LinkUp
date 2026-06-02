"""Point d'entrée du bridge en binaire autonome (PyInstaller).

Démarre uvicorn par code (pas en CLI `uvicorn app.main:app`) pour que le binaire
gelé n'ait besoin ni de Python ni des sources sur la machine cible.

Réglages via l'environnement :
  LINKUP_BRIDGE_HOST (défaut 127.0.0.1) — le bridge n'est appelé qu'en local.
  LINKUP_BRIDGE_PORT (défaut 8765).
"""

import os

import uvicorn

from app.main import app


def main() -> None:
    host = os.environ.get("LINKUP_BRIDGE_HOST", "127.0.0.1")
    port = int(os.environ.get("LINKUP_BRIDGE_PORT", "8765"))
    uvicorn.run(app, host=host, port=port)


if __name__ == "__main__":
    main()
