"""mDNS discovery for Linkup agents.

Bidirectional :
- LinkupAnnouncer registers the local agent as `_linkup._tcp.local`
- LinkupBrowser listens for other Linkup agents on the LAN
"""

from __future__ import annotations

import logging
import socket
import uuid
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime

from zeroconf import IPVersion, ServiceInfo, ServiceStateChange, Zeroconf
from zeroconf.asyncio import AsyncServiceBrowser, AsyncServiceInfo, AsyncZeroconf

logger = logging.getLogger(__name__)

SERVICE_TYPE = "_linkup._tcp.local."


@dataclass(slots=True)
class DiscoveredAgent:
    """A Linkup agent discovered on the LAN."""

    name: str
    host: str
    addresses: list[str]
    port: int
    properties: dict[str, str] = field(default_factory=dict)
    last_seen: str = field(default_factory=lambda: datetime.now(UTC).isoformat())

    @property
    def fingerprint(self) -> str | None:
        return self.properties.get("fp")

    @property
    def version(self) -> str | None:
        return self.properties.get("v")


def _local_ip() -> str:
    """Best-effort local IPv4 (the one used to reach the internet)."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


def _hostname() -> str:
    """Hostname used in the mDNS record (FQDN with `.local.` suffix)."""
    host = socket.gethostname().split(".")[0]
    return f"{host}.local."


class LinkupAnnouncer:
    """Register this agent on the LAN as `_linkup._tcp.local.`."""

    def __init__(
        self,
        port: int = 8080,
        agent_id: str | None = None,
        fingerprint: str | None = None,
        version: str = "0.1.0",
        instance_name: str | None = None,
    ) -> None:
        self.port = port
        self.agent_id = agent_id or f"linkup-{uuid.uuid4().hex[:8]}"
        self.fingerprint = fingerprint or "pending"
        self.version = version
        self.instance_name = instance_name or f"{self.agent_id}.{SERVICE_TYPE}"

        self._zc: AsyncZeroconf | None = None
        self._info: ServiceInfo | None = None

    async def start(self) -> None:
        if self._zc is not None:
            return

        ip = _local_ip()
        self._info = ServiceInfo(
            type_=SERVICE_TYPE,
            name=self.instance_name,
            addresses=[socket.inet_aton(ip)],
            port=self.port,
            properties={
                "id": self.agent_id,
                "v": self.version,
                "fp": self.fingerprint,
                "host": socket.gethostname(),
            },
            server=_hostname(),
        )

        self._zc = AsyncZeroconf(ip_version=IPVersion.V4Only)
        await self._zc.async_register_service(self._info)
        logger.info("mDNS announce: %s on %s:%s", self.instance_name, ip, self.port)

    async def stop(self) -> None:
        if self._zc is None:
            return
        try:
            if self._info is not None:
                await self._zc.async_unregister_service(self._info)
        finally:
            await self._zc.async_close()
            self._zc = None
            self._info = None
            logger.info("mDNS announce stopped")

    def info(self) -> dict:
        return {
            "registered": self._zc is not None,
            "instance_name": self.instance_name,
            "agent_id": self.agent_id,
            "fingerprint": self.fingerprint,
            "version": self.version,
            "port": self.port,
            "host": _hostname(),
            "ip": _local_ip(),
        }


class LinkupBrowser:
    """Listen for `_linkup._tcp.local.` services on the LAN."""

    def __init__(self) -> None:
        self._zc: AsyncZeroconf | None = None
        self._browser: AsyncServiceBrowser | None = None
        self._agents: dict[str, DiscoveredAgent] = {}

    async def start(self) -> None:
        if self._zc is not None:
            return
        self._zc = AsyncZeroconf(ip_version=IPVersion.V4Only)
        self._browser = AsyncServiceBrowser(
            self._zc.zeroconf,
            [SERVICE_TYPE],
            handlers=[self._on_change],
        )
        logger.info("mDNS browser started for %s", SERVICE_TYPE)

    async def stop(self) -> None:
        if self._browser is not None:
            await self._browser.async_cancel()
            self._browser = None
        if self._zc is not None:
            await self._zc.async_close()
            self._zc = None
        self._agents.clear()
        logger.info("mDNS browser stopped")

    def _on_change(
        self,
        *,
        zeroconf: Zeroconf,
        service_type: str,
        name: str,
        state_change: ServiceStateChange,
    ) -> None:
        if state_change is ServiceStateChange.Removed:
            removed = self._agents.pop(name, None)
            if removed:
                logger.info("mDNS gone: %s", name)
            return
        # Added or Updated → resolve async via _resolve task
        import asyncio

        asyncio.ensure_future(self._resolve(service_type, name))

    async def _resolve(self, service_type: str, name: str) -> None:
        if self._zc is None:
            return
        info = AsyncServiceInfo(service_type, name)
        await info.async_request(self._zc.zeroconf, timeout=2000)
        if not info or not info.addresses:
            return

        addresses = [socket.inet_ntoa(a) for a in info.addresses if len(a) == 4]
        properties = {
            (k.decode() if isinstance(k, bytes) else k): (v.decode() if isinstance(v, bytes) else v)
            for k, v in (info.properties or {}).items()
            if v is not None
        }

        agent = DiscoveredAgent(
            name=name,
            host=info.server or "",
            addresses=addresses,
            port=info.port or 0,
            properties=properties,
        )
        self._agents[name] = agent
        logger.info("mDNS found: %s @ %s:%s", name, addresses, info.port)

    def list_agents(self) -> list[dict]:
        return [asdict(a) for a in self._agents.values()]
