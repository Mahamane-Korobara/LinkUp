#!/usr/bin/env bash
# Lanceur Linkup (partagé .deb et AppImage). Modèle « application » :
#   clic → démarre le hub + ouvre le dashboard dans une fenêtre dédiée ;
#   on FERME la fenêtre → le hub s'arrête (le port se libère).
#
# Le hub = frankenphp (agent Laravel + dashboard statique, port 8770) +
# linkup-bridge (accès OS + LAN, port 8765). Port 8770 choisi pour ne PAS
# entrer en conflit avec le 8000/3000 des environnements de dev.
#
# L'app est en lecture seule (sous /opt/linkup pour le .deb, ou le montage
# squashfs pour l'AppImage) ; tout l'état inscriptible vit dans $XDG_DATA_HOME.
set -uo pipefail

APP_DIR="${LINKUP_APP_DIR:-/opt/linkup}"
STATE="${XDG_DATA_HOME:-$HOME/.local/share}/linkup"
AGENT="$STATE/agent"
PROFILE="$STATE/win"                       # profil navigateur dédié (détection de fermeture)
PORT="${LINKUP_HTTP_PORT:-8770}"
URL="http://localhost:${PORT}"

log() { logger -t linkup "$*" 2>/dev/null || true; }
health() { curl -fsS -m 1 "$URL/api/health" >/dev/null 2>&1; }

# Chemin ABSOLU d'une icône installée (jamais d'icône cassée sur le bureau).
icon_abs() {
  local p
  for p in "$HOME/.local/share/icons/hicolor/512x512/apps/linkup.png" \
           "/usr/share/icons/hicolor/512x512/apps/linkup.png" \
           "$APP_DIR/linkup.png"; do
    [ -f "$p" ] && { echo "$p"; return; }
  done
}

# Intégration AppImage : entrée menu + icône (PAS d'autostart : modèle « app »).
integrate_appimage() {
  [ -n "${APPIMAGE:-}" ] || return 0
  local apps="$HOME/.local/share/applications"
  local icondir="$HOME/.local/share/icons/hicolor/512x512/apps"
  mkdir -p "$apps" "$icondir"
  [ -f "$APP_DIR/linkup.png" ] && cp -f "$APP_DIR/linkup.png" "$icondir/linkup.png"
  # Ancien autostart d'une version précédente → on le retire (modèle app désormais).
  rm -f "$HOME/.config/autostart/linkup.desktop" 2>/dev/null || true
  cat > "$apps/linkup.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Linkup
GenericName=Hub téléphone ⇄ PC
Comment=Relie ton téléphone et ton PC sur le réseau local
Exec=$APPIMAGE
Icon=$(icon_abs)
Terminal=false
Categories=Network;
StartupNotify=true
EOF
  update-desktop-database "$apps" 2>/dev/null || true
}

# Icône cliquable sur le bureau (dossier localisé, ex. ~/Bureau), Icon en chemin
# ABSOLU + marquée « de confiance ». Idempotent.
place_desktop_icon() {
  local desk src ic
  desk="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
  [ -d "$desk" ] || return 0
  if [ -f /usr/share/applications/linkup.desktop ]; then
    src=/usr/share/applications/linkup.desktop          # .deb
  else
    src="$HOME/.local/share/applications/linkup.desktop" # AppImage
  fi
  [ -f "$src" ] || return 0
  ic="$(icon_abs)"
  # (Re)génère pour garantir une icône absolue (corrige les icônes cassées).
  sed "s|^Icon=.*|Icon=${ic}|" "$src" > "$desk/linkup.desktop"
  chmod +x "$desk/linkup.desktop"
  gio set "$desk/linkup.desktop" metadata::trusted true 2>/dev/null || true
}

# Empreinte du build embarqué (écrite par build-bundle-linux.sh dans l'agent).
app_build()   { cat "$APP_DIR/agent/LINKUP_BUILD" 2>/dev/null || echo ""; }
state_build() { cat "$AGENT/LINKUP_BUILD" 2>/dev/null || echo ""; }

# Rafraîchit le CODE de l'agent depuis l'app installée, en PRÉSERVANT l'état
# inscriptible (.env → APP_KEY + token, et la base SQLite). On ne recopie que le
# fichier .sqlite (pas tout le dossier database) pour garder les NOUVELLES
# migrations livrées avec la mise à jour, puis on les applique.
refresh_agent_code() {
  local newdir="$STATE/agent.new"
  rm -rf "$newdir"
  cp -a "$APP_DIR/agent" "$newdir"
  cp -a "$AGENT/.env" "$newdir/.env" 2>/dev/null || true
  mkdir -p "$newdir/database"
  cp -a "$AGENT/database/database.sqlite" "$newdir/database/database.sqlite" 2>/dev/null || true
  rm -rf "$AGENT"
  mv "$newdir" "$AGENT"
  "$APP_DIR/frankenphp" php-cli "$AGENT/artisan" migrate --force
}

# Init/MAJ par-utilisateur (idempotent). 1er lancement → init complète. Lancements
# suivants → si le build embarqué a changé (mise à jour du .deb/AppImage), on
# rafraîchit le code ; sinon la copie inscriptible garderait l'ANCIENNE version
# (routes manquantes, etc.).
ensure_init() {
  mkdir -p "$STATE"
  if [ -f "$STATE/.initialized" ]; then
    local src; src="$(app_build)"
    if [ -n "$src" ] && [ "$src" != "$(state_build)" ]; then
      command -v notify-send >/dev/null 2>&1 && \
        notify-send -i "$(icon_abs)" "Linkup" "Mise à jour…" || true
      refresh_agent_code
    fi
    return 0
  fi
  command -v notify-send >/dev/null 2>&1 && \
    notify-send -i "$(icon_abs)" "Linkup" "Préparation au premier démarrage…" || true

  rm -rf "$AGENT"
  cp -a "$APP_DIR/agent" "$AGENT"
  local env_file="$AGENT/.env"
  [ -f "$env_file" ] || cp "$AGENT/.env.example" "$env_file" 2>/dev/null || : >"$env_file"
  set_env() {
    local k="$1" v="$2"
    if grep -q "^${k}=" "$env_file"; then sed -i "s|^${k}=.*|${k}=${v}|" "$env_file"
    else printf '%s=%s\n' "$k" "$v" >>"$env_file"; fi
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
  touch "$STATE/.initialized"
}

# Ouvre le dashboard dans une fenêtre-app dédiée (profil isolé → on peut
# détecter sa fermeture). Renvoie 0 si Chromium (fermeture détectable),
# 1 si fallback navigateur par défaut (non détectable).
open_dashboard() {
  local b
  for b in google-chrome google-chrome-stable chromium chromium-browser brave-browser microsoft-edge; do
    if command -v "$b" >/dev/null 2>&1; then
      "$b" --app="$URL" --user-data-dir="$PROFILE" \
           --no-first-run --no-default-browser-check >/dev/null 2>&1 &
      return 0
    fi
  done
  xdg-open "$URL" >/dev/null 2>&1 &
  return 1
}

start_hub() {
  export LINKUP_AGENT_PUBLIC="$AGENT/public"
  export LINKUP_DASHBOARD_OUT="$APP_DIR/dashboard-out"
  export LINKUP_HTTP_PORT="$PORT"
  export LINKUP_PAIRING_PORT="$PORT"        # le QR de pairing encode CE port
  export LINKUP_BRIDGE_HOST="0.0.0.0"
  export LINKUP_BRIDGE_PORT="${LINKUP_BRIDGE_PORT:-8765}"
  export LINKUP_BRIDGE_LARAVEL_PORT="$PORT"   # annoncé au tél via /health + mDNS
  export LINKUP_BRIDGE_AGENT_TOKEN="$(grep '^LINKUP_BRIDGE_AGENT_TOKEN=' "$AGENT/.env" | cut -d= -f2-)"
  export LINKUP_BRIDGE_TRANSFERS_DIR="${LINKUP_BRIDGE_TRANSFERS_DIR:-$HOME/Linkup/Transfert}"
  mkdir -p "$HOME/Linkup/Transfert" "$HOME/Linkup/Outbox"
  "$APP_DIR/linkup-bridge" >/dev/null 2>&1 &
  BRIDGE_PID=$!
  "$APP_DIR/frankenphp" run --config "$APP_DIR/Caddyfile" >/dev/null 2>&1 &
  FRANKEN_PID=$!
}

# --------------------------------------------------------------------------- run
integrate_appimage
place_desktop_icon

# Déjà lancé (autre instance) ? On ouvre juste une fenêtre, sans gérer le cycle.
if health; then
  open_dashboard
  exit 0
fi

ensure_init
start_hub
trap 'kill "${BRIDGE_PID:-}" "${FRANKEN_PID:-}" 2>/dev/null || true' EXIT INT TERM
for _ in $(seq 1 80); do health && break; sleep 0.25; done
log "hub démarré (bridge=${BRIDGE_PID:-?} frankenphp=${FRANKEN_PID:-?}) sur $PORT"

if open_dashboard; then
  # Tant que la fenêtre dédiée est ouverte, on garde le hub. À sa fermeture,
  # la boucle se termine → le trap arrête le hub (le port se libère).
  sleep 2
  while pgrep -f -- "--user-data-dir=$PROFILE" >/dev/null 2>&1; do sleep 2; done
else
  # Pas de Chromium : impossible de détecter la fermeture → on garde le hub
  # vivant tant que le process tourne (l'utilisateur ferme via une déconnexion).
  wait "$FRANKEN_PID"
fi
