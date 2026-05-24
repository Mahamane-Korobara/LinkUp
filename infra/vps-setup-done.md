# VPS Linkup — État de la configuration

> **NE PAS COMMITER** ce fichier s'il contient des secrets (le .gitignore couvre infra/secrets/).
> Ce fichier est un mémo de référence local uniquement.

## Infos VPS

| | |
|---|---|
| **IP** | 72.61.194.76 |
| **OS** | Ubuntu 24.04 LTS |
| **RAM** | 7.8 Go |
| **Disk** | 96 Go (7.7 Go utilisés) |
| **Web server** | Apache 2 (pas Nginx) |
| **PHP** | 8.4 FPM |
| **MySQL** | actif sur 127.0.0.1:3306 |
| **Docker** | actif |
| **Supervisor** | actif |

---

## ✅ Ce qui est installé et configuré

### coturn (TURN server WebRTC)
- Port UDP/TCP : **3478**
- Port TLS : **5349**
- Realm : `sahelstack.tech`
- Méthode auth : HMAC REST (credentials éphémères générés par Laravel, TTL 1h)
- Secret stocké dans : `/etc/linkup-secrets.env` (chmod 600)
- Config : `/etc/turnserver.conf`
- Logs : `/var/log/linkup/coturn.log`
- Statut : `systemctl status coturn` → **active (running)**

### autossh
- Installé : `/usr/bin/autossh`
- Utilisé côté **PC agent** (pas côté VPS) — cf. service systemd ci-dessous

### SSH tunnel
- Utilisateur dédié : `linkup-tunnel` (shell `/bin/false`)
- Authorized keys : `/home/linkup-tunnel/.ssh/authorized_keys` ← **à remplir avec la clé publique du PC agent**
- `GatewayPorts yes` et `AllowTcpForwarding yes` activés dans sshd
- Ports tunnelés : `18080` (Reverb) + `18000` (Laravel HTTP)

### Apache vhosts
- `linkup.sahelstack.tech` → proxy `127.0.0.1:18080` (HTTP API)
- `relay.sahelstack.tech` → proxy WebSocket `127.0.0.1:18080` (Reverb)
- SSL : **pas encore** — à faire après DNS (voir ci-dessous)

### UFW Firewall
| Port | Protocole | Usage |
|---|---|---|
| 22, 2222 | TCP | SSH |
| 80, 443 | TCP | Apache HTTP/HTTPS |
| 3478 | TCP + UDP | TURN |
| 5349 | TCP + UDP | TURNS TLS |
| 49152-65535 | UDP | WebRTC media relay |

### Supervisor
- Config : `/etc/supervisor/conf.d/linkup.conf`
- Programmes : `linkup:linkup-reverb`, `linkup:linkup-worker`, `linkup-bridge`
- Statut : **STOPPED** (normal — code pas encore déployé, `autostart=false`)

### Répertoires
```
/var/www/projects/linkup/
├── agent/        ← code Laravel (déploiement futur)
├── releases/     ← historique releases (déploiement Envoyer style)
└── shared/
    ├── storage/
    └── logs/
/var/log/linkup/  ← tous les logs Linkup
```

---

## ⏳ Étapes restantes (à faire avant B7)

### 1. Ajouter les DNS (chez ton registrar / Hostinger DNS)

Aller dans le panneau DNS de `sahelstack.tech` et ajouter :

```
linkup    A    72.61.194.76    TTL 3600
relay     A    72.61.194.76    TTL 3600
```

### 2. Générer SSL avec Certbot (après DNS propagé ~5-30 min)

```bash
ssh root@72.61.194.76
certbot --apache -d linkup.sahelstack.tech -d relay.sahelstack.tech
```

### 3. Activer TLS coturn

Décommenter dans `/etc/turnserver.conf` :
```
cert=/etc/letsencrypt/live/linkup.sahelstack.tech/fullchain.pem
pkey=/etc/letsencrypt/live/linkup.sahelstack.tech/privkey.pem
```
Puis : `systemctl restart coturn`

### 4. Générer la clé SSH du PC agent + la déposer sur le VPS

Sur le PC de développement :
```bash
ssh-keygen -t ed25519 -f ~/.linkup/keys/tunnel_ed25519 -N "" -C "linkup-agent-tunnel"
cat ~/.linkup/keys/tunnel_ed25519.pub
```

Puis sur le VPS :
```bash
echo "<clé publique>" >> /home/linkup-tunnel/.ssh/authorized_keys
```

### 5. Déployer le code (en B8 — sprint packaging)

```bash
# Depuis CI ou manuellement :
rsync -avz --exclude='.git' agent/ root@72.61.194.76:/var/www/projects/linkup/agent/
ssh root@72.61.194.76 "cd /var/www/projects/linkup/agent && composer install --no-dev && php artisan migrate --force"
supervisorctl start linkup:all
supervisorctl start linkup-bridge
```

---

## Commande autossh (côté PC agent — S20)

Service systemd à créer sur le PC Linux :

```ini
# /etc/systemd/system/linkup-tunnel.service
[Unit]
Description=Linkup reverse SSH tunnel to VPS
After=network-online.target
Wants=network-online.target

[Service]
User=mahamane
ExecStart=/usr/bin/autossh -M 0 -N \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -o StrictHostKeyChecking=no \
  -i /home/mahamane/.linkup/keys/tunnel_ed25519 \
  -R 18080:localhost:8080 \
  -R 18000:localhost:8000 \
  linkup-tunnel@72.61.194.76
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable linkup-tunnel
systemctl start linkup-tunnel
```

---

## Secret coturn

> ⚠️ NE PAS partager — stocker dans le `.env` de l'agent Laravel sous `COTURN_SECRET`

```
COTURN_SECRET=7296fac70958daa98e4019b13bf1f211470c24f71f09b0020f045584c172da68
```

Le Laravel agent génèrera des credentials éphémères ainsi :
```php
$ttl = time() + 3600; // 1h
$username = $ttl . ':linkup-' . $deviceId;
$password = base64_encode(hash_hmac('sha1', $username, env('COTURN_SECRET'), true));
```
