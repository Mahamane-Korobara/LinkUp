"""Tests d'integration mDNS reels (zeroconf + heartbeat HTTP).

Ces tests demarrent de vrais services Zeroconf sur la machine et verifient
que la decouverte bidirectionnelle fonctionne bout-a-bout. Ils sont plus
lents que les unit tests et dependent d'un stack reseau avec multicast
fonctionnel.

Pour les sauter dans un environnement restreint (CI sandbox, container
sans multicast), exporter `LINKUP_SKIP_INTEGRATION=1`.
"""

from __future__ import annotations

import asyncio
import os
import uuid
from collections.abc import Awaitable, Callable

import pytest
import uvicorn
from fastapi import FastAPI

from app.services.mdns import LinkupAnnouncer, LinkupBrowser

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(
        os.environ.get("LINKUP_SKIP_INTEGRATION") == "1",
        reason="LINKUP_SKIP_INTEGRATION=1",
    ),
]


async def _wait_for(
    predicate: Callable[[], bool],
    *,
    timeout: float = 10.0,
    interval: float = 0.2,
) -> bool:
    """Attend qu'un predicat devienne vrai ou expire."""
    loop = asyncio.get_event_loop()
    deadline = loop.time() + timeout
    while loop.time() < deadline:
        if predicate():
            return True
        await asyncio.sleep(interval)
    return predicate()


# ============================================================
# 1. Decouverte d'un agent annonce sur le LAN
# ============================================================


async def test_browser_discovers_real_announcer():
    """Un browser doit voir un announcer qui tourne sur la meme machine."""
    suffix = uuid.uuid4().hex[:6]
    announcer = LinkupAnnouncer(
        port=18080,
        bridge_port=18765,
        agent_id=f"linkup-it-{suffix}",
        fingerprint=f"fp-{suffix}",
        version="0.1.0",
    )
    browser = LinkupBrowser(
        heartbeat_interval_seconds=60.0,
        stale_after_seconds=120.0,
    )

    await announcer.start()
    await browser.start()

    try:
        found = await _wait_for(
            lambda: any(
                agent["properties"].get("id") == announcer.agent_id
                for agent in browser.list_agents()
            ),
            timeout=10.0,
        )
        assert found, (
            f"Annonce {announcer.agent_id} non vue par le browser. "
            f"Etat actuel : {browser.list_agents()}"
        )
    finally:
        await browser.stop()
        await announcer.stop()


# ============================================================
# 2. Decouverte de deux annonces simultanees
# ============================================================


async def test_two_announcers_visible_to_browser():
    """Deux announcers en parallele doivent etre tous deux visibles."""
    suffix_a = uuid.uuid4().hex[:6]
    suffix_b = uuid.uuid4().hex[:6]

    announcer_a = LinkupAnnouncer(
        port=18090,
        bridge_port=18791,
        agent_id=f"linkup-it-a-{suffix_a}",
        fingerprint=f"fp-a-{suffix_a}",
    )
    announcer_b = LinkupAnnouncer(
        port=18091,
        bridge_port=18792,
        agent_id=f"linkup-it-b-{suffix_b}",
        fingerprint=f"fp-b-{suffix_b}",
    )
    browser = LinkupBrowser(
        heartbeat_interval_seconds=60.0,
        stale_after_seconds=120.0,
    )

    await announcer_a.start()
    await announcer_b.start()
    await browser.start()

    expected_ids = {announcer_a.agent_id, announcer_b.agent_id}

    try:

        def both_seen() -> bool:
            ids = {a["properties"].get("id") for a in browser.list_agents()}
            return expected_ids.issubset(ids)

        ok = await _wait_for(both_seen, timeout=15.0)
        assert ok, (
            "Les deux announcers n'ont pas ete decouverts. "
            f"Vus : {[a['properties'].get('id') for a in browser.list_agents()]}"
        )
    finally:
        await browser.stop()
        await announcer_a.stop()
        await announcer_b.stop()


# ============================================================
# 3. Heartbeat HTTP reel + purge apres TTL
# ============================================================


def _make_health_app(status: str = "alive") -> FastAPI:
    """Cree une mini app FastAPI qui imite le /health du bridge."""
    app = FastAPI()

    @app.get("/health")
    def health() -> dict:
        return {"status": status, "service": "linkup-bridge-fake"}

    return app


async def _run_uvicorn(app: FastAPI, port: int) -> tuple[uvicorn.Server, asyncio.Task]:
    """Lance uvicorn sur 127.0.0.1:<port> dans une tache asyncio."""
    config = uvicorn.Config(
        app,
        host="127.0.0.1",
        port=port,
        log_level="warning",
        access_log=False,
    )
    server = uvicorn.Server(config)
    task = asyncio.create_task(server.serve())

    started = await _wait_for(lambda: server.started, timeout=5.0, interval=0.05)
    if not started:
        task.cancel()
        raise RuntimeError(f"uvicorn n'a pas demarre sur 127.0.0.1:{port}")

    return server, task


async def _stop_uvicorn(server: uvicorn.Server, task: asyncio.Task) -> None:
    server.should_exit = True
    try:
        await asyncio.wait_for(task, timeout=5.0)
    except TimeoutError:
        task.cancel()


async def _with_health_server(
    port: int,
    action: Callable[[], Awaitable[None]],
    status: str = "alive",
) -> None:
    server, task = await _run_uvicorn(_make_health_app(status), port)
    try:
        await action()
    finally:
        await _stop_uvicorn(server, task)


async def test_heartbeat_refreshes_last_seen_against_real_http():
    """Un agent qui repond a /health doit voir son last_seen rafraichi."""
    from datetime import UTC, datetime, timedelta

    from app.services.mdns import DiscoveredAgent

    port = 18799
    browser = LinkupBrowser(
        heartbeat_interval_seconds=60.0,
        stale_after_seconds=120.0,
        healthcheck_timeout_seconds=2.0,
    )
    await browser.start()

    stale_iso = (datetime.now(UTC) - timedelta(seconds=60)).isoformat()
    browser._agents["fake-agent"] = DiscoveredAgent(
        name="fake-agent._linkup._tcp.local.",
        host="fake.local.",
        addresses=["127.0.0.1"],
        port=8080,
        properties={"bridge_port": str(port), "id": "fake-agent"},
        last_seen=stale_iso,
    )

    try:

        async def probe() -> None:
            await browser._probe_agent("fake-agent")
            refreshed = browser._agents["fake-agent"].last_seen
            assert refreshed != stale_iso, "last_seen n'a pas ete mis a jour"
            refreshed_dt = datetime.fromisoformat(refreshed)
            assert refreshed_dt > datetime.now(UTC) - timedelta(seconds=5)

        await _with_health_server(port, probe)
    finally:
        await browser.stop()
