#!/usr/bin/env bash
# Construit l'AppImage Linkup : UN seul fichier, AUCUNE installation, marche sur
# toutes les distros. Au 1er lancement il s'auto-intègre (menu + bureau +
# autostart pointant sur lui-même) et ouvre le dashboard.
#
# Réutilise le bundle (dist/linkup-linux/) et le MÊME lanceur que le .deb
# (infra/deb/linkup-launch.sh). Produit dist/Linkup-x86_64.AppImage.
#
# Prérequis : curl (pour appimagetool), FUSE pour exécuter l'AppImage produite.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE="$ROOT/dist/linkup-linux"
APPSRC="$ROOT/infra/appimage"
DEB_SRC="$ROOT/infra/deb"
ICON="$ROOT/dashboard/public/icons/icon-512.png"
APPDIR="$ROOT/dist/Linkup.AppDir"
OUT="$ROOT/dist/Linkup-x86_64.AppImage"
TOOL="$ROOT/dist/appimagetool-x86_64.AppImage"

# 1) Bundle requis.
if [ ! -x "$BUNDLE/frankenphp" ] || [ ! -x "$BUNDLE/linkup-bridge" ]; then
  echo "==> Bundle absent — construction"; "$ROOT/infra/bundle/build-bundle-linux.sh"
fi

echo "==> AppDir $APPDIR"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/lib/linkup/bin" "$APPDIR/usr/share/icons/hicolor/512x512/apps"

# 2) Payload app (même layout que /opt/linkup → lanceur réutilisé tel quel).
cp -a "$BUNDLE/frankenphp" "$BUNDLE/linkup-bridge" "$BUNDLE/Caddyfile" "$APPDIR/usr/lib/linkup/"
cp -a "$BUNDLE/agent" "$APPDIR/usr/lib/linkup/agent"
cp -a "$BUNDLE/dashboard-out" "$APPDIR/usr/lib/linkup/dashboard-out"
install -m 0755 "$DEB_SRC/linkup-launch.sh" "$APPDIR/usr/lib/linkup/bin/linkup"
install -m 0644 "$ICON" "$APPDIR/usr/lib/linkup/linkup.png"   # source d'icône pour l'auto-intégration
rm -f "$APPDIR/usr/lib/linkup/agent/.env" \
      "$APPDIR/usr/lib/linkup/agent/database/database.sqlite" 2>/dev/null || true

# 3) Métadonnées AppDir (AppRun + .desktop + icône top-level requis par appimagetool).
install -m 0755 "$APPSRC/AppRun" "$APPDIR/AppRun"
install -m 0644 "$APPSRC/linkup.desktop" "$APPDIR/linkup.desktop"
install -m 0644 "$ICON" "$APPDIR/linkup.png"
install -m 0644 "$ICON" "$APPDIR/usr/share/icons/hicolor/512x512/apps/linkup.png"

# 4) appimagetool (téléchargé une fois).
if [ ! -x "$TOOL" ]; then
  echo "==> Téléchargement appimagetool"
  curl -fsSL -o "$TOOL" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$TOOL"
fi

echo "==> appimagetool"
rm -f "$OUT"
ARCH=x86_64 "$TOOL" "$APPDIR" "$OUT" 2>&1 | tail -8 || \
  ARCH=x86_64 "$TOOL" --appimage-extract-and-run "$APPDIR" "$OUT" 2>&1 | tail -8

chmod +x "$OUT"
echo "✓ AppImage : $OUT"
ls -lh "$OUT"
