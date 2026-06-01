"""Tests S5 — presse-papier (multi-backend) + lien rapide (bridge)."""

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.deps import require_agent_token
from app.routes import clipboard as clipboard_routes
from app.services import clipboard as clip
from app.services import links


def make_client() -> TestClient:
    app = FastAPI()
    app.include_router(clipboard_routes.router)
    app.dependency_overrides[require_agent_token] = lambda: None
    return TestClient(app)


# ----------------------------------------------------------------- clipboard


def test_read_clipboard_decodes_utf8(monkeypatch):
    class _Result:
        stdout = "salut 👋 accentué".encode()
        returncode = 0

    monkeypatch.setattr(clip.shutil, "which", lambda _: "/usr/bin/xclip")
    monkeypatch.setattr(clip.subprocess, "run", lambda *a, **k: _Result())
    assert clip.read_clipboard() == "salut 👋 accentué"


def test_write_clipboard_pipes_stdin(monkeypatch):
    captured = {}

    class _Result:
        returncode = 0

    def fake_run(cmd, input=None, env=None, timeout=None):  # noqa: A002
        captured["cmd"] = cmd
        captured["input"] = input
        return _Result()

    monkeypatch.setattr(clip.shutil, "which", lambda _: "/usr/bin/wl-copy")
    monkeypatch.setattr(clip.subprocess, "run", fake_run)
    clip.write_clipboard("hello")
    assert captured["input"] == b"hello"


def test_picks_first_installed_backend(monkeypatch):
    # wl-copy absent, xclip présent → on doit choisir xclip.
    installed = {"xclip"}
    monkeypatch.setenv("WAYLAND_DISPLAY", "wayland-0")
    monkeypatch.setattr(clip.shutil, "which", lambda name: name if name in installed else None)
    write_cmd = clip._pick(clip._WRITE)
    assert write_cmd[0] == "xclip"


def test_write_clipboard_rejects_oversized(monkeypatch):
    monkeypatch.setattr(clip.shutil, "which", lambda _: "/usr/bin/xclip")
    with pytest.raises(clip.ClipboardError, match="volumineux"):
        clip.write_clipboard("x" * (clip.MAX_CLIPBOARD_BYTES + 1))


def test_clipboard_reports_no_tool_installed(monkeypatch):
    monkeypatch.setattr(clip.shutil, "which", lambda _: None)
    with pytest.raises(clip.ClipboardError, match="Aucun outil"):
        clip.read_clipboard()
    with pytest.raises(clip.ClipboardError, match="Aucun outil"):
        clip.write_clipboard("x")


# ----------------------------------------------------------------------- links


def test_open_url_rejects_dangerous_schemes():
    for bad in ["file:///etc/passwd", "javascript:alert(1)", "data:text/html,x", "ftp://h/x"]:
        with pytest.raises(links.LinkError):
            links.open_url(bad)


def test_open_url_accepts_https(monkeypatch):
    class _Proc:
        returncode = 0

        def communicate(self, timeout=None):
            return (b"", b"")

    monkeypatch.setattr(links.subprocess, "Popen", lambda *a, **k: _Proc())
    assert links.open_url("  https://example.com/a?b=1  ") == "https://example.com/a?b=1"


# ------------------------------------------------------------------ HTTP routes


def test_http_endpoints(monkeypatch):
    monkeypatch.setattr(clip, "read_clipboard", lambda: "clip-content")
    written: dict = {}
    monkeypatch.setattr(clip, "write_clipboard", lambda t: written.update(text=t))
    monkeypatch.setattr(links, "open_url", lambda u: u)
    client = make_client()

    assert client.get("/clipboard/read").json() == {"text": "clip-content"}

    assert client.post("/clipboard/write", json={"text": "hi"}).json() == {"ok": True}
    assert written["text"] == "hi"

    r = client.post("/link/open", json={"url": "https://x.com"})
    assert r.json() == {"ok": True, "url": "https://x.com"}


def test_http_link_open_rejects_bad_scheme():
    client = make_client()
    r = client.post("/link/open", json={"url": "file:///etc/passwd"})
    assert r.status_code == 422
