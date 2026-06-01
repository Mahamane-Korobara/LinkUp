# Linkup Bridge

OS bridge — piloté **localement** par l'agent Laravel. Pas exposé directement au réseau (sauf le service mDNS qui annonce l'agent sur le LAN).

## Quick start

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env
uvicorn app.main:app --reload --host 127.0.0.1 --port 8765
```

## Dépendances système (runtime)

Le bridge **shell-out** vers des outils natifs pour toucher l'OS. Côté
**utilisateur final, l'installeur (S6.5) les fournit automatiquement** — rien à
faire à la main (cf. `packaging/system-dependencies.md`). En **dev** (lancement
depuis les sources), installe-les une fois.

| Fonction | Linux | Windows | macOS |
|---|---|---|---|
| Ouvrir fichier / lien | `xdg-open` (paquet `xdg-utils`, ~toujours présent) | intégré (`start`) | intégré (`open`) |
| Presse-papier | **un** parmi `wl-clipboard` (Wayland) / `xclip` / `xsel` | intégré (`clip` + PowerShell) | intégré (`pbcopy`/`pbpaste`) |

→ **Windows : rien à installer.** **Linux en dev :**

```bash
# Debian / Ubuntu
sudo apt install -y wl-clipboard xdg-utils      # (ou xclip à la place sur X11)
# Fedora
sudo dnf install -y wl-clipboard xdg-utils
# Arch
sudo pacman -S --needed wl-clipboard xdg-utils
```

Le bridge essaie les outils dans l'ordre et renvoie une **erreur claire**
(« installe wl-clipboard ») si aucun n'est présent — il ne plante pas.

## Endpoints

| Méthode | URL | Auth | Description |
|---|---|---|---|
| GET | `/health` | — | Statut + version + OS |
| GET | `/system/info` | Bearer | Infos système détaillées |
| GET | `/mdns/info` | — | Ce que CET agent annonce sur le LAN |
| GET | `/mdns/services` | — | Liste des agents Linkup découverts sur le LAN |
| POST | `/transfer/upload` | Bearer/scopé | Reçoit un chunk de fichier (S4) |
| POST | `/transfer/{id}/finalize` | Bearer/scopé | Recompose + vérifie le SHA-256 (S4) |
| POST | `/transfer/open` | Bearer | Ouvre un fichier de l'inbox sur le PC (S4) |
| GET | `/clipboard/read` | Bearer | Lit le presse-papier du PC (S5) |
| POST | `/clipboard/write` | Bearer | Écrit dans le presse-papier du PC (S5) |
| POST | `/link/open` | Bearer | Ouvre un lien http(s) dans le navigateur (S5) |

## Tests

```bash
pytest -v
ruff check .
black --check .
```

---

## 🔎 Tester la découverte mDNS en local

### Option 1 — Avec `avahi-utils` (Linux uniquement)

```bash
sudo apt install avahi-utils

# Démarrer le bridge dans un terminal
uvicorn app.main:app --host 127.0.0.1 --port 8765

# Dans un autre terminal, observer en temps réel
avahi-browse -r _linkup._tcp

# Tu devrais voir quelque chose comme :
# = enp3s0 IPv4 linkup-abcd1234       _linkup._tcp         local
#    hostname = [ton-pc.local]
#    address = [192.168.1.42]
#    port = [8080]
#    txt = ["host=ton-pc" "fp=pending" "v=0.1.0" "id=linkup-abcd1234"]
```

### Option 2 — Via le bridge lui-même (multi-OS)

```bash
# Terminal 1 : démarrer le bridge
uvicorn app.main:app --host 127.0.0.1 --port 8765

# Terminal 2 : voir ce que le bridge annonce
curl -s http://127.0.0.1:8765/mdns/info | jq

# Voir tout ce qu'il découvre sur le LAN (s'inclut lui-même)
curl -s http://127.0.0.1:8765/mdns/services | jq
```

### Option 3 — Tester avec 2 instances (le scénario réel multi-PC)

Simule deux agents Linkup sur le même réseau, en bricolant deux instances du bridge.

```bash
# Terminal 1 — instance "alpha" sur le port 8765
LINKUP_BRIDGE_PORT=8765 LINKUP_BRIDGE_REVERB_PORT=8080 \
  uvicorn app.main:app --host 127.0.0.1 --port 8765

# Terminal 2 — instance "beta" sur le port 8766 (simule un autre PC)
LINKUP_BRIDGE_PORT=8766 LINKUP_BRIDGE_REVERB_PORT=8081 \
  uvicorn app.main:app --host 127.0.0.1 --port 8766
```

Puis :

```bash
curl -s http://127.0.0.1:8765/mdns/services | jq '.count, .agents[].name'
# Devrait afficher 2 (alpha + beta)

curl -s http://127.0.0.1:8766/mdns/services | jq '.count, .agents[].name'
# Pareil, 2 agents visibles
```

> ℹ️ Les deux instances vont s'auto-découvrir car elles utilisent la même socket multicast `224.0.0.251:5353` (mDNS standard). Chaque instance se voit elle-même + l'autre.

### Option 4 — Depuis un autre PC / téléphone sur le même Wi-Fi

- **Android** : app *Service Browser* ou *Bonjour Browser*, chercher le type `_linkup._tcp`
- **Linux** : `avahi-browse -r _linkup._tcp`
- **Windows** : `dns-sd -B _linkup._tcp` (si Bonjour iTunes installé) ou *Network Service Discovery* tool
- **macOS** : `dns-sd -B _linkup._tcp`

### Pourquoi mDNS peut échouer ?

| Problème | Solution |
|---|---|
| Wi-Fi entreprise avec *client isolation* | Saisie manuelle IP/port dans le fallback Flutter |
| Box Internet (certaines Livebox) bloque multicast | UFW/pare-feu doit autoriser UDP 5353 |
| Multi-interfaces réseau (Ethernet + Wi-Fi + VPN) | Préciser `--interface` dans `avahi-publish` |
| Conteneur Docker sans `--network=host` | Le service mDNS ne sortira pas du conteneur |
| iOS sans permission *Local Network* | À demander dans Info.plist (Phase 2) |
