# Déploiement VideoHub (VPS)

Service FastAPI **internet-facing** (téléchargeur vidéo + transcript) tournant sur le VPS
`sahelstack.tech`, derrière Apache, géré par supervisor. Distinct du bridge PC (LAN).

```
Tél (app) ──HTTPS──► linkup.sahelstack.tech/video/* ──► 127.0.0.1:8780 (uvicorn videohub)
                          (Apache, cert Let's Encrypt)        yt-dlp + ffmpeg + Gemini
```

## 1. Prérequis VPS (une fois)

```bash
ssh root@72.61.194.76
apt update && apt install -y ffmpeg python3-venv
mkdir -p /var/www/projects/linkup/videohub
```

## 2. Secret (une fois, NON commité)

```bash
# Sur le VPS, créer /var/www/projects/linkup/videohub/.env (chmod 600) :
LINKUP_VIDEOHUB_SERVICE_TOKEN=<python -c 'import secrets; print(secrets.token_urlsafe(32))'>
LINKUP_VIDEOHUB_GEMINI_API_KEY=<clé gratuite https://aistudio.google.com/apikey>
LINKUP_VIDEOHUB_GEMINI_MODEL=gemini-3.5-flash
# Optionnel — débloque YouTube (cf. §7) :
LINKUP_VIDEOHUB_YT_COOKIES_FILE=/var/www/projects/linkup/videohub/cookies.txt
```
> Le **même** `SERVICE_TOKEN` doit être mis côté app dans
> `mobile/lib/services/video/video_hub_client.dart` (constante `_defaultServiceToken`).

## 3. Supervisor

Copier `linkup-videohub.conf` dans `/etc/supervisor/conf.d/` (ou ajouter le bloc au
`linkup.conf` existant), puis :

```bash
supervisorctl reread && supervisorctl update && supervisorctl start linkup-videohub
```

## 4. Apache

Ajouter le bloc de `apache-video-location.conf` dans le vhost **HTTPS**
`linkup.sahelstack.tech` (`/etc/apache2/sites-available/linkup-le-ssl.conf`),
**AVANT** le `ProxyPass /` catch-all qui pointe vers le tunnel `:18000`
(Apache applique la première règle qui matche). Puis :

```bash
a2enmod proxy proxy_http   # si pas déjà actifs
apachectl configtest && systemctl reload apache2
```

## 5. Déploiement / mise à jour

Depuis le PC de dev : `infra/videohub/deploy-videohub.sh` (rsync + pip + restart).

## 6. Vérifier

```bash
curl https://linkup.sahelstack.tech/video/../health        # via uvicorn local d'abord :
ssh root@72.61.194.76 'curl -s localhost:8780/health'
curl -H "Authorization: Bearer <TOKEN>" \
  "https://linkup.sahelstack.tech/video/resolve?url=https://youtu.be/XXXX"
```

## 7. Débloquer YouTube (IP datacenter)

YouTube **bloque l'accès anonyme depuis une IP datacenter** : sans setup, on reçoit
« Sign in to confirm you're not a bot ». Les **autres plateformes (TikTok, Vimeo, Insta,
X…) marchent sans rien**. Pour YouTube il faut **4 briques** :

1. **Cookies** d'un compte connecté (idéalement jetable), au format Netscape, dans
   `cookies.txt` (chmod 600, `www-data`). Exporté via une extension navigateur. Pointé par
   `LINKUP_VIDEOHUB_YT_COOKIES_FILE`. ⚠️ **expirent** (jours/semaines) → à régénérer quand
   YouTube recommence à échouer. Fichier **gitignored** (jamais sur GitHub).
2. **PO Token provider** (proof-of-origin) — conteneur Docker, redémarrage auto :
   ```bash
   docker run -d --name bgutil-pot --restart unless-stopped \
     -p 127.0.0.1:4416:4416 brainicism/bgutil-ytdlp-pot-provider
   ```
3. **Plugin yt-dlp** qui parle au provider : `.venv/bin/pip install bgutil-ytdlp-pot-provider`.
4. **Runtime JS + solveur EJS** pour le défi « n » : Deno (`curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh -s -- -y`)
   + `.venv/bin/pip install yt-dlp-ejs`. Le service a besoin de `deno` dans son `PATH` et
   d'un `DENO_DIR` inscriptible → déjà dans `linkup-videohub.conf` (`environment=…`).

Test : `ssh root@72.61.194.76 'cd …/videohub && PATH=/usr/local/bin:$PATH .venv/bin/yt-dlp --cookies cookies.txt --skip-download --print "%(title)s" "https://youtu.be/jNQXAC9IVRw"'`

> Pile **fragile par nature** (YouTube change souvent). En cas d'échec YouTube : 1) refaire
> les cookies, 2) `docker restart bgutil-pot`, 3) `pip install -U yt-dlp bgutil-ytdlp-pot-provider yt-dlp-ejs`.
