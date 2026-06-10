import pytest

from app.services import formatter


@pytest.mark.asyncio
async def test_no_key_falls_back_to_heuristic(monkeypatch):
    monkeypatch.setattr(formatter.settings, "gemini_api_key", "")
    doc = await formatter.format_transcript("Titre", ["para un", "para deux"])
    assert doc["formatted_by"] == "heuristic"
    assert doc["title"] == "Titre"
    assert doc["sections"][0]["paragraphs"] == ["para un", "para deux"]


@pytest.mark.asyncio
async def test_empty_paragraphs(monkeypatch):
    monkeypatch.setattr(formatter.settings, "gemini_api_key", "")
    doc = await formatter.format_transcript("T", [])
    assert doc["formatted_by"] == "heuristic"
    assert doc["sections"][0]["paragraphs"] == []


def test_coerce_rejects_malformed_and_falls_back():
    # Réponse Gemini sans sections valides → repli heuristique.
    out = formatter._coerce({"title": "X", "sections": "pas une liste"}, "T", ["p"])
    assert out["formatted_by"] == "heuristic"


def test_coerce_accepts_valid_structure():
    payload = {
        "title": "Mon doc",
        "sections": [{"heading": "Intro", "paragraphs": ["Bonjour.", "  "]}],
    }
    out = formatter._coerce(payload, "T", ["p"])
    assert out["formatted_by"] == "gemini"
    assert out["title"] == "Mon doc"
    assert out["sections"][0]["heading"] == "Intro"
    assert out["sections"][0]["paragraphs"] == ["Bonjour."]
