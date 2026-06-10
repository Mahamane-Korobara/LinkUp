import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from app.services import extractor

AUTH = {"Authorization": f"Bearer {settings.service_token}"}


@pytest.fixture
def client():
    return TestClient(app)


def test_health_is_public(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["service"] == "linkup-videohub"


def test_video_requires_token(client):
    r = client.get("/video/resolve", params={"url": "https://x.test/v"})
    assert r.status_code == 401


def test_resolve_rejects_non_http(client):
    r = client.get("/video/resolve", params={"url": "ftp://nope"}, headers=AUTH)
    assert r.status_code == 400


def test_resolve_ok(monkeypatch, client):
    monkeypatch.setattr(
        extractor,
        "resolve",
        lambda url: {"title": "Démo", "has_subtitles": True, "subtitle_source": "manual"},
    )
    r = client.get(
        "/video/resolve", params={"url": "https://x.test/v"}, headers=AUTH
    )
    assert r.status_code == 200
    assert r.json()["title"] == "Démo"


def test_transcript_no_subtitles(monkeypatch, client):
    monkeypatch.setattr(
        extractor,
        "fetch_subtitle_vtt",
        lambda url, lang: {
            "available": False,
            "title": "Sans sous-titres",
            "reason": "Sous-titres non présents sur cette vidéo.",
        },
    )
    r = client.get(
        "/video/transcript", params={"url": "https://x.test/v"}, headers=AUTH
    )
    assert r.status_code == 200
    body = r.json()
    assert body["available"] is False
    assert "non présents" in body["reason"]


def test_transcript_formats_document(monkeypatch, client):
    monkeypatch.setattr(
        extractor,
        "fetch_subtitle_vtt",
        lambda url, lang: {
            "available": True,
            "vtt": "WEBVTT\n\n00:00:00.000 --> 00:00:02.000\nbonjour le monde\n",
            "source": "auto",
            "lang": "fr",
            "title": "Démo",
        },
    )
    r = client.get(
        "/video/transcript", params={"url": "https://x.test/v"}, headers=AUTH
    )
    assert r.status_code == 200
    body = r.json()
    assert body["available"] is True
    assert body["subtitle_source"] == "auto"
    assert body["formatted_by"] == "heuristic"  # pas de clé Gemini en test
    assert "bonjour le monde" in body["sections"][0]["paragraphs"][0]
