"""Lance VideoHub via uvicorn (utilisé par supervisor sur le VPS).

    LINKUP_VIDEOHUB_HOST (défaut 127.0.0.1) — derrière le proxy Apache.
    LINKUP_VIDEOHUB_PORT (défaut 8780).
"""

import uvicorn

from app.config import settings
from app.main import app


def main() -> None:
    uvicorn.run(app, host=settings.host, port=settings.port)


if __name__ == "__main__":
    main()
