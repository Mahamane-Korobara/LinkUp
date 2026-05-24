# Linkup Bridge

OS bridge — piloted **locally** by the Laravel agent. Not exposed to the network directly.

## Quick start

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env
uvicorn app.main:app --reload --host 127.0.0.1 --port 8765
```

## Tests

```bash
pytest
ruff check .
black --check .
```

## Endpoints

- `GET /health` — public, status + version
- `GET /system/info` — bearer auth required (agent token)

More endpoints land brique by brique (cf. `docs/Linkup-Plan-Execution.md`).
