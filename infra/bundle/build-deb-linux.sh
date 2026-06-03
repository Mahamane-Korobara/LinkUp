#!/usr/bin/env bash
# Construit le .deb Linkup AUTONOME (runtimes embarqués : frankenphp + bridge
# PyInstaller). Aucune dépendance php/python/node système — contrairement à
# l'ancien packaging/debian (apt, abandonné).
#
# Réutilise le bundle assemblé par build-bundle-linux.sh (dist/linkup-linux/) :
# le lance d'abord s'il manque. Produit dist/linkup-pc.deb.
#
# Prérequis : dpkg-deb (dpkg), convert (ImageMagick). Build du bundle : composer,
# pnpm, pyinstaller, curl.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE="$ROOT/dist/linkup-linux"
DEB_SRC="$ROOT/infra/deb"
ICON_SRC="$ROOT/infra/assets/linkup-512.png"
VERSION="${LINKUP_VERSION:-0.6.0}"
STAGE="$ROOT/dist/deb-stage"
OUT_DEB="$ROOT/dist/linkup-pc.deb"

# 1) S'assurer que le bundle existe (sinon on le construit).
if [ ! -x "$BUNDLE/frankenphp" ] || [ ! -x "$BUNDLE/linkup-bridge" ]; then
  echo "==> Bundle absent — construction via build-bundle-linux.sh"
  "$ROOT/infra/bundle/build-bundle-linux.sh"
fi

echo "==> Staging $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE/opt/linkup/bin" \
         "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/icons/hicolor/512x512/apps" \
         "$STAGE/usr/share/icons/hicolor/256x256/apps" \
         "$STAGE/usr/share/icons/hicolor/128x128/apps" \
         "$STAGE/DEBIAN"

# 2) App (lecture seule) sous /opt/linkup.
cp -a "$BUNDLE/frankenphp" "$BUNDLE/linkup-bridge" "$BUNDLE/Caddyfile" "$STAGE/opt/linkup/"
cp -a "$BUNDLE/agent" "$STAGE/opt/linkup/agent"
cp -a "$BUNDLE/dashboard-out" "$STAGE/opt/linkup/dashboard-out"
install -m 0755 "$DEB_SRC/linkup-launch.sh" "$STAGE/opt/linkup/bin/linkup"
# Pas d'état pré-généré embarqué (clé/SQLite sont créés par utilisateur au 1er run).
rm -f "$STAGE/opt/linkup/agent/.env" "$STAGE/opt/linkup/agent/.initialized" \
      "$STAGE/opt/linkup/agent/database/database.sqlite" 2>/dev/null || true

# 3) Lanceur menu/bureau + icônes (déclinées du 512 de marque).
install -m 0644 "$DEB_SRC/linkup.desktop" "$STAGE/usr/share/applications/linkup.desktop"
install -m 0644 "$ICON_SRC" "$STAGE/usr/share/icons/hicolor/512x512/apps/linkup.png"
convert "$ICON_SRC" -resize 256x256 "$STAGE/usr/share/icons/hicolor/256x256/apps/linkup.png"
convert "$ICON_SRC" -resize 128x128 "$STAGE/usr/share/icons/hicolor/128x128/apps/linkup.png"

# 4) Métadonnées DEBIAN.
INSTALLED_KB="$(du -sk "$STAGE/opt" "$STAGE/usr" | awk '{s+=$1} END{print s}')"
cat >"$STAGE/DEBIAN/control" <<EOF
Package: linkup
Version: $VERSION
Section: net
Priority: optional
Architecture: amd64
Maintainer: Linkup <korobaramahamane311@gmail.com>
Installed-Size: $INSTALLED_KB
Depends: xdg-utils, libfontconfig1, wl-clipboard | xclip | xsel
Recommends: x11-utils
Description: Hub multi-appareils Linkup (téléphone <-> PC) sur le LAN
 Linkup relie un téléphone Android et ce PC sur le réseau local : transfert de
 fichiers (galerie + documents), presse-papier partagé, ouverture de liens.
 .
 Paquet AUTONOME : l'agent (PHP via FrankenPHP), le bridge (Python figé) et le
 dashboard sont embarqués. Rien d'autre à installer. Lance « Linkup » depuis le
 menu : le dashboard s'ouvre sur http://localhost:8000.
EOF
install -m 0755 "$DEB_SRC/postinst" "$STAGE/DEBIAN/postinst"
install -m 0755 "$DEB_SRC/postrm" "$STAGE/DEBIAN/postrm"

# 5) Construction (propriétaires root, comme attendu pour /opt et /usr).
echo "==> dpkg-deb --build"
dpkg-deb --root-owner-group --build "$STAGE" "$OUT_DEB"
echo "✓ Paquet : $OUT_DEB"
dpkg-deb --info "$OUT_DEB" | sed -n '1,20p'
