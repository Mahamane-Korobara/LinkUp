#!/usr/bin/env bash
# Lanceur Linkup installé par le .deb (/opt/linkup/bin/linkup).
#
# Cliqué depuis le menu/bureau (zéro terminal) : démarre les deux binaires
# embarqués (frankenphp = agent Laravel + dashboard sur :8000, linkup-bridge =
# accès OS + LAN sur :8765), puis ouvre le dashboard. Mono-instance : si Linkup
# tourne déjà, on se contente de rouvrir la fenêtre.
#
# L'app est en lecture seule sous /opt/linkup ; tout l'état inscriptible (clé,
# token, base SQLite, logs Laravel) vit dans l'espace utilisateur.
set -euo pipefail

APP_DIR="${LINKUP_APP_DIR:-/opt/linkup}"   # surchargé en test ; /opt/linkup en prod
STATE="${XDG_DATA_HOME:-$HOME/.local/share}/linkup"
AGENT="$STATE/agent"
PORT="${LINKUP_HTTP_PORT:-8000}"
URL="http://localhost:${PORT}"

log() { logger -t linkup "$*" 2>/dev/null || true; }

# Ouvre le dashboard : fenêtre-app dédiée si un navigateur Chromium est présent
# (rendu « vraie app »), sinon onglet normal via xdg-open.
open_dashboard() {
  for b in google-chrome google-chrome-stable chromium chromium-browser brave-browser microsoft-edge; do
    if command -v "$b" >/dev/null 2>&1; then
      "$b" --app="$URL" >/dev/null 2>&1 &
      return
    fi
  done
  xdg-open "$URL" >/dev/null 2>&1 &
}

# Déjà démarré ? → on rouvre juste la fenêtre et on sort.
if curl -fsS -m 1 "$URL/api/health" >/dev/null 2>&1; then
  open_dashboard
  exit 0
fi

mkdir -p "$STATE"

# --- Premier lancement (par utilisateur) -----------------------------------
if [ ! -f "$STATE/.initialized" ]; then
  command -v notify-send >/dev/null 2>&1 && \
    notify-send -i linkup "Linkup" "Préparation au premier démarrage…" || true

  # Copie de l'app Laravel dans l'espace utilisateur (storage/.env/SQLite y sont
  # inscriptibles, contrairement à /opt). Binaires + dashboard restent dans /opt.
  rm -rf "$AGENT"
  cp -a "$APP_DIR/agent" "$AGENT"

  ENV_FILE="$AGENT/.env"
  [ -f "$ENV_FILE" ] || cp "$AGENT/.env.example" "$ENV_FILE" 2>/dev/null || : >"$ENV_FILE"
  set_env() {
    local k="$1" v="$2"
    if grep -q "^${k}=" "$ENV_FILE"; then sed -i "s|^${k}=.*|${k}=${v}|" "$ENV_FILE"
    else printf '%s=%s\n' "$k" "$v" >>"$ENV_FILE"; fi
  }
  set_env APP_ENV production
  set_env DB_CONNECTION sqlite
  set_env DB_DATABASE "$AGENT/database/database.sqlite"
  set_env LINKUP_BRIDGE_AGENT_TOKEN \
    "$(openssl rand -hex 32 2>/dev/null || head -c32 /dev/urandom | xxd -p | tr -d '\n')"

  mkdir -p "$AGENT/database"
  : >"$AGENT/database/database.sqlite"
  "$APP_DIR/frankenphp" php-cli "$AGENT/artisan" key:generate --force
  "$APP_DIR/frankenphp" php-cli "$AGENT/artisan" migrate --force

  # Icône sur le bureau (dossier localisé, ex. ~/Bureau), marquée « de confiance »
  # pour qu'elle soit cliquable directement.
  DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
  if [ -d "$DESKTOP_DIR" ] && [ -f /usr/share/applications/linkup.desktop ]; then
    cp /usr/share/applications/linkup.desktop "$DESKTOP_DIR/linkup.desktop"
    chmod +x "$DESKTOP_DIR/linkup.desktop"
    gio set "$DESKTOP_DIR/linkup.desktop" metadata::trusted true 2>/dev/null || true
  fi

  touch "$STATE/.initialized"
fi

# --- Démarrage des services -------------------------------------------------
export LINKUP_AGENT_PUBLIC="$AGENT/public"
export LINKUP_DASHBOARD_OUT="$APP_DIR/dashboard-out"
export LINKUP_HTTP_PORT="$PORT"
export LINKUP_BRIDGE_HOST="0.0.0.0"
export LINKUP_BRIDGE_PORT="${LINKUP_BRIDGE_PORT:-8765}"
export LINKUP_BRIDGE_AGENT_TOKEN="$(grep '^LINKUP_BRIDGE_AGENT_TOKEN=' "$AGENT/.env" | cut -d= -f2-)"
export LINKUP_BRIDGE_TRANSFERS_DIR="${LINKUP_BRIDGE_TRANSFERS_DIR:-$HOME/Linkup/Transfert}"
mkdir -p "$HOME/Linkup/Transfert" "$HOME/Linkup/Outbox"

"$APP_DIR/linkup-bridge" >/dev/null 2>&1 &
BRIDGE_PID=$!
"$APP_DIR/frankenphp" run --config "$APP_DIR/Caddyfile" >/dev/null 2>&1 &
FRANKEN_PID=$!
trap 'kill "$BRIDGE_PID" "$FRANKEN_PID" 2>/dev/null || true' EXIT INT TERM
log "démarré (bridge=$BRIDGE_PID frankenphp=$FRANKEN_PID)"

# Attendre que l'agent réponde, puis ouvrir le dashboard.
for _ in $(seq 1 60); do
  curl -fsS -m 1 "$URL/api/health" >/dev/null 2>&1 && break
  sleep 0.25
done
open_dashboard

# Garder le hub vivant (il doit rester joignable par le téléphone sur le LAN)
# tant que la session ne le coupe pas.
wait
