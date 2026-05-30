# Linkup - Explication ligne par ligne des fichiers Python

Ce document explique **chaque fichier Python du bridge**.

Je me limite aux fichiers Python du projet lui-meme :

- `bridge/app/__init__.py`
- `bridge/app/config.py`
- `bridge/app/main.py`
- `bridge/app/routes/mdns.py`
- `bridge/app/services/mdns.py`
- `bridge/app/os/__init__.py`
- `bridge/app/routes/__init__.py`
- `bridge/app/services/__init__.py`
- `bridge/tests/__init__.py`
- `bridge/tests/test_health.py`
- `bridge/tests/test_mdns.py`

Je n'explique pas les fichiers Python de `.venv/` car ce sont ceux des bibliotheques installees, pas ceux que tu maintiens.

---

## 1. `bridge/app/__init__.py`

Fichier :

- [bridge/app/__init__.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/__init__.py:1)

Contenu :

```python
"""Linkup OS bridge — FastAPI service piloted by the Laravel agent."""

__version__ = "0.1.0"
```

### Ligne 1

```python
"""Linkup OS bridge — FastAPI service piloted by the Laravel agent."""
```

C'est une **docstring de module**.

Ca sert a dire :

- ce package Python correspond au bridge OS
- il est pilote par Laravel

### Ligne 3

```python
__version__ = "0.1.0"
```

Variable globale de version.

Elle est reutilisee ailleurs, notamment dans :

- `app.main`
- certaines reponses `/health`
- les infos mDNS

---

## 2. `bridge/app/config.py`

Fichier :

- [bridge/app/config.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/config.py:1)

Contenu :

```python
from pydantic_settings import BaseSettings, SettingsConfigDict
```

Ici on importe l'outil qui permet de lire la config depuis :

- le code par defaut
- un fichier `.env`
- les variables d'environnement

### Classe `Settings`

```python
class Settings(BaseSettings):
```

On cree un objet de configuration central.

Au lieu d'ecrire des constantes partout, on les regroupe ici.

### `model_config`

```python
model_config = SettingsConfigDict(env_file=".env", env_prefix="LINKUP_BRIDGE_")
```

Ca veut dire :

- lire aussi un fichier `.env`
- ne prendre que les variables qui commencent par `LINKUP_BRIDGE_`

Exemple :

- `LINKUP_BRIDGE_PORT=8765`

alimente :

- `port`

### `host`

```python
host: str = "127.0.0.1"
```

Adresse d'ecoute par defaut du bridge.

Ici le bridge est pense comme :

- un service local
- pas un service public expose

### `port`

```python
port: int = 8765
```

Port HTTP local du bridge.

Exemples de routes :

- `http://127.0.0.1:8765/health`
- `http://127.0.0.1:8765/mdns/info`

### `reverb_port`

```python
reverb_port: int = 8080
```

Port du service temps reel Reverb.

Le bridge ne fait pas tourner Reverb lui-meme.

Mais il a besoin de connaitre ce port pour :

- l'annoncer dans mDNS comme port principal Linkup

### `agent_token`

```python
agent_token: str = "dev-shared-token-change-me"
```

Token de confiance partage entre :

- Laravel
- le bridge

Il est utilise pour proteger certaines routes bridge.

### `transfers_dir` et `downloads_dir`

```python
transfers_dir: str = "~/Linkup/Inbox"
downloads_dir: str = "~/Linkup/Downloads"
```

Repertoires cibles pour de futures fonctions :

- transferts
- telechargements

Aujourd'hui ils sont surtout prets pour la suite.

### `log_level`

```python
log_level: str = "INFO"
```

Niveau de logs.

### `mdns_heartbeat_interval_seconds`

```python
mdns_heartbeat_interval_seconds: float = 5.0
```

Toutes les 5 secondes :

- le browser mDNS reverifie les agents connus

### `mdns_stale_after_seconds`

```python
mdns_stale_after_seconds: float = 15.0
```

Si un agent n'a pas repondu depuis plus de 15 secondes :

- il est considere stale
- il est supprime

### `mdns_healthcheck_timeout_seconds`

```python
mdns_healthcheck_timeout_seconds: float = 2.0
```

Quand le bridge appelle `/health` sur un autre agent :

- il n'attend pas indefiniment
- timeout au bout de 2 secondes

### Derniere ligne

```python
settings = Settings()
```

On instancie la config une seule fois.

Ensuite dans le projet on fait :

- `from app.config import settings`

---

## 3. `bridge/app/main.py`

Fichier :

- [bridge/app/main.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/main.py:1)

C'est le **point d'entree principal** de l'application FastAPI.

Il :

- configure l'app
- demarre mDNS
- expose les routes
- gere la securite bridge

### Bloc imports

```python
import platform
import time
from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI, Header, HTTPException, Request, status
from app import __version__
from app.config import settings
from app.routes import mdns as mdns_routes
from app.services.mdns import LinkupAnnouncer, LinkupBrowser
```

Role des imports :

- `platform` -> infos systeme
- `time` -> uptime + timestamp
- `asynccontextmanager` -> lifecycle startup/shutdown
- `fastapi...` -> framework HTTP
- `__version__` -> version du bridge
- `settings` -> configuration
- `mdns_routes` -> router mDNS
- `LinkupAnnouncer`, `LinkupBrowser` -> services mDNS

### Fonction `lifespan`

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
```

Cette fonction controle :

- ce qui se passe au demarrage
- ce qui se passe a l'arret

FastAPI l'utilise comme cycle de vie global.

### Creation de l'annonceur

```python
announcer = LinkupAnnouncer(
    port=settings.reverb_port, bridge_port=settings.port, version=__version__
)
```

Cette ligne est fondamentale.

Elle veut dire :

- le service mDNS Linkup annonce le port `8080` comme port principal
- mais expose aussi `bridge_port=8765`

Donc :

- port annonce = Reverb
- port bridge = FastAPI local

### Creation du browser

```python
browser = LinkupBrowser(
    heartbeat_interval_seconds=settings.mdns_heartbeat_interval_seconds,
    stale_after_seconds=settings.mdns_stale_after_seconds,
    healthcheck_timeout_seconds=settings.mdns_healthcheck_timeout_seconds,
)
```

On cree le scanner mDNS avec ses regles de presence.

Donc le browser sait deja :

- toutes les combien de secondes heartbeat
- quand supprimer un agent stale
- combien de temps attendre les reponses

### Demarrage effectif

```python
await announcer.start()
await browser.start()
```

Au demarrage du bridge :

- il devient visible sur le LAN
- il commence a scanner les autres agents

### Stockage dans `app.state`

```python
app.state.mdns_announcer = announcer
app.state.mdns_browser = browser
```

`app.state` = espace de stockage partage pour l'application FastAPI.

Ca permet a d'autres morceaux du code, notamment les routes, de recuperer :

- l'annonceur
- le browser

Sans recreer ces objets a chaque requete.

### `yield`

```python
yield
```

Cette ligne signifie :

- tout ce qui est avant = startup
- tout ce qui est apres = shutdown

### Shutdown

```python
await browser.stop()
await announcer.stop()
```

A l'arret :

- on stoppe l'ecoute mDNS
- on retire l'annonce mDNS

Ca permet un cleanup propre.

### Creation de l'app FastAPI

```python
app = FastAPI(
    title="Linkup Bridge",
    version=__version__,
    description=("Pont système pour Linkup : clipboard, fichiers, processus et média."),
    lifespan=lifespan,
)
```

On construit l'application HTTP.

### Ajout du router mDNS

```python
app.include_router(mdns_routes.router)
```

Ca branche toutes les routes definies dans `routes/mdns.py`.

### `_started_at`

```python
_started_at = time.monotonic()
```

On memorise un point de depart.

But :

- calculer l'uptime du bridge

### `require_agent_token`

```python
def require_agent_token(authorization: str | None = Header(default=None)) -> None:
```

Fonction de securite.

Elle lit le header :

- `Authorization`

et verifie qu'il est de la forme :

- `Bearer <token>`

#### Si le header est absent ou mal forme

```python
if not authorization or not authorization.startswith("Bearer "):
```

Alors :

- erreur `401`

#### Extraction du token

```python
token = authorization.removeprefix("Bearer ").strip()
```

On retire le mot `Bearer`.

#### Verification

```python
if token != settings.agent_token:
```

Si le token ne correspond pas a la config :

- `401`

### Route `/health`

```python
@app.get("/health")
def health(request: Request) -> dict:
```

Route publique.

Elle sert a deux choses :

- verifier que le bridge vit
- servir de heartbeat pour les autres agents Linkup

#### Recuperer l'annonceur

```python
announcer = getattr(request.app.state, "mdns_announcer", None)
```

On essaie de recuperer l'annonceur depuis l'etat global.

#### Reponse

Le JSON renvoie :

- `status`
- `service`
- `agent_id`
- `timestamp`
- `version`
- `uptime_seconds`
- `os`
- `os_release`
- `python`

Point important :

- `status` vaut `alive`
- c'est ce champ que le heartbeat mDNS verifie

### Route `/system/info`

```python
@app.get("/system/info", dependencies=[Depends(require_agent_token)])
def system_info() -> dict:
```

Route protegee.

`Depends(require_agent_token)` veut dire :

- avant d'executer `system_info`
- FastAPI execute la verification du token

Si le token est bon, on renvoie :

- `os`
- `os_release`
- `machine`
- `node`
- `python`

---

## 4. `bridge/app/routes/mdns.py`

Fichier :

- [bridge/app/routes/mdns.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/routes/mdns.py:1)

Ce fichier sert a exposer les routes mDNS.

### Imports

```python
from typing import Annotated
from fastapi import APIRouter, Depends, Request
from app.services.mdns import LinkupAnnouncer, LinkupBrowser
```

Role :

- `APIRouter` -> permet de grouper des routes
- `Depends` -> injection de dependances FastAPI
- `Request` -> acces a l'objet requete
- les classes mDNS -> types attendus

### Router

```python
router = APIRouter(
    prefix="/mdns",
    tags=["mdns"],
)
```

Toutes les routes de ce fichier auront le prefixe :

- `/mdns`

Donc :

- `/info`
- `/services`

deviennent :

- `/mdns/info`
- `/mdns/services`

### `_announcer`

```python
def _announcer(request: Request) -> LinkupAnnouncer:
```

Fonction helper.

Elle lit :

- `request.app.state.mdns_announcer`

Donc elle recupere l'annonceur cree au startup.

### `_browser`

```python
def _browser(request: Request) -> LinkupBrowser:
```

Meme idee pour le browser.

### `AnnouncerDep`

```python
AnnouncerDep = Annotated[LinkupAnnouncer, Depends(_announcer)]
```

Ca dit a FastAPI :

- si une route demande `AnnouncerDep`
- appelle `_announcer`
- injecte l'objet retourne

### `BrowserDep`

Meme logique pour le browser.

### Route `/mdns/info`

```python
@router.get("/info")
def mdns_info(announcer: AnnouncerDep) -> dict:
```

Cette route recoit automatiquement :

- l'objet `LinkupAnnouncer`

Grace a l'injection de dependance.

Ensuite :

```python
return announcer.info()
```

On delegue a la methode de la classe.

### Route `/mdns/services`

```python
@router.get("/services")
def mdns_services(browser: BrowserDep) -> dict:
```

Cette route recoit :

- l'objet `LinkupBrowser`

Puis :

```python
agents = browser.list_agents()
return {"count": len(agents), "agents": agents}
```

Donc :

- on demande la liste des agents vivants
- on renvoie le nombre
- on renvoie la liste

---

## 5. `bridge/app/services/mdns.py`

Fichier :

- [bridge/app/services/mdns.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/services/mdns.py:1)

C'est le fichier Python le plus important du bridge aujourd'hui.

Il contient :

- les helpers date/temps
- la structure d'un agent decouvert
- l'annonceur mDNS
- le browser mDNS
- le heartbeat
- la purge TTL

## 5.1 Docstring du module

La docstring explique l'intention :

- decouverte mDNS
- eviter les agents fantomes
- utiliser un heartbeat HTTP

## 5.2 Imports

### `asyncio`

Pour :

- lancer des taches asynchrones
- heartbeat loop
- create_task
- gather

### `contextlib`

Pour :

- faire un `suppress(...)`
- eviter certaines erreurs au cleanup

### `logging`

Pour les logs du module.

### `socket`

Pour :

- IP locale
- adresses IPv4
- hostname
- manipulation reseau bas niveau

### `uuid`

Pour generer un `agent_id` aleatoire si besoin.

### `dataclasses`

Pour la classe `DiscoveredAgent`.

### `datetime`

Pour :

- `last_seen`
- TTL
- comparaison temporelle

### `httpx`

Pour les appels HTTP du heartbeat :

- `GET /health`

### `zeroconf`

Pour mDNS / Bonjour.

## 5.3 `logger`

```python
logger = logging.getLogger(__name__)
```

Logger standard du module.

## 5.4 `SERVICE_TYPE`

```python
SERVICE_TYPE = "_linkup._tcp.local."
```

Constante centrale du service mDNS Linkup.

Tous les agents Linkup utilisent ce type.

## 5.5 `_utcnow()`

```python
def _utcnow() -> datetime:
```

Petit helper qui renvoie l'heure courante en UTC.

Pourquoi utile :

- eviter de reecrire `datetime.now(UTC)` partout
- garder des timestamps coherents

## 5.6 `_parse_iso_datetime(value)`

Cette fonction convertit une chaine ISO en objet `datetime`.

Cas geres :

- date invalide -> `None`
- date sans timezone -> on force UTC
- date avec timezone -> conversion vers UTC

Elle est utile au moment de la purge TTL.

## 5.7 Classe `DiscoveredAgent`

```python
@dataclass(slots=True)
class DiscoveredAgent:
```

Cette classe represente un agent trouve sur le reseau.

### Champs

- `name`
- `host`
- `addresses`
- `port`
- `properties`
- `last_seen`

### Pourquoi `dataclass`

Parce qu'on veut une structure simple de donnees.

### Pourquoi `slots=True`

Pour optimiser un peu la memoire et verrouiller les attributs attendus.

### `last_seen`

```python
last_seen: str = field(default_factory=lambda: _utcnow().isoformat())
```

Quand un agent est cree :

- il recoit automatiquement l'heure courante

### Propriete `fingerprint`

Lit dans `properties["fp"]`.

### Propriete `version`

Lit dans `properties["v"]`.

### Propriete `bridge_port`

Recupere `properties["bridge_port"]`.

Puis :

- si absent -> `None`
- si non entier -> `None`
- sinon -> `int(...)`

### Propriete `health_url`

Construit l'URL du heartbeat :

- prend la premiere IP de `addresses`
- prend `bridge_port`
- fabrique `http://<ip>:<bridge_port>/health`

Si on n'a pas assez d'infos :

- `None`

### Methode `touch`

Met a jour `last_seen`.

Elle est appelee quand :

- un agent est nouvellement resolu
- un heartbeat reussit

## 5.8 `_local_ip()`

Cette fonction essaie de trouver l'IP locale principale.

Strategie :

1. creer un socket UDP
2. simuler une connexion vers `8.8.8.8`
3. demander au socket quelle IP locale il utilise

Si ca echoue :

- retourne `127.0.0.1`

Le `finally` ferme le socket proprement.

## 5.9 `_hostname()`

Prend le hostname systeme puis force le suffixe :

- `.local.`

Exemple :

- `monpc` -> `monpc.local.`

## 5.10 Classe `LinkupAnnouncer`

Role :

- annoncer cette machine sur le LAN

### `__init__`

Parametres :

- `port`
- `bridge_port`
- `agent_id`
- `fingerprint`
- `version`
- `instance_name`

#### `self.port`

Port principal annonce par mDNS.

Dans l'usage actuel :

- c'est souvent `8080` = Reverb

#### `self.bridge_port`

Port HTTP du bridge.

Dans l'usage actuel :

- `8765`

#### `self.agent_id`

Si absent :

- genere `linkup-xxxxxxxx`

#### `self.fingerprint`

Par defaut :

- `pending`

#### `self.instance_name`

Si absent :

- construit `"{agent_id}._linkup._tcp.local."`

#### `_zc`

Instance Zeroconf async.

#### `_info`

Objet `ServiceInfo` annonce.

### Methode `start`

But :

- rendre la machine visible sur le LAN

Etapes :

1. si deja lance -> return
2. calculer l'IP locale
3. construire `ServiceInfo`
4. ouvrir `AsyncZeroconf`
5. enregistrer le service
6. logger

#### Le `ServiceInfo`

Contient :

- type `_linkup._tcp.local.`
- nom instance
- adresses
- port principal
- proprietes TXT :
  - `id`
  - `v`
  - `fp`
  - `host`
  - `bridge_port`
- `server=_hostname()`

### Methode `stop`

But :

- retirer proprement le service du reseau

Etapes :

1. si pas lance -> return
2. si `_info` existe -> unregister
3. fermer Zeroconf
4. nettoyer `_zc` et `_info`

### Methode `info`

Retourne un dictionnaire avec :

- `registered`
- `instance_name`
- `agent_id`
- `fingerprint`
- `version`
- `port`
- `bridge_port`
- `host`
- `ip`

Elle est utilisee par :

- la route `/mdns/info`

## 5.11 Classe `LinkupBrowser`

Role :

- detecter les autres agents Linkup
- maintenir leur etat vivant/mort

### `__init__`

Parametres :

- `heartbeat_interval_seconds`
- `stale_after_seconds`
- `healthcheck_timeout_seconds`

Attributs internes :

- `_zc` -> moteur Zeroconf
- `_browser` -> navigateur de services
- `_heartbeat_task` -> boucle async
- `_client` -> client HTTP async
- `_agents` -> dictionnaire des agents connus

### `start`

But :

- demarrer l'ecoute mDNS
- creer le client heartbeat
- lancer la boucle heartbeat

Etapes :

1. si deja demarre -> return
2. creer `AsyncZeroconf`
3. creer `AsyncServiceBrowser`
4. creer `httpx.AsyncClient`
5. lancer `_heartbeat_loop()` en tache de fond

### `stop`

But :

- tout arreter proprement

Etapes :

1. annuler la tache heartbeat si elle existe
2. annuler le browser mDNS
3. fermer le client HTTP
4. fermer Zeroconf
5. vider `_agents`

### `_on_change(...)`

Callback appele par Zeroconf quand un service change.

Cas 1 :

- `Removed`
- on retire l'agent

Cas 2 :

- autre changement
- on lance `_resolve(service_type, name)`

### `_resolve(...)`

But :

- obtenir tous les details d'un service trouve

Etapes :

1. verifier que Zeroconf existe
2. creer `AsyncServiceInfo`
3. faire la requete de resolution
4. verifier qu'il y a des adresses
5. convertir les adresses bytes -> IPv4 string
6. convertir les proprietes bytes -> str
7. creer `DiscoveredAgent`
8. faire `touch()`
9. stocker dans `_agents`

### `_heartbeat_loop()`

Boucle infinie async :

1. attendre `heartbeat_interval_seconds`
2. appeler `_refresh_agents()`

Cette boucle existe tant que le browser tourne.

### `_refresh_agents()`

But :

- verifier tous les agents connus
- puis nettoyer ceux qui ont expire

Si `_agents` n'est pas vide :

- `asyncio.gather(...)` lance `_probe_agent(name)` pour chacun

Puis :

- `_purge_expired_agents()`

### `_probe_agent(name)`

But :

- verifier si un agent repond encore sur `/health`

Etapes :

1. recuperer l'agent
2. verifier qu'on a un client HTTP
3. calculer `health_url`
4. appeler `GET /health`
5. si erreur -> log debug, ne rien faire
6. si JSON et `status == "alive"` -> `agent.touch()`

Tres important :

- si le heartbeat rate une fois, l'agent n'est pas supprime tout de suite
- il sera supprime seulement si `last_seen` devient trop vieux

### `_purge_expired_agents()`

But :

- supprimer les agents trop vieux

Etapes :

1. calculer `stale_before = now - TTL`
2. parcourir tous les agents
3. parser `last_seen`
4. si invalide ou trop vieux -> marquer pour suppression
5. supprimer effectivement

### `list_agents()`

But :

- retourner seulement les agents consideres vivants

Avant de renvoyer la liste :

- appelle encore `_purge_expired_agents()`

Puis :

- convertit les dataclasses en dictionnaires avec `asdict`

---

## 6. `bridge/app/os/__init__.py`

Fichier :

- [bridge/app/os/__init__.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/os/__init__.py:1)

Etat actuel :

- fichier vide

### Pourquoi il existe

Pour marquer `app/os/` comme package Python et reserver cet espace pour de futurs modules systeme :

- clipboard
- media
- terminal
- processus

---

## 7. `bridge/app/routes/__init__.py`

Fichier :

- [bridge/app/routes/__init__.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/routes/__init__.py:1)

Etat actuel :

- fichier vide

### Pourquoi il existe

Pour marquer `app/routes/` comme package Python.

---

## 8. `bridge/app/services/__init__.py`

Fichier :

- [bridge/app/services/__init__.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/services/__init__.py:1)

Etat actuel :

- fichier vide

### Pourquoi il existe

Pour marquer `app/services/` comme package Python.

---

## 9. `bridge/tests/__init__.py`

Fichier :

- [bridge/tests/__init__.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/tests/__init__.py:1)

Etat actuel :

- fichier vide

### Pourquoi il existe

Pour marquer `tests/` comme package Python.

---

## 10. `bridge/tests/test_health.py`

Fichier :

- [bridge/tests/test_health.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/tests/test_health.py:1)

Ce fichier teste les fonctions simples de `app.main`.

### Imports

```python
from types import SimpleNamespace
import pytest
from fastapi import HTTPException
from app.main import health, require_agent_token, system_info
```

Role :

- `SimpleNamespace` -> fabriquer un faux objet simple pour simuler `request.app.state`
- `pytest` -> framework de test
- `HTTPException` -> verifier les erreurs FastAPI
- fonctions importées -> tests directs

### `test_health_returns_alive`

On construit un faux `request` avec :

- `request.app.state.mdns_announcer.agent_id = "linkup-test-1234"`

Puis :

- on appelle directement `health(request)`

Ce test verifie :

- `status == alive`
- `service == linkup-bridge`
- `agent_id` attendu
- presence de `timestamp`, `version`, `os`

### `test_system_info_requires_token`

Appelle :

- `require_agent_token(None)`

Attendu :

- exception HTTP 401

### `test_system_info_rejects_bad_token`

Appelle :

- `require_agent_token("Bearer wrong")`

Attendu :

- 401

### `test_system_info_accepts_dev_token`

Appelle :

- `require_agent_token("Bearer dev-shared-token-change-me")`

Puis :

- `system_info()`

Attendu :

- le body contient au moins `os`

---

## 11. `bridge/tests/test_mdns.py`

Fichier :

- [bridge/tests/test_mdns.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/tests/test_mdns.py:1)

Ce fichier teste la logique mDNS sans dependre d'un vrai reseau LAN.

### Docstring

```python
"""Unit tests for Linkup mDNS presence and cleanup."""
```

Le but est clair :

- tester la presence
- tester le cleanup

### Imports

On importe :

- `datetime`, `timedelta`
- `pytest`
- `mdns_module`
- les classes / constantes de `app.services.mdns`

Pourquoi `mdns_module` directement ?

Parce que certains tests vont faire du monkeypatch sur :

- `_local_ip`
- `AsyncZeroconf`
- `AsyncServiceBrowser`
- `httpx.AsyncClient`

### `test_discovered_agent_helpers`

Ce test cree un `DiscoveredAgent` manuellement.

Il verifie :

- `fingerprint`
- `version`
- `bridge_port`
- `health_url`

Donc il valide les proprietes helper de la dataclass.

### `test_announcer_info_before_start`

Ici on remplace `_local_ip` par une fonction qui renvoie toujours :

- `192.168.1.42`

But :

- rendre le test stable

Puis on cree un `LinkupAnnouncer` et on appelle `info()`.

On verifie :

- `registered` est `False`
- fingerprint correct
- port correct
- bridge_port correct
- `agent_id` commence par `linkup-`
- `host` finit par `.local.`

### `test_browser_starts_empty`

Test async.

Il fabrique de faux objets :

- `DummyAsyncZeroconf`
- `DummyAsyncServiceBrowser`
- `DummyAsyncClient`

Puis monkeypatch :

- Zeroconf
- browser service
- client HTTP

Pourquoi ?

Pour ne pas dependre du vrai reseau ou d'un vrai socket.

Ensuite :

- cree un `LinkupBrowser`
- `await browser.start()`
- verifie que `list_agents() == []`
- puis `await browser.stop()`

### `test_probe_agent_updates_last_seen`

Ici on simule :

- un client HTTP qui renvoie un faux `/health` avec `{"status": "alive"}`

On cree un agent avec un `last_seen` ancien de 30 secondes.

Puis on appelle :

- `await browser._probe_agent("agent-1")`

Attendu :

- `last_seen` devient recent

Donc ce test prouve que le heartbeat rafraichit bien la presence.

### `test_list_agents_purges_stale_entries`

On cree deux agents :

- `fresh` vu il y a 5 secondes
- `stale` vu il y a 20 secondes

Avec un TTL de 15 secondes.

Quand on appelle :

- `browser.list_agents()`

Attendu :

- seul `fresh` reste

Donc ce test prouve la purge TTL.

### `test_service_type_constant`

Simple test de regression :

- `SERVICE_TYPE` doit rester `_linkup._tcp.local.`

---

## 12. Comment lire ce code intelligemment

Si tu veux apprendre plus vite, lis les fichiers dans cet ordre :

1. `bridge/app/config.py`
2. `bridge/app/__init__.py`
3. `bridge/app/main.py`
4. `bridge/app/routes/mdns.py`
5. `bridge/app/services/mdns.py`
6. `bridge/tests/test_health.py`
7. `bridge/tests/test_mdns.py`

Pourquoi cet ordre ?

- d'abord la config
- ensuite le point d'entree
- ensuite les routes
- ensuite la logique lourde
- ensuite les tests qui confirment le comportement attendu

---

## 13. Resume final du code Python actuel

Le bridge Python actuel fait principalement 4 choses :

1. expose une API FastAPI locale
2. annonce l'agent Linkup sur le LAN via mDNS
3. detecte les autres agents Linkup via mDNS
4. maintient une liste propre des agents vivants avec heartbeat + TTL

Donc si tu comprends :

- `main.py`
- `routes/mdns.py`
- `services/mdns.py`

alors tu comprends deja presque tout le code Python metier actuel de Linkup.

