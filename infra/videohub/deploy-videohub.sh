#!/usr/bin/env bash
# Déploie / met à jour le service VideoHub sur le VPS (rsync + pip + restart).
# Le .env (secrets) n'est JAMAIS poussé : il vit sur le VPS (cf. README.md §2).
set -euo pipefail

VPS="${LINKUP_VPS:-root@72.61.194.76}"
REMOTE_DIR="/var/www/projects/linkup/videohub"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "==> rsync videohub/ → $VPS:$REMOTE_DIR"
rsync -az --delete \
  --exclude='.venv' --exclude='.env' --exclude='__pycache__' \
  --exclude='.pytest_cache' --exclude='tests' --exclude='cookies.txt' \
  "$ROOT/videohub/" "$VPS:$REMOTE_DIR/"

echo "==> venv + dépendances + redémarrage"
ssh "$VPS" bash -s <<'REMOTE'
set -euo pipefail
cd /var/www/projects/linkup/videohub
[ -d .venv ] || python3 -m venv .venv
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -r requirements.txt
chown -R www-data:www-data /var/www/projects/linkup/videohub
supervisorctl restart linkup-videohub || supervisorctl start linkup-videohub
sleep 2
curl -fsS localhost:8780/health && echo " ✓ videohub up"
REMOTE

echo "✓ Déploiement terminé."
