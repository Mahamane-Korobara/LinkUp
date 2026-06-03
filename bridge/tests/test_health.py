from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.main import health, require_agent_token, system_info


def test_health_returns_alive():
    request = SimpleNamespace(
        app=SimpleNamespace(
            state=SimpleNamespace(
                mdns_announcer=SimpleNamespace(agent_id="linkup-test-1234"),
            )
        )
    )

    body = health(request)

    assert body["status"] == "alive"
    assert body["service"] == "linkup-bridge"
    assert body["agent_id"] == "linkup-test-1234"
    assert "timestamp" in body
    assert "version" in body
    assert "os" in body
    # Le tél lit ce port pour bâtir /api/agent/info sans coder 8000 en dur.
    assert body["laravel_port"] == 8000


def test_system_info_requires_token():
    with pytest.raises(HTTPException) as exc:
        require_agent_token(None)

    assert exc.value.status_code == 401


def test_system_info_rejects_bad_token():
    with pytest.raises(HTTPException) as exc:
        require_agent_token("Bearer wrong")

    assert exc.value.status_code == 401


def test_system_info_accepts_dev_token():
    require_agent_token("Bearer test-token-pytest-only-do-not-use-in-prod")

    body = system_info()
    assert "os" in body
