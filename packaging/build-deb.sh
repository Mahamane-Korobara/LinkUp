#!/usr/bin/env bash
# Construit le paquet .deb Linkup.
#
# dpkg attend un dossier `debian/` à la racine des sources : ce script le met en
# place temporairement (depuis packaging/debian), lance la construction, puis
# nettoie. À lancer depuis la racine du dépôt.
#
# Prérequis : dpkg-dev debhelper composer php-cli python3-venv nodejs npm
#   sudo apt install -y dpkg-dev debhelper
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -e debian ]; then
  echo "Erreur : un dossier ./debian existe déjà. Retire-le avant de builder." >&2
  exit 1
fi

cleanup() { rm -rf "$ROOT/debian"; }
trap cleanup EXIT

cp -a packaging/debian "$ROOT/debian"
chmod +x debian/rules debian/postinst debian/postrm

echo ">> dpkg-buildpackage (binaire, non signé)…"
dpkg-buildpackage -b -us -uc

echo ">> Paquet produit dans le dossier parent :"
ls -1 ../linkup_*.deb 2>/dev/null || true
