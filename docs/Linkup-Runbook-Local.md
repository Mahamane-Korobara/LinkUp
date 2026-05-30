# Linkup - Guide pratique pour lancer et tester tout le projet en local

Ce document est un **mode d'emploi concret**.

Le but :

- lancer les services localement
- comprendre ce qui doit etre ouvert
- tester les endpoints existants
- verifier que Laravel, Reverb et le bridge Python fonctionnent ensemble

Important :

- **mobile** et **dashboard** sont encore surtout des scaffolds
- donc ce guide se concentre surtout sur ce qui est deja testable aujourd'hui :
  - Laravel
  - Reverb
  - bridge Python
  - mDNS

---

## 1. Ce qu'on va lancer

En local, tu peux avoir jusqu'a 4 terminaux utiles :

### Terminal 1

Laravel :

```bash
cd agent
php artisan serve
```

### Terminal 2

Reverb :

```bash
cd agent
php artisan reverb:start
```

### Terminal 3

Bridge Python :

```bash
cd bridge
source .venv/bin/activate
uvicorn app.main:app --host 127.0.0.1 --port 8765
```

### Terminal 4

Dashboard de dev :

```bash
cd dashboard
pnpm dev
```

---

## 2. Ports a retenir

| Port | Service |
|---|---|
| `8000` | Laravel HTTP de dev |
| `8080` | Reverb WebSocket |
| `8765` | bridge Python FastAPI |
| `3000` | dashboard Next.js |
| `5353/UDP` | mDNS multicast LAN |

---

## 3. Prerequis

### PHP / Laravel

Il te faut :

- PHP
- Composer
- SQLite

### Python bridge

Il te faut :

- Python 3.11+
- un venv local

### Dashboard

Il te faut :

- Node
- pnpm

### Mobile

Il te faut :

- Flutter
- Android SDK

Mais le mobile n'est pas encore pret fonctionnellement.

---

## 4. Installation initiale

## 4.1 Agent Laravel

```bash
cd /home/mahamane/Bureau/Mahamane/linkUp/agent
composer install
cp .env.example .env
php artisan key:generate
php artisan migrate
```

### Ce que ca fait

- installe les dependances PHP
- cree le `.env`
- genere la cle Laravel
- cree la base SQLite / tables

## 4.2 Bridge Python

```bash
cd /home/mahamane/Bureau/Mahamane/linkUp/bridge
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env
```

### Ce que ca fait

- cree l'environnement Python
- installe FastAPI, zeroconf, httpx, pytest, etc.
- cree le `.env`

## 4.3 Dashboard

```bash
cd /home/mahamane/Bureau/Mahamane/linkUp/dashboard
pnpm install
```

## 4.4 Mobile

```bash
cd /home/mahamane/Bureau/Mahamane/linkUp/mobile
flutter pub get
```

---

## 5. Configuration minimale a verifier

## 5.1 Agent `.env`

Fichier :

- [agent/.env.example](/home/mahamane/Bureau/Mahamane/linkUp/agent/.env.example:1)

Points importants :

```env
BROADCAST_CONNECTION=reverb
REVERB_PORT=8080
REVERB_SERVER_PORT=8080
LINKUP_BRIDGE_BASE_URL=http://127.0.0.1:8765
LINKUP_BRIDGE_AGENT_TOKEN=change-me-to-a-random-32-bytes-base64
```

En pratique, dans `agent/.env`, assure-toi que :

- Laravel pointe bien vers le bridge local
- le token bridge cote Laravel correspond au token bridge cote Python

## 5.2 Bridge `.env`

Fichier :

- [bridge/.env.example](/home/mahamane/Bureau/Mahamane/linkUp/bridge/.env.example:1)

Points importants :

```env
LINKUP_BRIDGE_HOST=127.0.0.1
LINKUP_BRIDGE_PORT=8765
LINKUP_BRIDGE_REVERB_PORT=8080
LINKUP_BRIDGE_AGENT_TOKEN=change-me-to-a-random-32-bytes-base64
LINKUP_BRIDGE_MDNS_HEARTBEAT_INTERVAL_SECONDS=5
LINKUP_BRIDGE_MDNS_STALE_AFTER_SECONDS=15
```

Le token doit correspondre a celui configure dans Laravel.

---

## 6. Lancer les services

## 6.1 Lancer Laravel

```bash
cd /home/mahamane/Bureau/Mahamane/linkUp/agent
php artisan serve
```

Tu dois voir quelque chose comme :

```text
INFO  Server running on [http://127.0.0.1:8000]
```

## 6.2 Lancer Reverb

Dans un autre terminal :

```bash
cd /home/mahamane/Bureau/Mahamane/linkUp/agent
php artisan reverb:start
```

But :

- activer le WebSocket temps reel

## 6.3 Lancer le bridge Python

Dans un autre terminal :

```bash
cd /home/mahamane/Bureau/Mahamane/linkUp/bridge
source .venv/bin/activate
uvicorn app.main:app --host 127.0.0.1 --port 8765
```

Ce que ca lance en vrai :

- API FastAPI
- annonce mDNS
- browser mDNS
- heartbeat de presence

## 6.4 Lancer le dashboard

Dans un autre terminal :

```bash
cd /home/mahamane/Bureau/Mahamane/linkUp/dashboard
pnpm dev
```

Etat actuel :

- le dashboard n'est pas encore l'UI metier Linkup
- mais tu peux verifier que l'app Next.js demarre

---

## 7. Premier niveau de verification

## 7.1 Verifier Laravel

```bash
curl http://127.0.0.1:8000/api/health
```

Tu dois recevoir un JSON du style :

```json
{
  "status": "ok",
  "service": "linkup-agent",
  "version": "0.1.0",
  "time": "..."
}
```

## 7.2 Verifier le bridge Python

```bash
curl http://127.0.0.1:8765/health
```

Tu dois recevoir un JSON du style :

```json
{
  "status": "alive",
  "service": "linkup-bridge",
  "agent_id": "linkup-xxxx",
  "timestamp": "...",
  "version": "0.1.0",
  "uptime_seconds": 12.3,
  "os": "Linux",
  "os_release": "...",
  "python": "3.12.x"
}
```

## 7.3 Verifier que Laravel parle bien au bridge

```bash
curl http://127.0.0.1:8000/api/agent/info
```

Si tout va bien, Laravel doit te renvoyer les infos du bridge mDNS local.

Exemple attendu :

```json
{
  "name": "linkup-xxxx._linkup._tcp.local.",
  "fingerprint": "pending",
  "agent_id": "linkup-xxxx",
  "version": "0.1.0",
  "reverb_port": 8080,
  "bridge_port": 8765,
  "source": "bridge"
}
```

Si ca casse ici, le probleme est souvent :

- bridge pas lance
- mauvais token
- mauvais `LINKUP_BRIDGE_BASE_URL`

---

## 8. Tester les routes du bridge

## 8.1 `/mdns/info`

```bash
curl http://127.0.0.1:8765/mdns/info
```

But :

- voir ce que cet agent annonce sur le LAN

Tu dois y voir notamment :

- `instance_name`
- `agent_id`
- `fingerprint`
- `port`
- `bridge_port`
- `ip`

## 8.2 `/mdns/services`

```bash
curl http://127.0.0.1:8765/mdns/services
```

But :

- voir la liste des agents Linkup decouverts sur le LAN

Sur une seule machine, selon le comportement reseau local, tu peux :

- te voir toi-meme
- ou ne rien voir

Les deux ne veulent pas forcement dire qu'il y a un bug.

---

## 9. Tester les routes Laravel qui proxifient le bridge

## 9.1 `/api/agent/info`

```bash
curl http://127.0.0.1:8000/api/agent/info
```

But :

- verifier que Laravel utilise bien `MdnsAnnouncer`

## 9.2 `/api/mdns/services`

```bash
curl http://127.0.0.1:8000/api/mdns/services
```

But :

- verifier que Laravel peut lire la liste mDNS du bridge

---

## 10. Tester Reverb simplement

Le test deja present dans le code est surtout cote backend.

Tu peux au moins verifier le endpoint de declenchement :

```bash
curl -X POST http://127.0.0.1:8000/api/ping \
  -H "Content-Type: application/json" \
  -d '{"message":"hello-local"}'
```

Tu dois recevoir quelque chose comme :

```json
{
  "broadcasted": true,
  "channel": "linkup-system",
  "event": "ping",
  "message": "hello-local"
}
```

Ce test confirme :

- Laravel recoit la requete
- `PingEvent` est cree
- le chemin de broadcast est pret

---

## 11. Tester le token du bridge

La route protegee actuelle est :

- `GET /system/info`

### Sans token

```bash
curl http://127.0.0.1:8765/system/info
```

Attendu :

- `401`

### Avec token

```bash
curl http://127.0.0.1:8765/system/info \
  -H "Authorization: Bearer change-me-to-a-random-32-bytes-base64"
```

Remplace le token par la vraie valeur de ton `.env`.

Attendu :

- JSON avec `os`, `os_release`, `machine`, `node`, `python`

---

## 12. Tester mDNS en local de facon plus visible

## 12.1 Option Linux avec `avahi-browse`

Si tu es sur Linux :

```bash
avahi-browse -r _linkup._tcp
```

Tu devrais voir apparaitre l'annonce Linkup.

## 12.2 Option multi-instance sur la meme machine

Tu peux simuler deux agents.

### Terminal A

```bash
cd /home/mahamane/Bureau/Mahamane/linkUp/bridge
source .venv/bin/activate
LINKUP_BRIDGE_PORT=8765 LINKUP_BRIDGE_REVERB_PORT=8080 \
uvicorn app.main:app --host 127.0.0.1 --port 8765
```

### Terminal B

```bash
cd /home/mahamane/Bureau/Mahamane/linkUp/bridge
source .venv/bin/activate
LINKUP_BRIDGE_PORT=8766 LINKUP_BRIDGE_REVERB_PORT=8081 \
uvicorn app.main:app --host 127.0.0.1 --port 8766
```

### Puis verifier

```bash
curl http://127.0.0.1:8765/mdns/services
curl http://127.0.0.1:8766/mdns/services
```

But :

- voir que les deux bridges se detectent

### Important

Dans ce cas :

- le premier bridge annonce `reverb_port=8080`
- le second annonce `reverb_port=8081`

---

## 13. Tester les tests automatises

## 13.1 Tests Python

```bash
cd /home/mahamane/Bureau/Mahamane/linkUp/bridge
source .venv/bin/activate
pytest -q
```

Ou plus precisement :

```bash
pytest -q tests/test_health.py tests/test_mdns.py
```

## 13.2 Qualite Python

```bash
ruff check app tests
black --check app tests
```

## 13.3 Tests Laravel

```bash
cd /home/mahamane/Bureau/Mahamane/linkUp/agent
php artisan test
```

Ou seulement les tests importants :

```bash
php artisan test tests/Feature/PingEventTest.php tests/Feature/MdnsAnnouncerTest.php
```

---

## 14. Ce que tu peux tester aujourd'hui et ce que tu ne peux pas encore tester

## 14.1 Testable aujourd'hui

- demarrage Laravel
- demarrage Reverb
- demarrage bridge Python
- route `/api/health`
- route `/health`
- facade Laravel -> bridge
- mDNS info local
- liste mDNS
- heartbeat / TTL / purge
- tests Python et Laravel

## 14.2 Pas encore vraiment testable comme fonctionnalite produit complete

- scan QR mobile Linkup reel
- liste d'agents dans Flutter Linkup
- vrai dashboard Linkup
- pairing complet
- modules medias / terminal / galerie / camera

Parce que :

- mobile et dashboard sont encore surtout des templates

---

## 15. Pannes les plus courantes

## 15.1 `GET /api/agent/info` plante

Ca veut souvent dire :

- le bridge Python n'est pas lance
- le token ne correspond pas
- `LINKUP_BRIDGE_BASE_URL` est faux

## 15.2 `/mdns/services` est vide

Ca peut etre normal si :

- tu n'as qu'une seule machine
- le reseau filtre le multicast
- le second agent n'est pas vraiment lance

## 15.3 mDNS ne se voit pas sur le LAN

Ca peut venir de :

- firewall
- Wi-Fi avec isolation client
- container sans reseau host
- environnement de sandbox

## 15.4 Reverb semble demarre mais rien n'est recu

Pense a verifier :

- `BROADCAST_CONNECTION=reverb`
- ports `8080`
- futur client WebSocket bien configure

---

## 16. Ordre de debug conseille

Si quelque chose ne marche pas, verifie dans cet ordre :

1. `curl http://127.0.0.1:8765/health`
2. `curl http://127.0.0.1:8000/api/health`
3. `curl http://127.0.0.1:8765/mdns/info`
4. `curl http://127.0.0.1:8000/api/agent/info`
5. `curl http://127.0.0.1:8765/mdns/services`
6. `curl http://127.0.0.1:8000/api/mdns/services`
7. `POST /api/ping`

Cet ordre est bon parce qu'il va :

- du plus simple
- vers le plus compose

---

## 17. Sequence minimale que je te conseille

Si tu veux apprendre sans stress, fais juste ca :

### Etape 1

Lance le bridge :

```bash
uvicorn app.main:app --host 127.0.0.1 --port 8765
```

### Etape 2

Teste :

```bash
curl http://127.0.0.1:8765/health
curl http://127.0.0.1:8765/mdns/info
```

### Etape 3

Lance Laravel :

```bash
php artisan serve
```

### Etape 4

Teste :

```bash
curl http://127.0.0.1:8000/api/health
curl http://127.0.0.1:8000/api/agent/info
```

### Etape 5

Lance Reverb :

```bash
php artisan reverb:start
```

### Etape 6

Teste :

```bash
curl -X POST http://127.0.0.1:8000/api/ping \
  -H "Content-Type: application/json" \
  -d '{"message":"hello"}'
```

Une fois que tu comprends ces 6 etapes, tu comprends deja le coeur du socle actuel.

