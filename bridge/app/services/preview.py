"""Dev Preview (localhost mobile) — détection de ports + proxy transparent.

Deux briques, toutes deux self-contained (stdlib pure → reste bundlable dans
l'AppImage/.deb sans dépendance système) :

- ``scan_listening_ports`` : liste les serveurs de dev qui écoutent sur le PC
  (Next/Vite/Laravel…), via ``/proc/net/tcp`` (Linux, cible des installeurs).
- ``ProxyManager`` : pour un port choisi, ouvre un listener LAN dédié qui
  **relaie les octets bruts** vers ``127.0.0.1:<port>``. Le relais brut traverse
  HTTP **et** WebSocket (Reverb, Socket.io, Vite HMR, Next Fast Refresh) sans
  rien parser — c'est ce qui garantit « même comportement que sur le PC ». Un
  listener dédié par projet (et non un préfixe de path) préserve la racine ``/``,
  donc les chemins absolus et les appels même-origine de l'app marchent tels quels.

Le HTTPS (contexte sécurisé obligatoire pour caméra/géoloc/PWA côté tél) se
branchera en passant un ``ssl.SSLContext`` à ``asyncio.start_server`` : le relais
ci-dessous est inchangé, seul le listener gagne TLS. Cf. CDC §Dev Preview.
"""

import asyncio
import json
import os
import ssl
import time
from dataclasses import dataclass
from pathlib import Path

import httpx

# `0A` = TCP_LISTEN dans /proc/net/tcp (cf. include/net/tcp_states.h).
_STATE_LISTEN = "0A"
_PROC_TCP = ("/proc/net/tcp", "/proc/net/tcp6")
_RELAY_CHUNK = 65536
_CONNECT_TIMEOUT_SECONDS = 2.0

# --- Filtrage du bruit : ne montrer que ce qui ressemble à un serveur de dev ---
# Ports < 1024 = système (FTP 21, DNS 53, HTTP 80, HTTPS 443, CUPS 631…) ; un dev
# ne les bind quasi jamais (root requis). Ports >= 32768 = plage éphémère Linux
# (clients/VM debug : ports VS Code, dart VM service…), pas des serveurs de dev.
_MIN_DEV_PORT = 1024
_MAX_DEV_PORT = 32768
# Services d'infra que le NAVIGATEUR ne charge jamais (DB, cache, adb, exporters…).
_INFRA_PORTS = frozenset({3306, 5432, 6379, 27017, 11211, 9100, 5037, 9229, 9200})
# Process clairement non-web (outillage), exclus même dans la plage dev.
_DENY_PROCESS = ("adb", "code", "containerd", "dockerd")


class ProxyError(Exception):
    """Levée quand un port à exposer n'a aucun service derrière lui."""


@dataclass
class ListeningPort:
    port: int
    process: str | None

    def as_dict(self) -> dict:
        return {"port": self.port, "process": self.process}


@dataclass
class ProxyInfo:
    target_port: int
    listen_port: int
    started_at: float

    def as_dict(self) -> dict:
        return {
            "target_port": self.target_port,
            "listen_port": self.listen_port,
            "started_at": self.started_at,
        }


# --------------------------------------------------------------- détection ports


def scan_listening_ports(exclude: frozenset[int] | set[int] = frozenset()) -> list[ListeningPort]:
    """Serveurs de dev en écoute sur le PC, **filtrés du bruit système/infra**.

    Lit ``/proc/net/tcp{,6}`` (Linux). Écarte les ports hors plage dev
    (< 1024 système, >= 32768 éphémères), les services d'infra (DB/cache/adb…)
    et les process non-web (VS Code, adb…) — sinon la liste serait noyée sous
    FTP/DNS/MySQL/Redis/ports d'éditeur. Sur un OS sans ``/proc``, retourne [].
    """
    inode_by_port: dict[int, str] = {}
    for path in _PROC_TCP:
        try:
            with open(path) as fh:
                next(fh, None)  # ligne d'en-tête
                for line in fh:
                    parts = line.split()
                    if len(parts) < 10 or parts[3] != _STATE_LISTEN:
                        continue
                    try:
                        port = int(parts[1].rsplit(":", 1)[-1], 16)
                    except ValueError:
                        continue
                    if port in exclude or port in inode_by_port:
                        continue
                    if port < _MIN_DEV_PORT or port >= _MAX_DEV_PORT or port in _INFRA_PORTS:
                        continue
                    inode_by_port[port] = parts[9]
        except OSError:
            continue

    if not inode_by_port:
        return []

    names = _process_names(set(inode_by_port.values()))
    result: list[ListeningPort] = []
    for port, inode in sorted(inode_by_port.items()):
        proc = names.get(inode)
        if proc and any(deny in proc.lower() for deny in _DENY_PROCESS):
            continue  # outillage (éditeur, adb…), pas un serveur web
        result.append(ListeningPort(port=port, process=proc))
    return result


def _process_names(inodes: set[str]) -> dict[str, str | None]:
    """Mappe inode de socket → nom du process (``/proc/<pid>/comm``), best-effort.

    Sert juste à afficher « node (3000) » plutôt qu'un port nu côté tél. Toute
    erreur (process disparu, droits) est ignorée → le port reste listé sans nom.
    """
    if not inodes:
        return {}
    wanted = {inode: f"socket:[{inode}]" for inode in inodes}
    targets = {link: inode for inode, link in wanted.items()}
    found: dict[str, str | None] = {}
    proc = Path("/proc")
    try:
        pid_dirs = [p for p in proc.iterdir() if p.name.isdigit()]
    except OSError:
        return {}

    for pid_dir in pid_dirs:
        try:
            fds = list((pid_dir / "fd").iterdir())
        except OSError:
            continue  # process terminé / pas les droits
        name: str | None = None
        for fd in fds:
            try:
                link = os.readlink(fd)
            except OSError:
                continue
            inode = targets.get(link)
            if inode is None:
                continue
            if name is None:
                name = _read_comm(pid_dir)
            found[inode] = name
        if len(found) == len(inodes):
            break
    return found


def _read_comm(pid_dir: Path) -> str | None:
    try:
        return (pid_dir / "comm").read_text().strip() or None
    except OSError:
        return None


# ------------------------------------------------------ filtre « serveur HTTP ? »

_HTTP_PROBE_TIMEOUT = 0.7
# TTL du cache : on ne re-sonde pas un port à chaque poll du dashboard (2.5 s),
# pour ne pas spammer les logs des serveurs de dev avec des GET / répétés.
_HTTP_CACHE_TTL = 12.0
_http_cache: dict[int, tuple[bool, float]] = {}


async def _is_http_server(client: httpx.AsyncClient, port: int) -> bool:
    """Vrai si ``127.0.0.1:port`` répond en HTTP (n'importe quel statut).

    Distingue un vrai serveur web (Next/Vite/php/Spring…) d'un process qui écoute
    sans parler HTTP (démon IDE/Gradle/java, base, etc.) → seuls les premiers sont
    « previewables » dans un navigateur. Résultat mis en cache (TTL).
    """
    now = time.monotonic()
    cached = _http_cache.get(port)
    if cached and now - cached[1] < _HTTP_CACHE_TTL:
        return cached[0]
    try:
        await client.get(f"http://127.0.0.1:{port}/", timeout=_HTTP_PROBE_TIMEOUT)
        alive = True  # une réponse HTTP (même 4xx/5xx) = c'est bien un serveur HTTP
    except (httpx.HTTPError, OSError):
        alive = False  # pas de réponse / protocole non-HTTP / timeout → on écarte
    _http_cache[port] = (alive, now)
    return alive


async def filter_http_ports(ports: list[ListeningPort]) -> list[ListeningPort]:
    """Ne garde que les ports qui répondent réellement en HTTP."""
    if not ports:
        return []
    async with httpx.AsyncClient() as client:
        results = await asyncio.gather(*(_is_http_server(client, p.port) for p in ports))
    return [port for port, ok in zip(ports, results, strict=True) if ok]


# ------------------------------------------------------------------- proxy LAN


class ProxyManager:
    """Gère les listeners de proxy actifs (un par projet exposé).

    ``connect_host`` reste 127.0.0.1 : on ne joint QUE des services locaux du PC
    (jamais une IP arbitraire fournie par le tél → pas de SSRF). ``host`` est
    l'interface d'écoute exposée au LAN (0.0.0.0 en prod).
    """

    def __init__(
        self,
        host: str = "0.0.0.0",
        connect_host: str = "127.0.0.1",
        ssl_context: ssl.SSLContext | None = None,
        state_file: Path | None = None,
    ) -> None:
        self._host = host
        self._connect_host = connect_host
        # Si fourni, TLS est terminé au listener (le tél parle HTTPS) ; le relais
        # vers le dev-server reste en clair, en local sur le PC.
        self._ssl_context = ssl_context
        self._servers: dict[int, tuple[asyncio.AbstractServer, ProxyInfo]] = {}
        # Mapping PERSISTANT target_port → listen_port : un projet garde la même
        # URL entre redémarrages (donc figeable dans un .env), tout en évitant les
        # conflits (port choisi libre la 1ʳᵉ fois, re-choisi si pris ensuite).
        self._state_file = state_file
        self._preferred: dict[int, int] = self._load_state()

    def _load_state(self) -> dict[int, int]:
        if not self._state_file or not self._state_file.exists():
            return {}
        try:
            data = json.loads(self._state_file.read_text())
            return {int(k): int(v) for k, v in data.items()}
        except (OSError, ValueError):
            return {}

    def _save_state(self) -> None:
        if not self._state_file:
            return
        try:
            self._state_file.parent.mkdir(parents=True, exist_ok=True)
            self._state_file.write_text(
                json.dumps({str(k): v for k, v in self._preferred.items()})
            )
        except OSError:
            pass

    @property
    def scheme(self) -> str:
        return "https" if self._ssl_context else "http"

    def listen_ports(self) -> set[int]:
        return {info.listen_port for _, info in self._servers.values()}

    def list(self) -> list[ProxyInfo]:
        return [info for _, info in self._servers.values()]

    async def expose(self, target_port: int) -> ProxyInfo:
        """Démarre (ou réutilise) le proxy vers ``127.0.0.1:target_port``.

        Idempotent : ré-exposer un port déjà actif renvoie le même listener.
        Lève ``ProxyError`` si rien n'écoute derrière le port demandé.
        """
        if target_port in self._servers:
            return self._servers[target_port][1]

        await self._assert_reachable(target_port)

        server = await self._start_listener(target_port)
        listen_port = server.sockets[0].getsockname()[1]
        if self._preferred.get(target_port) != listen_port:
            self._preferred[target_port] = listen_port
            self._save_state()
        info = ProxyInfo(target_port=target_port, listen_port=listen_port, started_at=time.time())
        self._servers[target_port] = (server, info)
        return info

    async def _start_listener(self, target_port: int) -> asyncio.AbstractServer:
        """Ouvre le listener, en réutilisant le port mémorisé si possible.

        Tente d'abord le port persistant (URL stable) ; s'il est déjà pris,
        retombe sur un port libre choisi par l'OS (pas de conflit). ``port=0``
        laisse l'OS choisir.
        """

        def handler(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
            return self._relay(target_port, reader, writer)

        preferred = self._preferred.get(target_port)
        if preferred:
            try:
                return await asyncio.start_server(
                    handler, host=self._host, port=preferred, ssl=self._ssl_context
                )
            except OSError:
                pass  # port mémorisé occupé → on en prend un libre
        return await asyncio.start_server(
            handler, host=self._host, port=0, ssl=self._ssl_context
        )

    async def unexpose(self, target_port: int) -> bool:
        entry = self._servers.pop(target_port, None)
        if entry is None:
            return False
        server, _ = entry
        server.close()
        await server.wait_closed()
        return True

    async def shutdown(self) -> None:
        for target_port in list(self._servers):
            await self.unexpose(target_port)

    async def _assert_reachable(self, target_port: int) -> None:
        try:
            _, writer = await asyncio.wait_for(
                asyncio.open_connection(self._connect_host, target_port),
                timeout=_CONNECT_TIMEOUT_SECONDS,
            )
        except (OSError, TimeoutError) as exc:
            raise ProxyError(f"Aucun service n'écoute sur le port {target_port}.") from exc
        writer.close()

    async def _relay(
        self,
        target_port: int,
        client_reader: asyncio.StreamReader,
        client_writer: asyncio.StreamWriter,
    ) -> None:
        try:
            server_reader, server_writer = await asyncio.open_connection(
                self._connect_host, target_port
            )
        except OSError:
            client_writer.close()
            return

        await asyncio.gather(
            _pump(client_reader, server_writer),
            _pump(server_reader, client_writer),
        )


async def _pump(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    """Copie un sens du flux jusqu'à EOF, puis ferme le côté écriture."""
    try:
        while True:
            data = await reader.read(_RELAY_CHUNK)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except OSError:
        pass  # reset/peer parti : on laisse le finally fermer proprement
    finally:
        try:
            writer.close()
        except OSError:
            pass
