"""
Module de decouverte mDNS pour les agents Linkup.

Objectif :
Permettre a plusieurs machines sur le meme reseau local de se detecter
automatiquement et d'eviter les agents fantomes grace a un modele de presence.

Fonctionnement :
- LinkupAnnouncer : annonce cette machine sur le reseau
- LinkupBrowser : detecte les autres machines Linkup sur le reseau
- Heartbeat HTTP : verifie regulierement que les agents repondent encore
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
import socket
import uuid
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime, timedelta

import httpx
from zeroconf import IPVersion, ServiceInfo, ServiceStateChange, Zeroconf
from zeroconf.asyncio import AsyncServiceBrowser, AsyncServiceInfo, AsyncZeroconf

logger = logging.getLogger(__name__)

# Type de service mDNS utilise pour identifier les agents Linkup sur le reseau
SERVICE_TYPE = "_linkup._tcp.local."


def _utcnow() -> datetime:
    """
    Retourne la date courante en UTC.
    """
    return datetime.now(UTC)


def _parse_iso_datetime(value: str) -> datetime | None:
    """
    Parse une date ISO 8601 en UTC si possible.
    """
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None

    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)

    return parsed.astimezone(UTC)


# ============================================================
# Representation d'un agent detecte sur le reseau
# ============================================================


@dataclass(slots=True)
class DiscoveredAgent:
    """
    Represente un agent Linkup detecte sur le reseau local.
    """

    name: str
    host: str
    addresses: list[str]
    port: int
    properties: dict[str, str] = field(default_factory=dict)
    last_seen: str = field(default_factory=lambda: _utcnow().isoformat())

    @property
    def fingerprint(self) -> str | None:
        """
        Identifiant unique de l'agent, si disponible.
        """
        return self.properties.get("fp")

    @property
    def version(self) -> str | None:
        """
        Version du logiciel de l'agent.
        """
        return self.properties.get("v")

    @property
    def bridge_port(self) -> int | None:
        """
        Port HTTP du bridge, utilise pour le heartbeat applicatif.
        """
        raw_value = self.properties.get("bridge_port")

        if raw_value is None:
            return None

        try:
            return int(raw_value)
        except ValueError:
            return None

    @property
    def health_url(self) -> str | None:
        """
        URL du endpoint /health de l'agent.
        """
        host = next(iter(self.addresses), None)
        port = self.bridge_port

        if host is None or port is None:
            return None

        return f"http://{host}:{port}/health"

    def touch(self, seen_at: datetime | None = None) -> None:
        """
        Met a jour le timestamp de derniere presence.
        """
        self.last_seen = (seen_at or _utcnow()).isoformat()


# ============================================================
# Fonctions utilitaires reseau
# ============================================================


def _local_ip() -> str:
    """
    Retourne l'adresse IP locale principale de la machine.

    Astuce :
    On simule une connexion vers Internet (8.8.8.8)
    pour recuperer l'interface reseau utilisee.
    """
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        with contextlib.suppress(UnboundLocalError):
            sock.close()


def _hostname() -> str:
    """
    Retourne le nom de la machine formate pour mDNS (.local).
    """
    host = socket.gethostname().split(".")[0]
    return f"{host}.local."


# ============================================================
# ANNOUNCER : publication de l'agent sur le reseau
# ============================================================


class LinkupAnnouncer:
    """
    Rend la machine visible sur le reseau local via mDNS.

    Les autres machines peuvent alors la decouvrir automatiquement.
    """

    def __init__(
        self,
        port: int = 8080,
        bridge_port: int | None = None,
        agent_id: str | None = None,
        fingerprint: str | None = None,
        version: str = "0.1.0",
        instance_name: str | None = None,
    ) -> None:
        self.port = port
        self.bridge_port = bridge_port or port
        self.agent_id = agent_id or f"linkup-{uuid.uuid4().hex[:8]}"
        self.fingerprint = fingerprint or "pending"
        self.version = version
        self.instance_name = instance_name or f"{self.agent_id}.{SERVICE_TYPE}"
        self._zc: AsyncZeroconf | None = None
        self._info: ServiceInfo | None = None

    async def start(self) -> None:
        """
        Demarre la publication mDNS.
        """
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
                "bridge_port": str(self.bridge_port),
            },
            server=_hostname(),
        )

        self._zc = AsyncZeroconf(ip_version=IPVersion.V4Only)
        await self._zc.async_register_service(self._info)

        logger.info(
            "Annonce mDNS demarree : %s sur %s:%s (bridge:%s)",
            self.instance_name,
            ip,
            self.port,
            self.bridge_port,
        )

    async def stop(self) -> None:
        """
        Arrete la publication mDNS.
        """
        if self._zc is None:
            return

        try:
            if self._info is not None:
                await self._zc.async_unregister_service(self._info)
        finally:
            await self._zc.async_close()
            self._zc = None
            self._info = None
            logger.info("Annonce mDNS arretee")

    def info(self) -> dict:
        """
        Retourne l'etat actuel de l'agent local.
        """
        return {
            "registered": self._zc is not None,
            "instance_name": self.instance_name,
            "agent_id": self.agent_id,
            "fingerprint": self.fingerprint,
            "version": self.version,
            "port": self.port,
            "bridge_port": self.bridge_port,
            "host": _hostname(),
            "ip": _local_ip(),
        }


# ============================================================
# BROWSER : decouverte des autres agents sur le reseau
# ============================================================


class LinkupBrowser:
    """
    Ecoute le reseau local pour detecter les autres agents Linkup.
    """

    def __init__(
        self,
        heartbeat_interval_seconds: float = 5.0,
        stale_after_seconds: float = 15.0,
        healthcheck_timeout_seconds: float = 2.0,
    ) -> None:
        self._zc: AsyncZeroconf | None = None
        self._browser: AsyncServiceBrowser | None = None
        self._heartbeat_interval_seconds = heartbeat_interval_seconds
        self._stale_after_seconds = stale_after_seconds
        self._healthcheck_timeout_seconds = healthcheck_timeout_seconds
        self._heartbeat_task: asyncio.Task[None] | None = None
        self._client: httpx.AsyncClient | None = None
        self._agents: dict[str, DiscoveredAgent] = {}

    async def start(self) -> None:
        """
        Demarre l'ecoute mDNS.
        """
        if self._zc is not None:
            return

        self._zc = AsyncZeroconf(ip_version=IPVersion.V4Only)
        self._browser = AsyncServiceBrowser(
            self._zc.zeroconf,
            [SERVICE_TYPE],
            handlers=[self._on_change],
        )
        self._client = httpx.AsyncClient(timeout=self._healthcheck_timeout_seconds)
        self._heartbeat_task = asyncio.create_task(self._heartbeat_loop())

        logger.info("Browser mDNS demarre pour %s", SERVICE_TYPE)

    async def stop(self) -> None:
        """
        Arrete l'ecoute mDNS et vide la liste des agents.
        """
        if self._heartbeat_task is not None:
            self._heartbeat_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._heartbeat_task
            self._heartbeat_task = None

        if self._browser is not None:
            await self._browser.async_cancel()
            self._browser = None

        if self._client is not None:
            await self._client.aclose()
            self._client = None

        if self._zc is not None:
            await self._zc.async_close()
            self._zc = None

        self._agents.clear()
        logger.info("Browser mDNS arrete")

    def _on_change(
        self,
        *,
        zeroconf: Zeroconf,
        service_type: str,
        name: str,
        state_change: ServiceStateChange,
    ) -> None:
        """
        Callback appele quand un service apparait ou disparait sur le reseau.
        """
        if state_change is ServiceStateChange.Removed:
            self._agents.pop(name, None)
            logger.info("Agent supprime : %s", name)
            return

        asyncio.create_task(self._resolve(service_type, name))

    async def _resolve(self, service_type: str, name: str) -> None:
        """
        Recupere les details complets d'un agent detecte.
        """
        if self._zc is None:
            return

        info = AsyncServiceInfo(service_type, name)
        await info.async_request(self._zc.zeroconf, timeout=2000)

        if not info or not info.addresses:
            return

        addresses = [socket.inet_ntoa(address) for address in info.addresses if len(address) == 4]

        properties = {
            (key.decode() if isinstance(key, bytes) else key): (
                value.decode() if isinstance(value, bytes) else value
            )
            for key, value in (info.properties or {}).items()
            if value is not None
        }

        agent = DiscoveredAgent(
            name=name,
            host=info.server or "",
            addresses=addresses,
            port=info.port or 0,
            properties=properties,
        )
        agent.touch()
        self._agents[name] = agent

        logger.info("Agent detecte : %s", name)

    async def _heartbeat_loop(self) -> None:
        """
        Verifie regulierement que les agents connus repondent encore.
        """
        while True:
            await asyncio.sleep(self._heartbeat_interval_seconds)
            await self._refresh_agents()

    async def _refresh_agents(self) -> None:
        """
        Lance un heartbeat HTTP sur les agents connus puis purge les expires.
        """
        if self._agents:
            await asyncio.gather(
                *(self._probe_agent(name) for name in list(self._agents)),
                return_exceptions=True,
            )

        self._purge_expired_agents()

    async def _probe_agent(self, name: str) -> None:
        """
        Met a jour last_seen si l'agent repond sur /health.
        """
        agent = self._agents.get(name)

        if agent is None or self._client is None:
            return

        health_url = agent.health_url
        if health_url is None:
            return

        try:
            response = await self._client.get(health_url)
            response.raise_for_status()
            payload = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            logger.debug("Heartbeat echoue pour %s : %s", name, exc)
            return

        if isinstance(payload, dict) and payload.get("status") == "alive":
            agent.touch()

    def _purge_expired_agents(self) -> None:
        """
        Supprime les agents silencieux depuis plus longtemps que le TTL.
        """
        stale_before = _utcnow() - timedelta(seconds=self._stale_after_seconds)
        expired_names: list[str] = []

        for name, agent in self._agents.items():
            last_seen = _parse_iso_datetime(agent.last_seen)
            if last_seen is None or last_seen < stale_before:
                expired_names.append(name)

        for name in expired_names:
            self._agents.pop(name, None)
            logger.info("Agent expire supprime : %s", name)

    def list_agents(self) -> list[dict]:
        """
        Retourne les agents encore consideres vivants.
        """
        self._purge_expired_agents()
        return [asdict(agent) for agent in self._agents.values()]
