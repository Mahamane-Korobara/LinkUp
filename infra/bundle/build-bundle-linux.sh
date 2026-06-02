#!/usr/bin/env bash
# Assemble le bundle Linkup pour Linux : un dossier autonome (puis .tar.gz) que
# l'utilisateur décompresse et lance via ./linkup-run.sh — SANS rien installer.
#
# Contenu produit (dist/linkup-linux/) :
#   frankenphp        (agent Laravel + dashboard, PHP embarqué)
#   linkup-bridge     (accès OS, Python embarqué)
#   Caddyfile, linkup-run.sh
#   agent/            (app Laravel + vendor, sans dev)
#   dashboard-out/    (export statique Next)
#
# Prérequis BUILD (sur la machine de build seulement) : composer, node/npm,
# python3-venv, pyinstaller, curl. La machine CIBLE n'a besoin de rien.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/dist/linkup-linux"
FRANKEN_URL="https://github.com/php/frankenphp/releases/latest/download/frankenphp-linux-x86_64"

echo "==> Nettoyage"; rm -rf "$OUT"; mkdir -p "$OUT"

echo "==> Agent : composer --no-dev"
(cd "$ROOT/agent" && composer install --no-dev --optimize-autoloader --no-interaction)

echo "==> Dashboard : export statique"
(cd "$ROOT/dashboard" && npm ci && npm run build)

echo "==> Bridge : binaire PyInstaller"
(cd "$ROOT/bridge" && [ -x .venv/bin/python ] || python3 -m venv .venv; \
  .venv/bin/pip install -q . pyinstaller; ./build-binary.sh)

echo "==> FrankenPHP"
curl -sSL -o "$OUT/frankenphp" "$FRANKEN_URL"; chmod +x "$OUT/frankenphp"

echo "==> Assemblage"
cp "$ROOT/bridge/dist/linkup-bridge" "$OUT/"
cp "$ROOT/infra/bundle/Caddyfile" "$ROOT/infra/bundle/linkup-run.sh" "$OUT/"
chmod +x "$OUT/linkup-run.sh"
# Agent (app + vendor), sans le superflu de dev.
rsync -a --delete \
  --exclude '.git' --exclude 'tests' --exclude 'node_modules' \
  --exclude 'storage/logs/*' --exclude '.env' --exclude 'database/database.sqlite' \
  "$ROOT/agent/" "$OUT/agent/"
mkdir -p "$OUT/agent/database"
cp -r "$ROOT/dashboard/out" "$OUT/dashboard-out"

echo "==> Archive"
tar -C "$ROOT/dist" -czf "$ROOT/dist/linkup-linux.tar.gz" linkup-linux
echo "✓ Bundle : $ROOT/dist/linkup-linux.tar.gz"
echo "  Test : tar xzf linkup-linux.tar.gz && ./linkup-linux/linkup-run.sh"
