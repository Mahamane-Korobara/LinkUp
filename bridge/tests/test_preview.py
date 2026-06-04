"""Tests Dev Preview — détection de ports + proxy transparent (bridge)."""

import asyncio
import socket
import sys

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.deps import require_agent_token
from app.routes import preview as preview_routes
from app.services.preview import ProxyError, ProxyManager, scan_listening_ports

linux_only = pytest.mark.skipif(
    not sys.platform.startswith("linux"), reason="scan via /proc (Linux uniquement)"
)


def make_client() -> TestClient:
    app = FastAPI()
    app.include_router(preview_routes.router)
    app.state.proxy_manager = ProxyManager(host="127.0.0.1")
    app.dependency_overrides[require_agent_token] = lambda: None
    return TestClient(app)


# ------------------------------------------------------------- détection ports


@linux_only
def test_scan_detects_a_listening_port():
    srv = socket.socket()
    srv.bind(("127.0.0.1", 0))
    srv.listen()
    port = srv.getsockname()[1]
    try:
        ports = {p.port for p in scan_listening_ports()}
        assert port in ports
    finally:
        srv.close()


@linux_only
def test_scan_honors_exclude():
    srv = socket.socket()
    srv.bind(("127.0.0.1", 0))
    srv.listen()
    port = srv.getsockname()[1]
    try:
        ports = {p.port for p in scan_listening_ports(exclude={port})}
        assert port not in ports
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

        exposed = client.get("/preview/exposed").json()["exposed"]
        assert any(e["target_port"] == target for e in exposed)

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


@linux_only
def test_list_ports_route():
    srv = socket.socket()
    srv.bind(("127.0.0.1", 0))
    srv.listen()
    port = srv.getsockname()[1]
    client = make_client()
    try:
        ports = client.get("/preview/ports").json()["ports"]
        assert any(p["port"] == port for p in ports)
    finally:
        srv.close()
