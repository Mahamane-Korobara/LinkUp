#!/usr/bin/env bash
# =============================================================================
# Linkup — installeur Linux (S6.5.J1 / T6.5.1)
#
# Installe Linkup (agent Laravel + bridge Python + dashboard Next.js) sous
# /opt/linkup et le lance via des services systemd UTILISATEUR (le bridge doit
# être dans la session graphique pour le presse-papier Wayland/X11).
#
# Cibles testées (DoD) : Ubuntu 24.04, Debian 12. Gère apt/dnf/pacman/zypper.
#
# Usage :
#   bash infra/install-linux.sh            # installe depuis ce checkout
#   GIT_URL=https://… bash install-linux.sh  # clone d'abord depuis un dépôt
#
# Ne PAS lancer en root : le script appelle `sudo` uniquement pour installer les
# paquets système et écrire dans /opt. Les services tournent en `--user`.
# =============================================================================
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/linkup}"
CONFIG_DIR="$HOME/.config/linkup"
UNIT_DIR="$HOME/.config/systemd/user"
GIT_URL="${GIT_URL:-}"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!  \033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗  %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Ne lance pas ce script en root : il utilise sudo au besoin."

# ----------------------------------------------------------------------------
# 1. Dépendances système (selon le gestionnaire de paquets)
# ----------------------------------------------------------------------------
install_deps() {
  log "Installation des dépendances système…"
  local clip="wl-clipboard"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y \
      php-cli php-mbstring php-xml php-curl php-sqlite3 php-bcmath php-sodium \
      composer python3 python3-venv python3-pip nodejs npm \
      xdg-utils rsync openssl "$clip" || die "apt : installation échouée."
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y \
      php-cli php-mbstring php-xml php-pdo php-sodium php-bcmath composer \
      python3 python3-pip nodejs npm xdg-utils rsync openssl "$clip" \
      || die "dnf : installation échouée."
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --needed --noconfirm \
      php composer python nodejs npm xdg-utils rsync openssl "$clip" \
      || die "pacman : installation échouée."
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y \
      php-cli php-sodium composer python3 nodejs npm xdg-utils rsync openssl "$clip" \
      || die "zypper : installation échouée."
  else
    die "Gestionnaire de paquets non reconnu. Installe à la main : php, composer, python3, nodejs, npm, xdg-utils, wl-clipboard|xclip|xsel."
  fi
}

# ----------------------------------------------------------------------------
# 2. Récupération des sources sous /opt/linkup
# ----------------------------------------------------------------------------
fetch_sources() {
  log "Déploiement des sources dans $INSTALL_DIR…"
  sudo mkdir -p "$INSTALL_DIR"
  sudo chown "$USER":"$USER" "$INSTALL_DIR"
  if [ -n "$GIT_URL" ]; then
    if [ -d "$INSTALL_DIR/.git" ]; then
      git -C "$INSTALL_DIR" pull --ff-only
    else
      git clone --depth 1 "$GIT_URL" "$INSTALL_DIR"
    fi
  else
    # Copie depuis le checkout courant (dossier parent de infra/).
    local src
    src="$(cd "$(dirname "$0")/.." && pwd)"
    rsync -a --delete \
      --exclude '.git' --exclude 'node_modules' --exclude 'vendor' \
      --exclude '.venv' --exclude '.next' --exclude 'agent/storage/logs/*' \
      "$src"/ "$INSTALL_DIR"/
  fi
}

# ----------------------------------------------------------------------------
# 3. Build des 3 composants
# ----------------------------------------------------------------------------
build_all() {
  log "Build agent (composer --no-dev)…"
  (cd "$INSTALL_DIR/agent" && composer install --no-dev --optimize-autoloader --no-interaction)

  log "Build bridge (venv Python)…"
  python3 -m venv "$INSTALL_DIR/bridge/.venv"
  "$INSTALL_DIR/bridge/.venv/bin/pip" install --quiet --upgrade pip
  "$INSTALL_DIR/bridge/.venv/bin/pip" install --quiet "$INSTALL_DIR/bridge"

  log "Build dashboard (Next.js standalone)…"
  (cd "$INSTALL_DIR/dashboard" && npm ci && npm run build)
  # Le mode standalone ne copie pas les assets statiques : on le fait à la main
  # (sinon CSS/JS/images 404 derrière server.js).
  cp -r "$INSTALL_DIR/dashboard/.next/static" "$INSTALL_DIR/dashboard/.next/standalone/.next/static"
  [ -d "$INSTALL_DIR/dashboard/public" ] && \
    cp -r "$INSTALL_DIR/dashboard/public" "$INSTALL_DIR/dashboard/.next/standalone/public" || true
}

# ----------------------------------------------------------------------------
# 4. Configuration : clés, token partagé, base, dossiers
# ----------------------------------------------------------------------------
configure() {
  log "Configuration (clés, token agent↔bridge, base SQLite)…"
  mkdir -p "$CONFIG_DIR" "$HOME/Linkup/Inbox" "$HOME/Linkup/Outbox"

  local token
  token="$(openssl rand -hex 32)"

  # --- agent .env ---
  local env="$INSTALL_DIR/agent/.env"
  [ -f "$env" ] || cp "$INSTALL_DIR/agent/.env.example" "$env" 2>/dev/null || : >"$env"
  set_env() { # set_env KEY VALUE  (remplace ou ajoute dans .env)
    local k="$1" v="$2"
    if grep -q "^${k}=" "$env"; then
      sed -i "s|^${k}=.*|${k}=${v}|" "$env"
    else
      printf '%s=%s\n' "$k" "$v" >>"$env"
    fi
  }
  set_env APP_ENV production
  set_env DB_CONNECTION sqlite
  set_env LINKUP_BRIDGE_AGENT_TOKEN "$token"
  set_env LINKUP_INBOX_DIR "$HOME/Linkup/Inbox"
  set_env LINKUP_OUTBOX_DIR "$HOME/Linkup/Outbox"

  touch "$INSTALL_DIR/agent/database/database.sqlite"
  (cd "$INSTALL_DIR/agent" && php artisan key:generate --force && php artisan migrate --force)

  # --- env partagés pour les services (référencés par les units) ---
  cat >"$CONFIG_DIR/bridge.env" <<EOF
LINKUP_BRIDGE_AGENT_TOKEN=$token
LINKUP_BRIDGE_TRANSFERS_DIR=$HOME/Linkup/Inbox
EOF
  cat >"$CONFIG_DIR/agent.env" <<EOF
LINKUP_BRIDGE_AGENT_TOKEN=$token
EOF
  chmod 600 "$CONFIG_DIR"/*.env
}

# ----------------------------------------------------------------------------
# 5. Services systemd utilisateur
# ----------------------------------------------------------------------------
install_services() {
  log "Installation des services systemd utilisateur…"
  mkdir -p "$UNIT_DIR"

  cat >"$UNIT_DIR/linkup-bridge.service" <<EOF
[Unit]
Description=Linkup bridge — accès OS (presse-papier, fichiers, liens)
After=graphical-session.target
PartOf=graphical-session.target
[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR/bridge
ExecStart=$INSTALL_DIR/bridge/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8765
EnvironmentFile=-$CONFIG_DIR/bridge.env
Restart=on-failure
RestartSec=2
[Install]
WantedBy=default.target
EOF

  cat >"$UNIT_DIR/linkup-agent.service" <<EOF
[Unit]
Description=Linkup agent — API/état (Laravel)
After=network.target linkup-bridge.service
Wants=linkup-bridge.service
[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR/agent
# post/upload_max_filesize relevés : l'envoi PC→tél poste le fichier en multipart.
ExecStart=/usr/bin/php -d post_max_size=256M -d upload_max_filesize=256M artisan serve --host=0.0.0.0 --port=8000
EnvironmentFile=-$CONFIG_DIR/agent.env
Restart=on-failure
RestartSec=2
[Install]
WantedBy=default.target
EOF

  cat >"$UNIT_DIR/linkup-reverb.service" <<EOF
[Unit]
Description=Linkup reverb — temps réel (WebSocket Laravel)
After=network.target
[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR/agent
ExecStart=/usr/bin/php artisan reverb:start --host=0.0.0.0 --port=8080
Restart=on-failure
RestartSec=2
[Install]
WantedBy=default.target
EOF

  cat >"$UNIT_DIR/linkup-dashboard.service" <<EOF
[Unit]
Description=Linkup dashboard — UI locale (Next.js)
After=network.target linkup-agent.service
Wants=linkup-agent.service
[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR/dashboard
ExecStart=/usr/bin/node $INSTALL_DIR/dashboard/.next/standalone/server.js
Environment=PORT=3000
Environment=HOSTNAME=127.0.0.1
Restart=on-failure
RestartSec=2
[Install]
WantedBy=default.target
EOF

  # Linger : les services démarrent au boot, sans ouverture de session.
  loginctl enable-linger "$USER" >/dev/null 2>&1 || warn "enable-linger indisponible (services au prochain login)."

  systemctl --user daemon-reload
  systemctl --user enable --now \
    linkup-bridge.service linkup-agent.service linkup-reverb.service linkup-dashboard.service
}

main() {
  install_deps
  fetch_sources
  build_all
  configure
  install_services
  log "Installé ✓  →  Dashboard : http://localhost:3000"
  log "État des services : systemctl --user status 'linkup-*'"
}

main "$@"
