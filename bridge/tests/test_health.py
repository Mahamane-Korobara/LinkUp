from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_returns_ok():
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "version" in body
    assert "os" in body


def test_system_info_requires_token():
    response = client.get("/system/info")
    assert response.status_code == 401


def test_system_info_rejects_bad_token():
    response = client.get("/system/info", headers={"Authorization": "Bearer wrong"})
    assert response.status_code == 401


def test_system_info_accepts_dev_token():
    response = client.get(
        "/system/info",
        headers={"Authorization": "Bearer dev-shared-token-change-me"},
    )
    assert response.status_code == 200
    assert "os" in response.json()
