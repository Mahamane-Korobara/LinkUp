"""Unit tests for Linkup mDNS presence and cleanup."""

from datetime import UTC, datetime, timedelta

import pytest

from app.services import mdns as mdns_module
from app.services.mdns import SERVICE_TYPE, DiscoveredAgent, LinkupAnnouncer, LinkupBrowser


def test_discovered_agent_helpers():
    agent = DiscoveredAgent(
        name="a.linkup._tcp.local.",
        host="laptop.local.",
        addresses=["192.168.1.10"],
        port=8080,
        properties={"fp": "abc12345", "v": "0.1.0", "id": "linkup-xyz", "bridge_port": "8765"},
    )

    assert agent.fingerprint == "abc12345"
    assert agent.version == "0.1.0"
    assert agent.bridge_port == 8765
    assert agent.health_url == "http://192.168.1.10:8765/health"


def test_announcer_info_before_start(monkeypatch):
    monkeypatch.setattr(mdns_module, "_local_ip", lambda: "192.168.1.42")
    announcer = LinkupAnnouncer(port=8080, bridge_port=8765, fingerprint="abc12345")
    info = announcer.info()

    assert info["registered"] is False
    assert info["fingerprint"] == "abc12345"
    assert info["port"] == 8080
    assert info["bridge_port"] == 8765
    assert info["agent_id"].startswith("linkup-")
    assert info["host"].endswith(".local.")


@pytest.mark.asyncio
async def test_browser_starts_empty(monkeypatch):
    class DummyAsyncZeroconf:
        def __init__(self, *args, **kwargs):
            self.zeroconf = object()

        async def async_close(self):
            return None

    class DummyAsyncServiceBrowser:
        def __init__(self, *args, **kwargs):
            return None

        async def async_cancel(self):
            return None

    class DummyAsyncClient:
        def __init__(self, *args, **kwargs):
            return None

        async def aclose(self):
            return None

    monkeypatch.setattr(mdns_module, "AsyncZeroconf", DummyAsyncZeroconf)
    monkeypatch.setattr(mdns_module, "AsyncServiceBrowser", DummyAsyncServiceBrowser)
    monkeypatch.setattr(mdns_module.httpx, "AsyncClient", DummyAsyncClient)

    browser = LinkupBrowser(heartbeat_interval_seconds=60)
    await browser.start()
    try:
        assert browser.list_agents() == []
    finally:
        await browser.stop()


@pytest.mark.asyncio
async def test_probe_agent_updates_last_seen():
    class DummyResponse:
        def raise_for_status(self):
            return None

        def json(self):
            return {"status": "alive"}

    class DummyAsyncClient:
        async def get(self, url):
            return DummyResponse()

    browser = LinkupBrowser()
    browser._client = DummyAsyncClient()
    browser._agents["agent-1"] = DiscoveredAgent(
        name="agent-1._linkup._tcp.local.",
        host="agent-1.local.",
        addresses=["127.0.0.1"],
        port=8080,
        properties={"bridge_port": "8765"},
        last_seen=(datetime.now(UTC) - timedelta(seconds=30)).isoformat(),
    )

    await browser._probe_agent("agent-1")

    refreshed_at = datetime.fromisoformat(browser._agents["agent-1"].last_seen)
    assert refreshed_at > datetime.now(UTC) - timedelta(seconds=5)


def test_list_agents_purges_stale_entries():
    browser = LinkupBrowser(stale_after_seconds=15)
    browser._agents["fresh"] = DiscoveredAgent(
        name="fresh._linkup._tcp.local.",
        host="fresh.local.",
        addresses=["192.168.1.10"],
        port=8080,
        properties={"bridge_port": "8765"},
        last_seen=(datetime.now(UTC) - timedelta(seconds=5)).isoformat(),
    )
    browser._agents["stale"] = DiscoveredAgent(
        name="stale._linkup._tcp.local.",
        host="stale.local.",
        addresses=["192.168.1.11"],
        port=8080,
        properties={"bridge_port": "8765"},
        last_seen=(datetime.now(UTC) - timedelta(seconds=20)).isoformat(),
    )

    agents = browser.list_agents()

    assert len(agents) == 1
    assert agents[0]["name"] == "fresh._linkup._tcp.local."


def test_service_type_constant():
    assert SERVICE_TYPE == "_linkup._tcp.local."
