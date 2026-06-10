"""Injecte un token de service de test avant l'import des modules de l'app,
sinon `Settings()` refuse de démarrer (cf. config.py)."""

import os

os.environ.setdefault(
    "LINKUP_VIDEOHUB_SERVICE_TOKEN",
    "test-service-token-pytest-only-do-not-use",
)
# Pas de clé Gemini en test → le formatter reste sur le repli heuristique.
os.environ.setdefault("LINKUP_VIDEOHUB_GEMINI_API_KEY", "")
