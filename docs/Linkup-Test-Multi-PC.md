# Linkup — Test multi-PC (T1.20)

Objectif : valider sur **2 PCs réels** que la découverte mDNS + LAN sweep fonctionne, comme demandé par T1.20 du plan.

---

## 1. Prérequis

| Élément | Détail |
|---|---|
| PC #1 | celui où tu développes (Ubuntu actuel) |
| PC #2 | Ubuntu/Debian, accès SSH ou physique |
| Réseau | les 2 PCs sur le même Wi-Fi (test A) puis hotspot (test B) |
| Téléphone | optionnel — pour valider que le tel voit les 2 agents |

---

## 2. Install Linkup sur PC #2 (~15-20 min)

### 2.1 Cloner le repo

Option A — via GitHub (si tu l'as poussé) :
```bash
cd ~
git clone <ton-url-github>/linkup.git
cd linkup
```

Option B — via USB / scp depuis PC #1 :
```bash
# Sur PC #1 :
cd ~/Bureau/Mahamane
tar czf linkup.tar.gz --exclude='.venv' --exclude='vendor' --exclude='node_modules' --exclude='.dart_tool' --exclude='build' linkup/

# Transférer linkup.tar.gz sur PC #2, puis :
cd ~ && tar xzf linkup.tar.gz && cd linkup
```

### 2.2 Installer les dépendances système

```bash
sudo apt update
sudo apt install -y php8.4-cli php8.4-sqlite3 php8.4-mbstring php8.4-zip php8.4-curl \
                    php8.4-xml php8.4-bcmath \
                    composer python3 python3-venv python3-pip \
                    sqlite3 git curl
```

Si `php8.4` n'est pas disponible :
```bash
sudo add-apt-repository ppa:ondrej/php
sudo apt update
sudo apt install -y php8.4-cli php8.4-sqlite3 php8.4-mbstring php8.4-zip php8.4-curl
```

### 2.3 Agent Laravel

```bash
cd ~/linkup/agent
composer install --no-dev
cp .env.example .env
php artisan key:generate
php artisan reverb:install   # génère REVERB_APP_ID/KEY/SECRET
php artisan migrate
```

### 2.4 Bridge Python

```bash
cd ~/linkup/bridge
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env

# Génération token bridge (DIFFÉRENT du PC #1, c'est OK chaque PC son token)
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
# Copier la sortie dans LINKUP_BRIDGE_AGENT_TOKEN dans .env
nano .env   # ou : sed -i "s|change-me-to-a-random-32-bytes-base64|<TON_TOKEN>|" .env
```

### 2.5 Vérif locale PC #2

Trois terminaux sur PC #2 :

```bash
# Terminal A — Bridge
cd ~/linkup/bridge && source .venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8765

# Terminal B — Laravel
cd ~/linkup/agent
php artisan serve --host=0.0.0.0 --port=8000

# Terminal C — test
curl http://127.0.0.1:8765/health        # doit retourner agent_id, host, user
curl http://127.0.0.1:8000/api/health    # doit retourner status:ok
curl http://127.0.0.1:8000/api/agent/info # doit proxifier vers le bridge
```

Si les 3 curls répondent OK → PC #2 est prêt.

---

## 3. Pare-feu PC #1 et PC #2

Sur **chacun des 2 PCs** :

```bash
sudo ufw status

# Si UFW est actif, ouvrir les ports (adapter le subnet)
SUBNET=$(ip route | grep -oP 'src \K[\d.]+' | head -1 | sed 's|\.[0-9]*$|.0/24|')
sudo ufw allow from $SUBNET to any port 8765 proto tcp
sudo ufw allow from $SUBNET to any port 5353 proto udp
sudo ufw allow from $SUBNET to any port 8000 proto tcp
```

---

## 4. Test A — même Wi-Fi maison ✅ mDNS + sweep

### Préparation

- Connecter **PC #1 ET PC #2** à ta box Wi-Fi
- Récupérer les IPs :
  ```bash
  # Sur chaque PC
  hostname -I | awk '{print $1}'
  ```

### Lancer les bridges en parallèle

| PC | Commande |
|---|---|
| PC #1 | `cd ~/Bureau/Mahamane/linkUp/bridge && source .venv/bin/activate && uvicorn app.main:app --host 0.0.0.0 --port 8765` |
| PC #2 | `cd ~/linkup/bridge && source .venv/bin/activate && uvicorn app.main:app --host 0.0.0.0 --port 8765` |

### Vérifs croisées

**Depuis PC #1** :
```bash
# Voir l'annonce mDNS du PC #2 (et de lui-même)
avahi-browse -a -t | grep linkup

# Lister les agents découverts par le bridge PC#1
curl -s http://127.0.0.1:8765/mdns/services | python3 -m json.tool

# Frapper directement PC #2 en HTTP
curl http://<IP_PC2>:8765/health
```

**Depuis PC #2** : pareil avec `<IP_PC1>`.

**DoD test A :**
- [ ] `avahi-browse` voit les 2 agents `linkup-xxxx`
- [ ] `/mdns/services` sur PC#1 liste PC#2 (et inversement)
- [ ] curl `/health` cross-PC répond avec `agent_id` correct

### Bonus : tel sur le même Wi-Fi

Connecte ton tel à la même box, ouvre l'app :
- [ ] Les 2 PC apparaissent dans la liste « Sélectionner un agent Linkup »
- [ ] Tap sur l'un → écran détail charge `/api/agent/info` du PC choisi

---

## 5. Test B — hotspot téléphone ⚠️ sweep seul

Ce scénario reproduit le bug connu hotspot Samsung qui bloque le multicast.

### Préparation

- Activer le hotspot sur ton tel
- Connecter **PC #1 ET PC #2** au hotspot
- Vérifier les IPs : `hostname -I` → devraient être dans `192.168.144.0/24` (subnet hotspot Samsung)

### Lancer les bridges (idem test A)

### Vérifs

**Depuis PC #1** :
```bash
# avahi-browse va probablement voir QUE lui-même (multicast bloqué entre clients)
avahi-browse -a -t | grep linkup

# Mais en HTTP direct, ça passe
curl http://<IP_PC2>:8765/health
```

**DoD test B :**
- [ ] `avahi-browse` ne voit PAS l'autre PC (limitation hotspot, attendu)
- [ ] curl HTTP cross-PC fonctionne quand même
- [ ] Sur le tel : l'app voit les 2 PCs via le LAN sweep (pas via mDNS)

C'est le comportement attendu — et c'est exactement pourquoi le LAN sweep existe (cf. ADR-002).

---

## 6. Pannes courantes

### 6.1 Les 2 PCs ne se voient pas (test A)

Vérifier dans l'ordre :
- Les 2 sont sur le même Wi-Fi (pas un sur 2.4 et l'autre sur 5)
- Pare-feu : `sudo ufw status` puis ajouter les règles ci-dessus
- Wi-Fi de la box a-t-il « isolation client » activée ? Désactiver dans les params de la box
- `ping <IP_PC2>` répond depuis PC #1 ?

### 6.2 `php artisan reverb:install` plante sur PC #2

Si PHP < 8.2, mettre à jour avec le PPA ondrej (cf. §2.2).

### 6.3 Le tel voit un seul des 2 PCs

- Probablement scan trop court ou pas de retry suffisant
- Tape « Rescanner » manuellement dans l'app, attends 10s
- Vérifier que les 2 bridges répondent : `curl http://<IP_PC>:8765/health` depuis le tel via Termux ou un navigateur

---

## 7. DoD T1.20 (Plan d'exécution)

Du `Linkup-Plan-Execution.md` S1.J5 :

> Test manuel : 2 PC sur le même Wi-Fi, Flutter découvre les deux

Cocher :
- [ ] Test A passe (Wi-Fi maison, mDNS + sweep voient les 2 agents)
- [ ] Test B passe (hotspot, sweep seul voit les 2 agents)
- [ ] Sur le tel : 2 agents listés dans `AgentPickerScreen`, écran détail charge `/api/agent/info` pour chacun

Une fois ces 3 points cochés, **S1 est clos**. On peut attaquer S2 (pairing QR + Noise IK).
