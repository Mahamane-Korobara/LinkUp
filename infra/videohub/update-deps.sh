#!/usr/bin/env bash
# MAJ hebdomadaire des dépendances VOLATILES de VideoHub : yt-dlp et ses plugins
# (les sites changent souvent → yt-dlp se répare vite en amont), + l'image Docker
# du POT provider, puis redémarrage du service. Installé en cron hebdo sur le VPS
# (/etc/cron.d/linkup-videohub-update). Logge dans /var/log/linkup/videohub-update.log.
set -uo pipefail

DIR=/var/www/projects/linkup/videohub
LOG=/var/log/linkup/videohub-update.log
exec >>"$LOG" 2>&1

echo "===== $(date -Is) — MAJ deps VideoHub ====="

# venv (perms www-data) : yt-dlp + provider PO token + solveur EJS.
# PIP_CACHE_DIR inscriptible par www-data (sinon warning « cache disabled »).
sudo -u www-data env PIP_CACHE_DIR="$DIR/.pip-cache" \
  "$DIR/.venv/bin/pip" install -U --quiet \
  yt-dlp bgutil-ytdlp-pot-provider yt-dlp-ejs curl_cffi \
  && echo "pip -U OK" || echo "pip -U ÉCHEC"

# POT provider (conteneur Docker) — on rafraîchit l'image latest.
docker pull -q brainicism/bgutil-ytdlp-pot-provider >/dev/null 2>&1 || true
docker rm -f bgutil-pot >/dev/null 2>&1 || true
docker run -d --name bgutil-pot --restart unless-stopped \
  -p 127.0.0.1:4416:4416 brainicism/bgutil-ytdlp-pot-provider >/dev/null 2>&1 \
  && echo "bgutil-pot relancé" || echo "bgutil-pot ÉCHEC"

# Redémarrage du service + contrôle de santé.
supervisorctl restart linkup-videohub >/dev/null 2>&1
sleep 3
if curl -fsS localhost:8780/health >/dev/null 2>&1; then
  echo "service up — yt-dlp $("$DIR/.venv/bin/yt-dlp" --version 2>/dev/null)"
else
  echo "ALERTE: service KO après MAJ"
fi
echo ""
