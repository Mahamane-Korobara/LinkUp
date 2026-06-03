#!/usr/bin/env bash
# Lanceur du bundle Linkup (ce que l'app installée exécute).
#
# Démarre les DEUX binaires autonomes du PC :
#   - linkup-bridge : accès OS (presse-papier, ouvrir, mDNS) — DOIT écouter sur
#     0.0.0.0 car le téléphone lui pousse les chunks de fichiers en direct (LAN).
#   - frankenphp    : agent Laravel (/api/*) + dashboard statique, sur :8000.
#
# 1er lancement : génère APP_KEY + un token partagé agent↔bridge + la base SQLite.
# Aucune dépendance système (PHP/Python/Node tous embarqués).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

export LINKUP_AGENT_PUBLIC="$HERE/agent/public"
export LINKUP_DASHBOARD_OUT="$HERE/dashboard-out"
export LINKUP_HTTP_PORT="${LINKUP_HTTP_PORT:-8000}"
export LINKUP_BRIDGE_HOST="0.0.0.0"          # joignable par le tél sur le LAN
export LINKUP_BRIDGE_PORT="${LINKUP_BRIDGE_PORT:-8765}"

ENV_FILE="$HERE/agent/.env"

# --- Initialisation au premier lancement -----------------------------------
if [ ! -f "$HERE/.initialized" ]; then
  [ -f "$ENV_FILE" ] || cp "$HERE/agent/.env.example" "$ENV_FILE" 2>/dev/null || : >"$ENV_FILE"

  set_env() {
    local k="$1" v="$2"
    if grep -q "^${k}=" "$ENV_FILE"; then sed -i "s|^${k}=.*|${k}=${v}|" "$ENV_FILE"
    else printf '%s=%s\n' "$k" "$v" >>"$ENV_FILE"; fi
  }
  set_env APP_ENV production
  set_env DB_CONNECTION sqlite                 # zéro install : base fichier
  # Chemin ABSOLU : sinon SQLite prend DB_DATABASE (hérité de .env.example, ex.
  # « linkup ») comme un chemin relatif et migre dans le mauvais fichier.
  set_env DB_DATABASE "$HERE/agent/database/database.sqlite"
  set_env LINKUP_BRIDGE_AGENT_TOKEN "$(openssl rand -hex 32 2>/dev/null || head -c32 /dev/urandom | xxd -p | tr -d '\n')"

  : >"$HERE/agent/database/database.sqlite"
  "$HERE/frankenphp" php-cli "$HERE/agent/artisan" key:generate --force
  "$HERE/frankenphp" php-cli "$HERE/agent/artisan" migrate --force
  touch "$HERE/.initialized"
fi

# Token partagé : le bridge le lit dans l'environnement.
export LINKUP_BRIDGE_AGENT_TOKEN="$(grep '^LINKUP_BRIDGE_AGENT_TOKEN=' "$ENV_FILE" | cut -d= -f2-)"
# S6.6 : les reçus sont rangés par catégorie sous Transfert/{photos,video,fichiers}.
# L'ancien Inbox/ reste fouillé en fallback (cf. InboxLocator / resolve_in_inbox).
export LINKUP_BRIDGE_TRANSFERS_DIR="${LINKUP_BRIDGE_TRANSFERS_DIR:-$HOME/Linkup/Transfert}"
mkdir -p "$HOME/Linkup/Transfert" "$HOME/Linkup/Outbox"

# --- Démarrage ---------------------------------------------------------------
"$HERE/linkup-bridge" &
BRIDGE_PID=$!
trap 'kill "$BRIDGE_PID" 2>/dev/null || true' EXIT INT TERM

echo "Linkup démarré → dashboard : http://localhost:${LINKUP_HTTP_PORT}"
exec "$HERE/frankenphp" run --config "$HERE/Caddyfile"
