"""Tests Dev Preview — détection de ports + proxy transparent (bridge)."""

import asyncio
import socket
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.deps import require_agent_token
from app.routes import preview as preview_routes
from app.services import preview as preview_service
from app.services.preview import (
    ListeningPort,
    ProxyError,
    ProxyManager,
    filter_http_ports,
    route_and_rewrite,
    scan_listening_ports,
)


class _QuietHandler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):  # silence
        pass


def start_http_server() -> tuple[HTTPServer, int]:
    """Vrai serveur HTTP sur un port de la plage dev (pour passer le filtre HTTP)."""
    for port in range(20000, 20200):
        try:
            srv = HTTPServer(("127.0.0.1", port), _QuietHandler)
        except OSError:
            continue
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        return srv, port
    raise RuntimeError("aucun port dev libre pour le serveur HTTP de test")

linux_only = pytest.mark.skipif(
    not sys.platform.startswith("linux"), reason="scan via /proc (Linux uniquement)"
)


# Empreinte factice (64 hex) : les routes /exposed et /expose la relaient telle
# quelle, on vérifie juste sa présence côté API. La correction de l'empreinte
# réelle est couverte par test_server_fingerprint_matches_cert.
_FAKE_CERT_SHA256 = "ab" * 32


class _FakeCertManager:
    def server_fingerprint_sha256(self) -> str:
        return _FAKE_CERT_SHA256


def make_client(cert_manager: object | None = None) -> TestClient:
    app = FastAPI()
    app.include_router(preview_routes.router)
    app.state.proxy_manager = ProxyManager(host="127.0.0.1")
    app.state.cert_manager = cert_manager or _FakeCertManager()
    app.dependency_overrides[require_agent_token] = lambda: None
    return TestClient(app)


def listen_dev_port() -> socket.socket:
    """Socket en écoute sur un port LIBRE dans la plage dev [1024, 32768).

    Nécessaire car `scan_listening_ports` filtre les ports éphémères (>= 32768) :
    bind(0) donnerait justement un port éphémère, invisible au scan.
    """
    for port in range(20000, 20200):
        srv = socket.socket()
        try:
            srv.bind(("127.0.0.1", port))
            srv.listen()
            return srv
        except OSError:
            srv.close()
    raise RuntimeError("aucun port dev libre pour le test")


# ------------------------------------------------------------- détection ports


@linux_only
def test_scan_detects_a_listening_port():
    srv = listen_dev_port()
    port = srv.getsockname()[1]
    try:
        ports = {p.port for p in scan_listening_ports()}
        assert port in ports
    finally:
        srv.close()


@linux_only
def test_scan_honors_exclude():
    srv = listen_dev_port()
    port = srv.getsockname()[1]
    try:
        ports = {p.port for p in scan_listening_ports(exclude={port})}
        assert port not in ports
    finally:
        srv.close()


@linux_only
def test_scan_filters_system_and_infra_ports():
    # Un port d'infra (Redis 6379) ou éphémère ne doit jamais apparaître, même
    # s'il écoute. On vérifie qu'un port éphémère bind(0) est bien masqué.
    srv = socket.socket()
    srv.bind(("127.0.0.1", 0))  # port éphémère >= 32768
    srv.listen()
    ephemeral = srv.getsockname()[1]
    try:
        ports = {p.port for p in scan_listening_ports()}
        assert ephemeral not in ports
        assert all(1024 <= p < 32768 for p in ports)
    finally:
        srv.close()


# --------------------------------------------------------------- ProxyManager


async def test_proxy_relays_bytes_both_ways():
    async def handle(reader, writer):
        data = await reader.read(100)
        writer.write(b"echo:" + data)
        await writer.drain()
        writer.close()

    backend = await asyncio.start_server(handle, "127.0.0.1", 0)
    target = backend.sockets[0].getsockname()[1]
    manager = ProxyManager(host="127.0.0.1")
    try:
        info = await manager.expose(target)
        assert info.target_port == target
        assert info.listen_port > 0

        reader, writer = await asyncio.open_connection("127.0.0.1", info.listen_port)
        writer.write(b"hello")
        await writer.drain()
        out = await reader.read(100)
        assert out == b"echo:hello"
        writer.close()
    finally:
        await manager.shutdown()
        backend.close()
        await backend.wait_closed()


async def test_expose_is_idempotent():
    backend = await asyncio.start_server(lambda r, w: w.close(), "127.0.0.1", 0)
    target = backend.sockets[0].getsockname()[1]
    manager = ProxyManager(host="127.0.0.1")
    try:
        first = await manager.expose(target)
        second = await manager.expose(target)
        assert first.listen_port == second.listen_port
        assert len(manager.list()) == 1
    finally:
        await manager.shutdown()
        backend.close()
        await backend.wait_closed()


async def test_expose_unreachable_port_raises():
    probe = socket.socket()
    probe.bind(("127.0.0.1", 0))
    free_port = probe.getsockname()[1]
    probe.close()  # plus rien n'écoute sur ce port

    manager = ProxyManager(host="127.0.0.1")
    with pytest.raises(ProxyError):
        await manager.expose(free_port)


async def test_unexpose_unknown_returns_false():
    manager = ProxyManager(host="127.0.0.1")
    assert await manager.unexpose(12345) is False


# ------------------------------------------ routage single-origin (route_and_rewrite)


def test_route_default_no_prefix_forces_connection_close():
    req = b"GET /api/users HTTP/1.1\r\nHost: x\r\nConnection: keep-alive\r\n\r\n"
    dest, out = route_and_rewrite(3000, {3000, 8000}, req)
    assert dest == 3000  # pas de préfixe → port du listener
    assert b"GET /api/users HTTP/1.1" in out  # path inchangé
    assert b"Connection: close" in out
    assert b"keep-alive" not in out  # ancien Connection retiré


def test_route_prefix_to_exposed_strips_and_routes():
    req = b"GET /__linkup/8000/api/ping HTTP/1.1\r\nHost: x\r\n\r\n"
    dest, out = route_and_rewrite(3000, {3000, 8000}, req)
    assert dest == 8000  # routé vers l'autre service exposé
    assert out.startswith(b"GET /api/ping HTTP/1.1\r\n")  # préfixe /__linkup/8000 retiré
    assert b"Connection: close" in out


def test_route_prefix_bare_port_becomes_root():
    req = b"GET /__linkup/8000 HTTP/1.1\r\nHost: x\r\n\r\n"
    dest, out = route_and_rewrite(3000, {8000}, req)
    assert dest == 8000
    assert out.startswith(b"GET / HTTP/1.1\r\n")


def test_route_prefix_to_unexposed_falls_back_to_default():
    req = b"GET /__linkup/9999/x HTTP/1.1\r\nHost: x\r\n\r\n"
    dest, out = route_and_rewrite(3000, {3000, 8000}, req)
    assert dest == 3000  # 9999 pas exposé → port du listener
    assert out.startswith(b"GET /__linkup/9999/x HTTP/1.1\r\n")  # path inchangé (404 côté app)


def test_route_websocket_upgrade_preserved():
    req = (
        b"GET /__linkup/8000/socket HTTP/1.1\r\nHost: x\r\n"
        b"Upgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
    )
    dest, out = route_and_rewrite(3000, {8000}, req)
    assert dest == 8000
    assert out.startswith(b"GET /socket HTTP/1.1\r\n")  # préfixe strippé
    assert b"Upgrade: websocket" in out
    assert b"Connection: Upgrade" in out  # handshake intact
    assert b"Connection: close" not in out


def test_route_non_http_passthrough():
    junk = b"\x16\x03\x01 not http at all"
    dest, out = route_and_rewrite(3000, {3000}, junk)
    assert dest == 3000
    assert out == junk  # renvoyé tel quel


def _make_http_backend(tag: str):
    """Backend HTTP minimal qui renvoie `<tag> <path-reçu>` (pour vérifier le routage)."""

    async def handle(reader, writer):
        data = await reader.readuntil(b"\r\n\r\n")
        path = data.split(b"\r\n", 1)[0].split(b" ")[1]
        body = tag.encode() + b" " + path
        writer.write(
            b"HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % len(body)
            + body
        )
        await writer.drain()
        writer.close()

    return handle


async def _http_get(listen_port: int, path: str) -> bytes:
    reader, writer = await asyncio.open_connection("127.0.0.1", listen_port)
    writer.write(f"GET {path} HTTP/1.1\r\nHost: x\r\n\r\n".encode())
    await writer.drain()
    out = await reader.read(4096)
    writer.close()
    return out


async def test_single_origin_prefix_reaches_other_exposed_service():
    front = await asyncio.start_server(_make_http_backend("front"), "127.0.0.1", 0)
    back = await asyncio.start_server(_make_http_backend("back"), "127.0.0.1", 0)
    front_port = front.sockets[0].getsockname()[1]
    back_port = back.sockets[0].getsockname()[1]
    manager = ProxyManager(host="127.0.0.1")
    try:
        front_info = await manager.expose(front_port)
        await manager.expose(back_port)

        # Racine → le projet du listener (le front).
        root = await _http_get(front_info.listen_port, "/")
        assert b"front /" in root

        # Préfixe → l'autre service exposé (le back), préfixe retiré.
        api = await _http_get(front_info.listen_port, f"/__linkup/{back_port}/api/ping")
        assert b"back /api/ping" in api
    finally:
        await manager.shutdown()
        front.close()
        back.close()
        await front.wait_closed()
        await back.wait_closed()


# ------------------------------------------------------------------ HTTP routes


def test_expose_list_unexpose_flow():
    srv = socket.socket()
    srv.bind(("127.0.0.1", 0))
    srv.listen()
    target = srv.getsockname()[1]
    client = make_client()
    try:
        r = client.post("/preview/expose", json={"port": target})
        assert r.status_code == 200
        body = r.json()
        assert body["target_port"] == target
        assert body["listen_port"] > 0
        # Empreinte à épingler côté tél, relayée par /expose ET /exposed.
        assert body["cert_sha256"] == _FAKE_CERT_SHA256

        listing = client.get("/preview/exposed").json()
        assert listing["cert_sha256"] == _FAKE_CERT_SHA256
        assert any(e["target_port"] == target for e in listing["exposed"])

        assert client.post("/preview/unexpose", json={"port": target}).json() == {"ok": True}
    finally:
        srv.close()


def test_expose_unreachable_returns_404():
    probe = socket.socket()
    probe.bind(("127.0.0.1", 0))
    free_port = probe.getsockname()[1]
    probe.close()

    client = make_client()
    r = client.post("/preview/expose", json={"port": free_port})
    assert r.status_code == 404


def test_server_fingerprint_matches_cert(tmp_path):
    """L'empreinte exposée = SHA-256 du DER du cert serveur (vérif indépendante)."""
    import hashlib

    from cryptography import x509
    from cryptography.hazmat.primitives import serialization

    from app.services.cert import CertManager

    mgr = CertManager(ca_dir=tmp_path)
    mgr.ensure()
    fingerprint = mgr.server_fingerprint_sha256()

    cert = x509.load_pem_x509_certificate(mgr.server_cert_path.read_bytes())
    expected = hashlib.sha256(cert.public_bytes(serialization.Encoding.DER)).hexdigest()
    assert fingerprint == expected
    assert len(fingerprint) == 64 and all(c in "0123456789abcdef" for c in fingerprint)


@linux_only
def test_list_ports_route():
    # Le serveur DOIT parler HTTP, sinon le filtre HTTP de la route l'écarte.
    srv, port = start_http_server()
    preview_service._http_cache.clear()
    client = make_client()
    try:
        ports = client.get("/preview/ports").json()["ports"]
        assert any(p["port"] == port for p in ports)
    finally:
        srv.shutdown()


async def test_filter_http_ports_keeps_http_drops_non_http():
    preview_service._http_cache.clear()
    http_srv, http_port = start_http_server()

    # Serveur qui écoute mais ne parle PAS HTTP (façon démon java/IDE).
    async def silent(reader, writer):
        await asyncio.sleep(1.5)
        writer.close()

    raw_srv = await asyncio.start_server(silent, "127.0.0.1", 0)
    raw_port = raw_srv.sockets[0].getsockname()[1]
    try:
        kept = await filter_http_ports([
            ListeningPort(port=http_port, process="next-server"),
            ListeningPort(port=raw_port, process="java"),
        ])
        kept_ports = {p.port for p in kept}
        assert http_port in kept_ports  # vrai serveur HTTP → gardé
        assert raw_port not in kept_ports  # n'a pas répondu en HTTP → écarté
    finally:
        http_srv.shutdown()
        raw_srv.close()
        await raw_srv.wait_closed()


async def test_listen_port_is_stable_across_restarts(tmp_path):
    # URL stable : un projet ré-exposé après redémarrage garde le même port.
    state = tmp_path / "preview_ports.json"
    backend = await asyncio.start_server(lambda r, w: w.close(), "127.0.0.1", 0)
    target = backend.sockets[0].getsockname()[1]
    try:
        mgr1 = ProxyManager(host="127.0.0.1", state_file=state)
        first = (await mgr1.expose(target)).listen_port
        await mgr1.shutdown()  # « redémarrage » : on libère le port

        mgr2 = ProxyManager(host="127.0.0.1", state_file=state)
        second = (await mgr2.expose(target)).listen_port
        await mgr2.shutdown()

        assert first == second  # même port repris depuis le state persistant
    finally:
        backend.close()
        await backend.wait_closed()
