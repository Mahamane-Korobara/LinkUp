#!/usr/bin/env bash
# Lanceur Linkup installé par le .deb (/opt/linkup/bin/linkup).
#
# Deux modes :
#   --serve  : lance le hub en avant-plan (utilisé par l'autostart de session).
#              Fait l'init 1er-run, pose l'icône bureau, démarre frankenphp
#              (agent + dashboard, :8000) + linkup-bridge (LAN, :8765).
#   --open   : (défaut, clic sur l'icône) s'assure que le hub tourne — le démarre
#              détaché si besoin — puis OUVRE le dashboard dans le navigateur.
#
# L'app est en lecture seule sous /opt/linkup ; tout l'état inscriptible (clé,
# token, base SQLite, logs) vit dans l'espace utilisateur ($XDG_DATA_HOME).
set -euo pipefail

APP_DIR="${LINKUP_APP_DIR:-/opt/linkup}"   # surchargé en test ; /opt/linkup en prod
STATE="${XDG_DATA_HOME:-$HOME/.local/share}/linkup"
AGENT="$STATE/agent"
PORT="${LINKUP_HTTP_PORT:-8000}"
URL="http://localhost:${PORT}"

log() { logger -t linkup "$*" 2>/dev/null || true; }
health() { curl -fsS -m 1 "$URL/api/health" >/dev/null 2>&1; }

# Ouvre le dashboard : fenêtre-app dédiée si un navigateur Chromium est présent
# (rendu « vraie app »), sinon onglet via le navigateur par défaut.
open_dashboard() {
  for b in google-chrome google-chrome-stable chromium chromium-browser brave-browser microsoft-edge; do
    if command -v "$b" >/dev/null 2>&1; then "$b" --app="$URL" >/dev/null 2>&1 & return; fi
  done
  xdg-open "$URL" >/dev/null 2>&1 &
}

# Chemin du .desktop « menu » : système (.deb) ou local utilisateur (AppImage).
menu_desktop_path() {
  if [ -f /usr/share/applications/linkup.desktop ]; then
    echo /usr/share/applications/linkup.desktop
  else
    echo "$HOME/.local/share/applications/linkup.desktop"
  fi
}

# Intégration AppImage : crée l'entrée menu + l'autostart + l'icône, pointant
# sur le chemin réel de l'AppImage ($APPIMAGE). No-op hors AppImage (.deb).
integrate_appimage() {
  [ -n "${APPIMAGE:-}" ] || return 0
  local apps="$HOME/.local/share/applications"
  local autostart="$HOME/.config/autostart"
  local icondir="$HOME/.local/share/icons/hicolor/512x512/apps"
  mkdir -p "$apps" "$autostart" "$icondir"
  [ -f "$APP_DIR/linkup.png" ] && cp -f "$APP_DIR/linkup.png" "$icondir/linkup.png"

  cat > "$apps/linkup.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Linkup
GenericName=Hub téléphone ⇄ PC
Comment=Relie ton téléphone et ton PC sur le réseau local
Exec=$APPIMAGE --open
Icon=linkup
Terminal=false
Categories=Network;
StartupNotify=true
EOF

  cat > "$autostart/linkup.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Linkup (service)
Exec=$APPIMAGE --serve
Icon=linkup
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=3
EOF

  update-desktop-database "$apps" 2>/dev/null || true
}

# Pose une icône cliquable sur le bureau (dossier localisé, ex. ~/Bureau),
# marquée « de confiance ». Idempotent.
place_desktop_icon() {
  local desk src
  desk="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
  src="$(menu_desktop_path)"
  [ -d "$desk" ] || return 0
  [ -f "$src" ] || return 0
  if [ ! -f "$desk/linkup.desktop" ]; then
    cp "$src" "$desk/linkup.desktop"
    chmod +x "$desk/linkup.desktop"
    gio set "$desk/linkup.desktop" metadata::trusted true 2>/dev/null || true
  fi
}

# Init par-utilisateur au tout premier lancement (idempotent via .initialized).
ensure_init() {
  mkdir -p "$STATE"
  [ -f "$STATE/.initialized" ] && return 0

  command -v notify-send >/dev/null 2>&1 && \
    notify-send -i linkup "Linkup" "Préparation au premier démarrage…" || true

  # Copie de l'app Laravel dans l'espace utilisateur (storage/.env/SQLite y sont
  # inscriptibles, contrairement à /opt). Binaires + dashboard restent dans /opt.
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

# Démarre les deux services en avant-plan (bloque jusqu'à arrêt).
run_services() {
  export LINKUP_AGENT_PUBLIC="$AGENT/public"
  export LINKUP_DASHBOARD_OUT="$APP_DIR/dashboard-out"
  export LINKUP_HTTP_PORT="$PORT"
  export LINKUP_BRIDGE_HOST="0.0.0.0"
  export LINKUP_BRIDGE_PORT="${LINKUP_BRIDGE_PORT:-8765}"
  export LINKUP_BRIDGE_AGENT_TOKEN="$(grep '^LINKUP_BRIDGE_AGENT_TOKEN=' "$AGENT/.env" | cut -d= -f2-)"
  export LINKUP_BRIDGE_TRANSFERS_DIR="${LINKUP_BRIDGE_TRANSFERS_DIR:-$HOME/Linkup/Transfert}"
  mkdir -p "$HOME/Linkup/Transfert" "$HOME/Linkup/Outbox"

  "$APP_DIR/linkup-bridge" >/dev/null 2>&1 &
  local bridge=$!
  "$APP_DIR/frankenphp" run --config "$APP_DIR/Caddyfile" >/dev/null 2>&1 &
  local franken=$!
  trap 'kill "$bridge" "$franken" 2>/dev/null || true' EXIT INT TERM
  log "hub démarré (bridge=$bridge frankenphp=$franken)"
  wait
}

MODE="${1:---open}"

case "$MODE" in
  --serve)
    integrate_appimage
    # Déjà en route ailleurs ? On ne double pas (évite le conflit de port).
    if health; then log "déjà démarré, --serve no-op"; exit 0; fi
    ensure_init
    place_desktop_icon
    run_services
    ;;

  --open|*)
    integrate_appimage
    place_desktop_icon
    if ! health; then
      # Démarre le hub DÉTACHÉ (survit à la fermeture de ce process), puis attend.
      # En AppImage, on relance via $APPIMAGE : son montage squashfs est éphémère,
      # donc le service doit avoir SON propre process (et donc son propre montage).
      ensure_init
      if [ -n "${APPIMAGE:-}" ]; then
        setsid "$APPIMAGE" --serve </dev/null >/dev/null 2>&1 &
      else
        setsid "$APP_DIR/bin/linkup" --serve </dev/null >/dev/null 2>&1 &
      fi
      for _ in $(seq 1 60); do health && break; sleep 0.25; done
    fi
    open_dashboard
    ;;
esac
