# Linkup - Tutoriel complet du projet

Ce document a un seul but :

**te permettre de comprendre le projet entier sans supposer que tu sais deja comment Laravel, Python, Reverb, mDNS, les ports, les process et les routes fonctionnent.**

Je vais donc expliquer :

- ce que fait le projet
- quels sont les dossiers
- quels sont les programmes qui tournent
- quels sont les ports
- ce qu'est un agent
- comment Laravel et Python parlent entre eux
- comment mDNS fonctionne dans TON projet
- quelles routes existent vraiment
- ce qui est deja code
- ce qui est encore seulement prevu dans les docs

Le document parle du **code reel actuel** du repo, puis rappelle aussi la **vision cible** quand c'est utile.

---

## 1. Idee generale du projet

Linkup est un projet qui veut relier :

- un **PC** Windows/Linux
- un **telephone Android**
- et parfois un **navigateur web**

Le but final est :

- scanner un QR code
- connecter le telephone au PC
- utiliser plein de modules cross-device

Exemples de modules prevus dans le CDC :

- transfert de fichiers
- presse-papier partage
- lien rapide
- galerie distante
- telechargement video
- transcription
- conversion media
- camera du telephone vers le PC
- micro du telephone vers le PC
- terminal distant
- notifs miroir
- controle media

Mais attention :

**aujourd'hui, tout cela n'est pas encore completement implemente.**

Le repo contient surtout le socle initial :

- un **agent Laravel**
- un **bridge Python FastAPI**
- un debut de **temps reel avec Reverb**
- un debut de **decouverte reseau mDNS**
- des squelettes pour **mobile** et **dashboard**

---

## 2. Le monorepo

Le projet est un **monorepo**.

Ca veut dire :

- un seul depot Git
- plusieurs sous-projets dedans
- chaque dossier a son role

Structure principale :

```text
linkup/
├── agent/       -> application Laravel 12
├── bridge/      -> application Python FastAPI
├── mobile/      -> application Flutter Android
├── dashboard/   -> application Next.js
├── docs/        -> CDC, plan, ADR, notes
├── infra/       -> scripts et infra future
└── .github/     -> CI GitHub Actions
```

### Idee simple

- `agent/` = le cerveau
- `bridge/` = les mains qui touchent le systeme
- `mobile/` = l'application telephone
- `dashboard/` = l'interface web
- `docs/` = la strategie et l'explication

---

## 3. La phrase la plus importante du projet

Si tu dois retenir une seule phrase, retiens celle-ci :

**Laravel orchestre, Python execute les actions systeme, Reverb transporte les petits messages temps reel, mDNS sert a la decouverte sur le LAN, Flutter pilotera le telephone, Next.js pilotera le dashboard web.**

Autrement dit :

- **Laravel decide**
- **Python fait**
- **Reverb relie**
- **mDNS annonce et detecte**
- **Flutter utilisera le telephone**
- **Next.js affichera l'interface web**

---

## 4. Les mots de base, tres simplement

Avant d'aller dans le code, il faut clarifier le vocabulaire.

### 4.1 Agent

Dans ce projet, le mot **agent** veut dire :

> le logiciel qui tourne sur un PC et represente ce PC dans l'ecosysteme Linkup.

Dans la vision produit, "l'agent PC" est le tout :

- Laravel
- Reverb
- bridge Python

Dans le code actuel, on voit surtout deux sous-parties :

- **agent Laravel**
- **bridge Python**

### 4.2 Bridge

Le **bridge** est le pont Python local.

Il sert a faire ce que PHP fait mal ou ne fait pas facilement :

- parler au systeme d'exploitation
- manipuler du reseau bas niveau
- gerer clipboard, media, PTY, mDNS, etc.

### 4.3 Process

Un **process** = un programme qui tourne.

Exemples chez toi :

- `php artisan serve`
- `php artisan reverb:start`
- `uvicorn app.main:app`
- `pnpm dev`
- `flutter run`

Chaque commande lance en general **un process**.

### 4.4 Port

Un **port** = un numero qui identifie un service reseau sur une machine.

Exemples :

- `127.0.0.1:8765`
- `localhost:3000`
- `0.0.0.0:8080`

Tu peux voir ca comme :

- l'adresse IP = l'immeuble
- le port = l'appartement

### 4.5 Route

Une **route** HTTP = une URL qu'une application expose.

Exemples :

- `GET /health`
- `GET /mdns/info`
- `POST /ping`

### 4.6 Methode HTTP

Les methodes les plus importantes ici sont :

- `GET` = lire / demander une information
- `POST` = envoyer une action ou une donnee

Exemple :

- `GET /health` = "donne-moi ton etat"
- `POST /ping` = "declenche un evenement ping"

### 4.7 LAN

Le **LAN** = le reseau local.

Exemples :

- le meme Wi-Fi
- la meme box
- le meme routeur

### 4.8 mDNS

**mDNS** = mecanisme de decouverte locale sans serveur central.

Au lieu de dire :

- "le PC est a l'IP 192.168.1.42"

on peut dire :

- "je cherche les services `_linkup._tcp.local.`"

et les machines qui annoncent ce service repondent.

### 4.9 Reverb

**Reverb** = serveur WebSocket de Laravel pour le temps reel.

Il sert a diffuser des evenements rapides :

- ping
- notifications
- clipboard
- signaux de connexion

### 4.10 Heartbeat

Le **heartbeat** = une verification periodique du style :

> "tu es encore vivant ?"

Dans ce projet, il est fait avec des appels HTTP vers `/health`.

### 4.11 TTL

**TTL** = duree de vie maximale d'une information.

Exemple :

- si un agent n'a pas ete vu depuis plus de 15 secondes
- on le considere mort
- on le retire de la liste

---

## 5. Les 4 grands blocs du projet

## 5.1 `agent/` - Laravel

C'est l'application PHP.

Role :

- exposer l'API principale du PC
- gerer la logique metier
- plus tard gerer pairing, securite, tokens, base de donnees
- diffuser les evenements temps reel avec Reverb
- parler localement au bridge Python

Pense a Laravel comme :

> le coordinateur central.

## 5.2 `bridge/` - FastAPI Python

C'est l'application Python locale.

Role :

- faire des actions systeme
- annoncer le service Linkup sur le LAN via mDNS
- scanner les autres agents Linkup
- maintenir un modele de presence avec heartbeat

Pense a Python comme :

> l'operateur technique qui a acces au systeme et au reseau bas niveau.

## 5.3 `mobile/` - Flutter

Pour l'instant, c'est encore surtout un squelette Flutter.

Role cible :

- scanner le QR code
- parler au PC
- offrir l'interface mobile

Etat actuel :

- encore au stade template / scaffold

## 5.4 `dashboard/` - Next.js

Pour l'instant, c'est aussi surtout un squelette.

Role cible :

- page d'appairage
- approbation
- visualisation des appareils
- outils web

Etat actuel :

- encore au stade template Next.js

---

## 6. Les ports du projet

C'est souvent la partie la plus confuse, donc on va la rendre tres concrete.

### 6.1 Tableau simple

| Port | Service | Dossier | Role |
|---|---|---|---|
| `8000` | Laravel HTTP local de dev | `agent/` | API HTTP du PC quand tu lances `php artisan serve` |
| `8080` | Reverb | `agent/` | WebSocket temps reel |
| `8765` | Bridge FastAPI | `bridge/` | API locale Python |
| `3000` | Dashboard Next.js | `dashboard/` | Interface web de dev |
| `5353/UDP` | mDNS standard | systeme reseau | multicast de decouverte LAN |

### 6.2 Pourquoi il y a plusieurs ports

Parce qu'il y a plusieurs programmes.

Chaque bloc a son role :

- Laravel = API metier
- Reverb = WebSocket
- Python = bridge systeme
- Dashboard = frontend web

### 6.3 Le point subtil tres important

Dans le code actuel :

- le **bridge** ecoute sur `127.0.0.1:8765`
- mais le service mDNS annonce surtout le **port Reverb** `8080`
- et publie aussi `bridge_port=8765` dans les proprietes TXT

Ca veut dire :

- si un autre agent te detecte sur le LAN, il voit que le service Linkup principal est sur `8080`
- mais il peut aussi recuperer que le bridge HTTP local correspondant est `8765`

Concretement, dans `bridge/app/main.py`, l'annonceur est cree comme ca :

- `port=settings.reverb_port`
- `bridge_port=settings.port`

Donc :

- `port` mDNS = `8080`
- `bridge_port` TXT = `8765`

---

## 7. Ce qui tourne vraiment quand tu developpes

Si tu lances tout en local, tu peux avoir plusieurs process en meme temps.

### 7.1 Process Laravel

Commande :

```bash
php artisan serve
```

Ca lance :

- l'application Laravel HTTP
- souvent sur `http://127.0.0.1:8000`

### 7.2 Process Reverb

Commande :

```bash
php artisan reverb:start
```

Ca lance :

- le serveur WebSocket Reverb
- souvent sur le port `8080`

### 7.3 Process bridge Python

Commande :

```bash
uvicorn app.main:app --host 127.0.0.1 --port 8765
```

Ca lance :

- l'API FastAPI locale
- le service mDNS announce
- le service mDNS browser
- la boucle de heartbeat mDNS

### 7.4 Process dashboard

Commande :

```bash
pnpm dev
```

Ca lance :

- Next.js de dev
- souvent sur `http://localhost:3000`

### 7.5 Process mobile

Commande :

```bash
flutter run
```

Ca lance :

- l'application Flutter sur un appareil ou emulateur Android

---

## 8. Vue d'ensemble reseau tres simple

### 8.1 Communications locales sur le meme PC

Laravel et Python parlent entre eux en HTTP local :

```text
Laravel  <----HTTP local---->  FastAPI bridge
           127.0.0.1:8765
```

Important :

- ce trafic est local a la machine
- il ne sort pas sur Internet
- il ne devrait pas etre expose publiquement

### 8.2 Communications temps reel

Reverb sert de colonne vertebrale temps reel :

```text
Flutter / Dashboard / plus tard d'autres clients
        <---- WebSocket ---->
               Reverb
```

### 8.3 Communications de decouverte LAN

mDNS sert a dire :

- "je suis un agent Linkup"
- "qui d'autre est un agent Linkup sur ce reseau ?"

Ca passe par :

- multicast UDP
- port `5353`
- type de service `_linkup._tcp.local.`

---

## 9. Architecture actuelle, en une image mentale

```text
PC
|
|-- Laravel
|   |-- API metier
|   |-- parle au bridge Python
|   |-- emet des events via Reverb
|
|-- Reverb
|   |-- transporte les events temps reel
|
|-- Bridge Python
|   |-- expose /health
|   |-- annonce le PC via mDNS
|   |-- detecte les autres agents via mDNS
|   |-- supprime les agents fantomes avec TTL
|
|-- Dashboard
|   |-- UI web
|
`-- plus tard Flutter
    |-- UI mobile
    |-- scan QR
    `-- connexion temps reel
```

---

## 10. Laravel en detail

## 10.1 Fichier d'entree principal

Fichier :

- [agent/bootstrap/app.php](/home/mahamane/Bureau/Mahamane/linkUp/agent/bootstrap/app.php:1)

Ce fichier configure Laravel.

Point important :

- les routes API sont branchees via `routes/api.php`
- la route de health framework Laravel est sur `/up`

Donc il y a **deux notions de health** :

- `/up` = health framework Laravel
- `/api/health` = health specifique Linkup

## 10.2 Les routes API Laravel

Fichier :

- [agent/routes/api.php](/home/mahamane/Bureau/Mahamane/linkUp/agent/routes/api.php:1)

Comme ce fichier est monte comme route API Laravel, ses endpoints sont prefixes par `/api`.

Donc :

- `Route::get('/health', ...)` devient `GET /api/health`
- `Route::get('/agent/info', ...)` devient `GET /api/agent/info`
- `Route::get('/mdns/services', ...)` devient `GET /api/mdns/services`
- `Route::post('/ping', ...)` devient `POST /api/ping`

### Routes actuelles

#### `GET /api/health`

Role :

- dire que l'agent Laravel est vivant

Retourne :

- `status`
- `service`
- `version`
- `time`

Ce endpoint ne parle pas au bridge. Il parle de Laravel lui-meme.

#### `GET /api/agent/info`

Role :

- demander au **bridge Python** les infos mDNS locales
- renvoyer cela sous une forme Laravel

Donc ici Laravel agit comme **facade**.

Il ne calcule pas lui-meme ces infos.

Il appelle le service `MdnsAnnouncer`.

#### `GET /api/mdns/services`

Role :

- demander au bridge Python la liste des agents vus sur le LAN

Encore une fois :

- Laravel ne scanne pas lui-meme le LAN
- il demande au bridge Python

#### `POST /api/ping`

Role :

- declencher un `PingEvent`
- ce `PingEvent` est broadcast via Reverb

Concretement :

- le client envoie un message
- Laravel cree l'evenement
- l'evenement part sur le channel `linkup-system`

#### `GET /api/user`

Role :

- endpoint Laravel standard protege par Sanctum

Dans l'etat actuel, ce n'est pas encore le coeur de Linkup.

## 10.3 Le service Laravel `MdnsAnnouncer`

Fichier :

- [agent/app/Services/MdnsAnnouncer.php](/home/mahamane/Bureau/Mahamane/linkUp/agent/app/Services/MdnsAnnouncer.php:1)

Ce service est tres important pour comprendre l'architecture.

Il ne fait pas du mDNS lui-meme.

Il fait ceci :

1. il construit une requete HTTP locale
2. il appelle le bridge Python
3. il renvoie la reponse a Laravel

Methodes actuelles :

- `bridgeHealth()` -> appelle `GET /health` du bridge
- `localInfo()` -> appelle `GET /mdns/info`
- `discoveredServices()` -> appelle `GET /mdns/services`

### Pourquoi c'est utile

Parce que le plan d'execution parle d'un `MdnsAnnouncer` cote Laravel.

L'implementation bas niveau, elle, reste en Python.

Donc Laravel devient la **facade metier**, et Python reste le **moteur technique**.

C'est une maniere propre de respecter le plan sans faire du PHP bas niveau pour mDNS.

## 10.4 Comment Laravel sait joindre Python

Via la config :

- [agent/config/services.php](/home/mahamane/Bureau/Mahamane/linkUp/agent/config/services.php:1)
- [agent/.env.example](/home/mahamane/Bureau/Mahamane/linkUp/agent/.env.example:1)

Variables importantes :

- `LINKUP_BRIDGE_BASE_URL=http://127.0.0.1:8765`
- `LINKUP_BRIDGE_AGENT_TOKEN=...`
- `LINKUP_BRIDGE_TIMEOUT_SECONDS=2`

Donc Laravel sait que :

- le bridge Python est sur `127.0.0.1`
- au port `8765`

## 10.5 Reverb cote Laravel

Fichiers :

- [agent/config/reverb.php](/home/mahamane/Bureau/Mahamane/linkUp/agent/config/reverb.php:1)
- [agent/config/broadcasting.php](/home/mahamane/Bureau/Mahamane/linkUp/agent/config/broadcasting.php:1)

Ce que ca veut dire simplement :

- Laravel peut diffuser des events temps reel
- le driver de broadcast utilise est `reverb`
- Reverb tourne sur le port `8080`

Variables importantes :

- `REVERB_PORT=8080`
- `REVERB_SERVER_PORT=8080`

## 10.6 Le `PingEvent`

Fichier :

- [agent/app/Events/PingEvent.php](/home/mahamane/Bureau/Mahamane/linkUp/agent/app/Events/PingEvent.php:1)

C'est un exemple de diffusion temps reel.

Ce qu'il fait :

- implemente `ShouldBroadcastNow`
- diffuse immediatement
- sur le channel public `linkup-system`
- avec le nom d'evenement `ping`

Payload :

- `message`
- `emitted_at`

Le but actuel de cet event :

- valider que Reverb et le broadcast Laravel fonctionnent

---

## 11. Python bridge en detail

## 11.1 Point d'entree

Fichier :

- [bridge/app/main.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/main.py:1)

Ce fichier :

- cree l'application FastAPI
- configure le cycle de vie
- expose les routes
- demarre les services mDNS au boot

## 11.2 Le `lifespan`

Dans FastAPI, le `lifespan` sert a executer du code :

- au demarrage
- a l'arret

Ici, il fait 4 choses importantes :

1. cree un `LinkupAnnouncer`
2. cree un `LinkupBrowser`
3. lance les deux au demarrage
4. les arrete proprement a la fin

C'est capital pour comprendre le projet.

Ca veut dire que **demarrer le bridge Python ne lance pas seulement une API HTTP**.

Ca lance aussi :

- une presence mDNS
- une ecoute mDNS
- un modele de presence reseau

## 11.3 Les routes FastAPI

### `GET /health`

Role :

- dire que le bridge Python est vivant

Retourne notamment :

- `status=alive`
- `service=linkup-bridge`
- `agent_id`
- `timestamp`
- `version`
- `uptime_seconds`
- `os`
- `os_release`
- `python`

Cette route sert aussi pour le **heartbeat entre agents Linkup sur le LAN**.

### `GET /system/info`

Role :

- retourner des infos machine plus detaillees

Protection :

- token Bearer obligatoire

Fonction de validation :

- `require_agent_token(...)`

Donc :

- Laravel peut appeler cette route
- un client non autorise ne devrait pas

### `GET /mdns/info`

Role :

- retourner ce que CET agent annonce sur le LAN

Exemples d'infos :

- `agent_id`
- `instance_name`
- `fingerprint`
- `port`
- `bridge_port`
- `ip`

### `GET /mdns/services`

Role :

- retourner les agents Linkup encore consideres vivants sur le LAN

Retour :

- `count`
- `agents`

Chaque agent contient des infos comme :

- nom
- host
- addresses
- port
- properties
- `last_seen`

## 11.4 La configuration du bridge

Fichier :

- [bridge/app/config.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/config.py:1)

Variables cle :

- `host = 127.0.0.1`
- `port = 8765`
- `reverb_port = 8080`
- `agent_token = ...`
- `mdns_heartbeat_interval_seconds = 5.0`
- `mdns_stale_after_seconds = 15.0`
- `mdns_healthcheck_timeout_seconds = 2.0`

Traduction concrete :

- le bridge HTTP local ecoute sur `8765`
- l'annonce mDNS parle du port temps reel `8080`
- le heartbeat mDNS tourne toutes les 5 secondes
- un agent silencieux est jete apres 15 secondes

---

## 12. mDNS dans TON projet

C'est probablement la partie la plus difficile, donc on va la faire tres lentement.

## 12.1 L'idee

Tu veux que chaque PC Linkup puisse dire :

> "Je suis un agent Linkup sur ce reseau"

Et tu veux aussi qu'il puisse demander :

> "Y a-t-il d'autres agents Linkup sur le meme reseau ?"

## 12.2 Le type de service

Dans le code :

- `SERVICE_TYPE = "_linkup._tcp.local."`

Ca veut dire :

- nom du service : `linkup`
- protocole : `tcp`
- domaine local mDNS : `.local`

## 12.3 `LinkupAnnouncer`

Classe :

- [bridge/app/services/mdns.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/services/mdns.py:160)

Role :

- publier cet agent sur le LAN

Quand tu demarres le bridge :

- il cree un `agent_id` si besoin
- il trouve une IP locale
- il construit une `ServiceInfo`
- il enregistre le service dans Zeroconf

Infos annoncees :

- `id`
- `v`
- `fp`
- `host`
- `bridge_port`

Et le port principal annonce est :

- `self.port`
- donc en pratique `settings.reverb_port`
- donc souvent `8080`

## 12.4 `LinkupBrowser`

Classe :

- [bridge/app/services/mdns.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/services/mdns.py:258)

Role :

- ecouter le reseau local
- detecter les autres annonces `_linkup._tcp.local.`
- garder une liste locale des agents connus

## 12.5 Que se passe-t-il quand un service apparait

Quand mDNS signale un changement :

1. `_on_change(...)` est appele
2. si le service a ete supprime -> on retire l'agent
3. sinon -> on lance `_resolve(...)`

Le `_resolve(...)` :

- demande les details du service
- recupere les adresses IP
- decode les proprietes TXT
- cree un `DiscoveredAgent`
- met a jour `last_seen`
- stocke l'agent en memoire

## 12.6 Pourquoi `DiscoveredAgent` existe

Cette structure sert a representer un agent decouvert.

Elle contient :

- `name`
- `host`
- `addresses`
- `port`
- `properties`
- `last_seen`

Elle expose aussi des aides utiles :

- `fingerprint`
- `version`
- `bridge_port`
- `health_url`

`health_url` est calculee a partir de :

- l'IP decouverte
- `bridge_port`

Ca permet de faire ensuite un heartbeat HTTP.

---

## 13. Le vrai modele de presence actuel

Avant, le repo avait mDNS, mais pas vraiment un bon modele de presence.

Maintenant, l'idee est :

1. mDNS detecte qu'un agent existe
2. on stocke `last_seen`
3. on interroge regulierement `GET /health`
4. si l'agent repond -> on refresh `last_seen`
5. s'il ne repond plus assez longtemps -> on le supprime

## 13.1 Pourquoi mDNS seul ne suffit pas

mDNS n'offre pas a lui seul un "heartbeat metier" garanti.

Probleme :

- si un process meurt brutalement
- le retrait reseau n'arrive pas toujours de facon assez propre
- tu peux garder des agents fantomes

## 13.2 Heartbeat applicatif

Le bridge Python utilise maintenant un heartbeat interne.

Boucle :

- toutes les `5` secondes
- il parcourt les agents connus
- il appelle leur `/health`

Si la reponse contient :

- `status == "alive"`

alors :

- `last_seen` est mis a jour

## 13.3 TTL

Le TTL est :

- `15` secondes

Si :

- `maintenant - last_seen > 15 s`

alors :

- l'agent est retire de la liste

## 13.4 Cleanup propre

Quand le process bridge s'arrete proprement :

- le browser est stoppe
- l'annonce mDNS est `unregister`

Ca permet une disparition propre sur le reseau.

## 13.5 Ce que ca corrige

Ca evite :

- les agents fantomes
- les listes mDNS stale
- la confusion entre agents reellement vivants et morts

---

## 14. Comment Laravel et Python interagissent exactement

Il faut bien separer deux types d'interaction.

## 14.1 Interaction 1 - Laravel appelle Python en HTTP local

C'est l'interaction **interne au PC**.

Exemple :

1. un endpoint Laravel est appele
2. Laravel utilise `MdnsAnnouncer`
3. `MdnsAnnouncer` fait un `GET http://127.0.0.1:8765/...`
4. Python repond
5. Laravel reformate la reponse si besoin

Exemple reel :

### `GET /api/agent/info`

Flux :

1. client -> Laravel `/api/agent/info`
2. Laravel -> `MdnsAnnouncer::localInfo()`
3. `MdnsAnnouncer` -> `GET http://127.0.0.1:8765/mdns/info`
4. bridge Python -> reponse JSON
5. Laravel -> reponse finale JSON au client

Donc :

- le client ne parle pas directement au bridge
- Laravel joue le role de facade

## 14.2 Interaction 2 - Python annonce le PC sur le reseau LAN

Ici, Laravel n'est pas celui qui fait le travail bas niveau.

Le bridge Python :

- s'annonce via mDNS
- ecoute les autres agents
- tient a jour la presence

Laravel, lui :

- peut consulter ces infos
- les exposer proprement au reste de l'application

## 14.3 Pourquoi ce partage est sain

Parce que :

- PHP/Laravel est parfait pour l'orchestration
- Python est meilleur pour Zeroconf et les actions systeme

Donc :

- Laravel ne fait pas semblant de faire du bas niveau
- Python ne devient pas le cerveau metier

---

## 15. Routes et methodes - recap complet

## 15.1 Cote Laravel

Base courante en dev :

- `http://127.0.0.1:8000`

Routes actuelles :

| Methode | URL finale | Role |
|---|---|---|
| `GET` | `/up` | health framework Laravel |
| `GET` | `/api/health` | health de l'agent Laravel |
| `GET` | `/api/agent/info` | facade Laravel vers `/mdns/info` du bridge |
| `GET` | `/api/mdns/services` | facade Laravel vers `/mdns/services` du bridge |
| `POST` | `/api/ping` | diffuse un `PingEvent` |
| `GET` | `/api/user` | endpoint standard Sanctum protege |

## 15.2 Cote bridge Python

Base locale :

- `http://127.0.0.1:8765`

Routes actuelles :

| Methode | URL | Role |
|---|---|---|
| `GET` | `/health` | health du bridge + heartbeat applicatif |
| `GET` | `/system/info` | infos machine protegees par token Bearer |
| `GET` | `/mdns/info` | infos de cette machine annoncees en mDNS |
| `GET` | `/mdns/services` | agents decouverts et encore vivants |

## 15.3 Cote Reverb

Ce n'est pas une route HTTP classique pour le developpeur final, mais un serveur WebSocket sur :

- port `8080`

Actuellement, le code montre surtout un channel public :

- `linkup-system`

Et un event :

- `ping`

---

## 16. Comment comprendre les tests

Les tests te montrent souvent le vrai comportement attendu.

## 16.1 Tests Laravel

Fichiers :

- [agent/tests/Feature/PingEventTest.php](/home/mahamane/Bureau/Mahamane/linkUp/agent/tests/Feature/PingEventTest.php:1)
- [agent/tests/Feature/MdnsAnnouncerTest.php](/home/mahamane/Bureau/Mahamane/linkUp/agent/tests/Feature/MdnsAnnouncerTest.php:1)

Ils verifient notamment :

- que `/api/health` repond
- que `/api/ping` broadcast bien un event
- que `MdnsAnnouncer` proxifie bien le bridge

## 16.2 Tests bridge Python

Fichiers :

- [bridge/tests/test_health.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/tests/test_health.py:1)
- [bridge/tests/test_mdns.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/tests/test_mdns.py:1)

Ils verifient notamment :

- la structure de `/health`
- la logique de `DiscoveredAgent`
- la purge TTL
- la mise a jour de `last_seen`

---

## 17. Ce qui est reellement fini aujourd'hui

Voici une separation tres honnete entre le present et le futur.

## 17.1 Ce qui existe vraiment dans le code

- monorepo structure
- Laravel 12 installe
- Reverb installe
- `PingEvent`
- bridge FastAPI
- `/health` bridge
- `/system/info`
- annonce mDNS
- decouverte mDNS
- heartbeat presence + TTL + purge fantomes
- facade Laravel `MdnsAnnouncer`
- routes Laravel proxy vers le bridge
- tests de base Laravel et Python

## 17.2 Ce qui est encore surtout dans les docs / le plan

- vrai pairing QR complet
- Noise IK complet
- vrai client Flutter Linkup
- vrai dashboard Linkup
- la majorite des 16 modules fonctionnels
- device registry complet
- flux WebRTC reels
- securite complete de production

## 17.3 Important pour ne pas te tromper

Le CDC decrit la **destination**.

Le code actuel montre surtout le **socle du voyage**.

---

## 18. Mobile et dashboard - etat reel actuel

## 18.1 Mobile

Fichier principal :

- [mobile/lib/main.dart](/home/mahamane/Bureau/Mahamane/linkUp/mobile/lib/main.dart:1)

Etat actuel :

- encore le compteur Flutter de demo

Donc si tu te demandes :

- "ou est l'ecran de scan QR ?"
- "ou est la liste des agents ?"

La reponse est :

- pas encore implemente dans le code mobile actuel

## 18.2 Dashboard

Fichier principal :

- [dashboard/src/app/page.tsx](/home/mahamane/Bureau/Mahamane/linkUp/dashboard/src/app/page.tsx:1)

Etat actuel :

- encore la page de demo Next.js

Donc pareil :

- les vues metier Linkup ne sont pas encore construites

---

## 19. Sequence complete de demarrage du projet actuel

Imaginons que tu lances le projet en local.

## 19.1 Tu lances Laravel

Commande :

```bash
cd agent
php artisan serve
```

Resultat :

- Laravel sert les routes HTTP sur `8000`

## 19.2 Tu lances Reverb

Commande :

```bash
php artisan reverb:start
```

Resultat :

- le serveur WebSocket tourne sur `8080`

## 19.3 Tu lances le bridge Python

Commande :

```bash
cd bridge
uvicorn app.main:app --host 127.0.0.1 --port 8765
```

Resultat :

- FastAPI ecoute sur `8765`
- un agent mDNS est annonce sur le LAN
- le browser mDNS scanne les autres agents
- le heartbeat periodique demarre

## 19.4 Tu appelles Laravel

Exemple :

```bash
curl http://127.0.0.1:8000/api/agent/info
```

Flux :

1. Laravel recoit la requete
2. Laravel appelle le bridge Python
3. Python renvoie les infos mDNS locales
4. Laravel renvoie la reponse

## 19.5 Tu appelles le bridge directement

Exemple :

```bash
curl http://127.0.0.1:8765/mdns/info
```

La, tu bypasses Laravel et tu parles directement au bridge.

En architecture applicative, ce n'est pas l'usage ideal pour le client final.

Mais en debug, c'est tres utile.

---

## 20. Exemple concret pour comprendre les differences

Imaginons cette machine :

- IP LAN : `192.168.1.42`
- Laravel : `127.0.0.1:8000`
- Reverb : `0.0.0.0:8080`
- bridge : `127.0.0.1:8765`

### Question 1

"Quel service un autre PC va voir sur le LAN ?"

Reponse :

- l'annonce mDNS `_linkup._tcp.local.`
- port principal annonce : `8080`
- metadata TXT : contient aussi `bridge_port=8765`

### Question 2

"Quel service Laravel appelle localement ?"

Reponse :

- `http://127.0.0.1:8765`

### Question 3

"Quel service un navigateur de dev ouvre pour le dashboard ?"

Reponse :

- `http://localhost:3000`

### Question 4

"Quel endpoint prouve que le bridge est vivant ?"

Reponse :

- `GET http://127.0.0.1:8765/health`

### Question 5

"Quel endpoint prouve que l'agent Laravel est vivant ?"

Reponse :

- `GET http://127.0.0.1:8000/api/health`

---

## 21. Pourquoi il y a a la fois Laravel et Python

C'est une des meilleures questions a se poser.

Tu aurais pu essayer :

- tout en PHP
- tout en Python
- tout en Node

Le projet choisit un hybride.

### Pourquoi Laravel

Parce qu'il est bon pour :

- architecture applicative
- routes
- securite
- base de donnees
- jobs
- diffusion d'evenements
- structure de projet

### Pourquoi Python

Parce qu'il est bon pour :

- systeme
- multimedia
- scripts
- bibliotheques mDNS / Zeroconf
- automation machine

### La philosophie

**Ne pas utiliser un outil pour faire ce qu'un autre outil fait mieux.**

Donc :

- Laravel n'essaie pas de devenir un outil systeme
- Python n'essaie pas de devenir le coeur metier complet

---

## 22. Les fichiers les plus importants a connaitre

Si tu veux reviser le projet vite, lis ceux-ci dans cet ordre :

1. [README.md](/home/mahamane/Bureau/Mahamane/linkUp/README.md:1)
2. [docs/Linkup-CDC-v2_0.md](/home/mahamane/Bureau/Mahamane/linkUp/docs/Linkup-CDC-v2_0.md:1)
3. [docs/Linkup-Plan-Execution.md](/home/mahamane/Bureau/Mahamane/linkUp/docs/Linkup-Plan-Execution.md:1)
4. [docs/stack-roles.md](/home/mahamane/Bureau/Mahamane/linkUp/docs/stack-roles.md:1)
5. [agent/routes/api.php](/home/mahamane/Bureau/Mahamane/linkUp/agent/routes/api.php:1)
6. [agent/app/Services/MdnsAnnouncer.php](/home/mahamane/Bureau/Mahamane/linkUp/agent/app/Services/MdnsAnnouncer.php:1)
7. [agent/app/Events/PingEvent.php](/home/mahamane/Bureau/Mahamane/linkUp/agent/app/Events/PingEvent.php:1)
8. [bridge/app/main.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/main.py:1)
9. [bridge/app/services/mdns.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/services/mdns.py:1)
10. [bridge/app/routes/mdns.py](/home/mahamane/Bureau/Mahamane/linkUp/bridge/app/routes/mdns.py:1)

---

## 23. Comment penser le projet sans te noyer

Si tu veux garder une carte mentale simple, pense en 3 couches.

### Couche 1 - Ce que l'utilisateur voit

- telephone
- dashboard
- plus tard QR, modules, boutons

### Couche 2 - Le cerveau metier

- Laravel
- routes
- securite
- Reverb
- base

### Couche 3 - Le moteur technique local

- bridge Python
- mDNS
- heartbeat
- systeme d'exploitation

Et entre les couches :

- Flutter / dashboard parlent surtout a Laravel/Reverb
- Laravel parle au bridge
- bridge parle au reseau local et au systeme

---

## 24. Les erreurs de comprehension les plus courantes

### Erreur 1

"Le bridge Python remplace Laravel"

Non.

Le bridge est un **sous-service local** du PC.

### Erreur 2

"Le port mDNS est le port HTTP du bridge"

Non.

Le port mDNS annonce actuellement surtout **Reverb 8080**.
Le bridge HTTP, lui, est en `8765` et il est aussi publie dans les proprietes.

### Erreur 3

"Le dashboard et le mobile sont deja complets"

Non.

Ils sont encore largement en scaffold.

### Erreur 4

"mDNS suffit a savoir si un agent est vivant"

Non.

C'est pour cela qu'on a ajoute :

- heartbeat
- `last_seen`
- TTL
- purge

### Erreur 5

"Laravel parle au reseau LAN pour scanner mDNS"

Pas directement dans le code actuel.

C'est Python qui fait ce boulot, Laravel agit comme facade.

---

## 25. Resume ultra simple en 10 phrases

1. Linkup veut connecter un PC et un telephone Android.
2. Le PC a deux briques principales : Laravel et Python.
3. Laravel est le cerveau et l'API metier.
4. Python est le bridge systeme local.
5. Reverb sert au temps reel sur le port `8080`.
6. Le bridge Python sert l'API locale sur `8765`.
7. mDNS sert a annoncer et detecter les agents sur le LAN.
8. Laravel appelle Python localement avec HTTP.
9. Le mobile et le dashboard ne sont pas encore vraiment construits.
10. Le projet actuel est surtout un socle technique propre pour la suite.

---

## 26. Si tu veux apprendre progressivement, ordre conseille

### Etape 1

Comprendre juste ceci :

- Laravel = cerveau
- Python = bridge local
- Reverb = temps reel
- mDNS = decouverte LAN

### Etape 2

Comprendre les ports :

- `8000` Laravel
- `8080` Reverb
- `8765` bridge
- `3000` dashboard
- `5353/UDP` mDNS

### Etape 3

Comprendre les 4 routes les plus importantes aujourd'hui :

- `/api/health`
- `/api/agent/info`
- `/health`
- `/mdns/services`

### Etape 4

Comprendre les 2 flux les plus importants :

- Laravel -> bridge Python
- bridge Python -> LAN via mDNS

### Etape 5

Comprendre le futur :

- Flutter se connectera ensuite au couple Laravel + Reverb
- le dashboard fera pareil

---

## 27. Conclusion

Le projet peut sembler enorme parce qu'il melange :

- backend
- bridge systeme
- temps reel
- reseau local
- mobile
- dashboard
- securite

Mais dans le fond, il repose sur une idee tres simple :

**un chef d'orchestre Laravel, un technicien Python, un fil temps reel Reverb, et un mecanisme mDNS pour que les machines se trouvent sur le reseau local.**

Si tu comprends bien ces 4 briques, tu comprends deja le coeur de Linkup.

---

## 28. Suite conseillee

Apres avoir lu ce document, la suite logique pour apprendre est :

1. lancer Laravel, Reverb et le bridge en local
2. appeler les routes a la main avec `curl`
3. observer les reponses JSON
4. lire `bridge/app/services/mdns.py`
5. lire `agent/routes/api.php`
6. seulement apres, attaquer Flutter et le dashboard

Si tu veux, le prochain pas que je peux faire pour toi est :

- soit un **schema visuel encore plus simple**
- soit un **guide pratique "comment lancer et tester tout en local"**
- soit un **cours ligne par ligne sur `bridge/app/services/mdns.py`**
