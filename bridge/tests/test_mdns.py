"""Integration test: two LinkupAnnouncer instances see each other via LinkupBrowser."""

import asyncio

import pytest

from app.services.mdns import SERVICE_TYPE, DiscoveredAgent, LinkupAnnouncer, LinkupBrowser


def test_discovered_agent_helpers():
    agent = DiscoveredAgent(
        name="a.linkup._tcp.local.",
        host="laptop.local.",
        addresses=["192.168.1.10"],
        port=8080,
        properties={"fp": "abc12345", "v": "0.1.0", "id": "linkup-xyz"},
    )

    assert agent.fingerprint == "abc12345"
    assert agent.version == "0.1.0"
    assert agent.addresses == ["192.168.1.10"]


def test_announcer_info_before_start():
    announcer = LinkupAnnouncer(port=8080, fingerprint="abc12345")
    info = announcer.info()

    assert info["registered"] is False
    assert info["fingerprint"] == "abc12345"
    assert info["port"] == 8080
    assert info["agent_id"].startswith("linkup-")
    assert info["host"].endswith(".local.")


@pytest.mark.asyncio
async def test_browser_starts_empty():
    browser = LinkupBrowser()
    await browser.start()
    try:
        # Just started: no agents resolved yet
        assert browser.list_agents() == []
    finally:
        await browser.stop()


@pytest.mark.asyncio
async def test_announcer_and_browser_see_each_other():
    """E2E : start one announcer + browser, the browser should resolve it."""
    announcer = LinkupAnnouncer(
        port=18080,
        agent_id="linkup-test-aaaa",
        fingerprint="testfp01",
        instance_name="linkup-test-aaaa._linkup._tcp.local.",
    )
    browser = LinkupBrowser()

    await announcer.start()
    await browser.start()
    try:
        # Wait up to 5s for the browser to resolve the announcement
        for _ in range(50):
            agents = browser.list_agents()
            if any(a["name"].startswith("linkup-test-aaaa") for a in agents):
                break
            await asyncio.sleep(0.1)
        else:
            pytest.fail("Browser did not discover announcer within 5s")

        found = [a for a in browser.list_agents() if a["name"].startswith("linkup-test-aaaa")][0]
        assert found["port"] == 18080
        assert found["properties"].get("fp") == "testfp01"
        assert found["properties"].get("id") == "linkup-test-aaaa"
        assert len(found["addresses"]) >= 1
    finally:
        await browser.stop()
        await announcer.stop()


def test_service_type_constant():
    assert SERVICE_TYPE == "_linkup._tcp.local."
