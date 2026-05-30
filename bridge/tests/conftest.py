"""Setup commun aux tests pytest.

Injecte un LINKUP_BRIDGE_AGENT_TOKEN de test avant l'import des modules de
l'app, sinon `Settings()` refuse de démarrer (cf. ADR-002 / config.py).
"""

import os

os.environ.setdefault(
    "LINKUP_BRIDGE_AGENT_TOKEN",
    "test-token-pytest-only-do-not-use-in-prod",
)
