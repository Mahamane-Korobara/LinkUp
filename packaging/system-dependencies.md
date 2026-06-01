# Dépendances système Linkup — pour les installeurs (S6.5)

Le bridge Python et l'agent Laravel **shell-out** vers des outils de l'OS pour
toucher le système (presse-papier, ouverture de fichier/lien, mDNS). Les
installeurs **doivent garantir leur présence** pour que l'utilisateur final
n'ait **rien** à installer à la main.

> Statut : le bridge gère déjà proprement l'absence d'outil (erreur explicite,
> pas de crash). Ce document est la **référence de packaging** pour S6.5 — rien
> n'est encore branché dans un installeur (les installeurs n'existent pas).

## Récapitulatif

| Fonction | Linux | Windows | macOS (hors cible) |
|---|---|---|---|
| Ouvrir fichier / lien | `xdg-utils` (`xdg-open`) | intégré (`start`) | intégré (`open`) |
| Presse-papier | `wl-clipboard` \| `xclip` \| `xsel` | intégré (`clip` + PowerShell) | intégré (`pbcopy`/`pbpaste`) |
| Découverte mDNS | `libnss-mdns` / avahi (souvent présent) | Bonjour (souvent présent) | intégré |

**Cibles officielles : Linux + Windows.** Windows n'a besoin d'**aucune**
dépendance externe (tout est intégré à Windows 10/11).

## Linux — paquet `.deb` (Debian / Ubuntu)

Dans `debian/control` :

```
Depends: ${shlibs:Depends}, ${misc:Depends},
         xdg-utils,
         wl-clipboard | xclip | xsel
```

`apt` installe automatiquement l'alternative manquante à l'installation de Linkup.

## Linux — paquet `.rpm` (Fedora / RHEL)

```
Requires: xdg-utils
Requires: (wl-clipboard or xclip or xsel)
```

## Linux — installeur `.sh` (fallback universel)

Snippet à intégrer (détection distro + install si manquant) :

```sh
has_clipboard() {
  command -v wl-copy >/dev/null 2>&1 \
    || command -v xclip >/dev/null 2>&1 \
    || command -v xsel  >/dev/null 2>&1
}

if ! has_clipboard || ! command -v xdg-open >/dev/null 2>&1; then
  if   command -v apt-get >/dev/null 2>&1; then sudo apt-get install -y wl-clipboard xdg-utils
  elif command -v dnf     >/dev/null 2>&1; then sudo dnf install -y wl-clipboard xdg-utils
  elif command -v pacman  >/dev/null 2>&1; then sudo pacman -S --needed --noconfirm wl-clipboard xdg-utils
  elif command -v zypper  >/dev/null 2>&1; then sudo zypper install -y wl-clipboard xdg-utils
  else echo "⚠️  Installe manuellement : wl-clipboard (ou xclip) + xdg-utils"; fi
fi
```

> Sur une session **X11** plutôt que Wayland, `xclip`/`xsel` suffisent ; on
> installe `wl-clipboard` par défaut car les distros récentes sont en Wayland.

## Windows

**Rien à installer** : `clip`, `powershell Get-Clipboard` et `start` sont
intégrés à Windows 10/11. L'installeur `.exe`/MSIX n'a aucune dépendance système
à déclarer pour ces fonctions.

## macOS (hors cible alpha, pour mémoire)

`pbcopy`/`pbpaste`/`open` intégrés → rien à installer.

---

Voir aussi : `bridge/README.md` (section « Dépendances système ») et la mémoire
projet `linkup-clipboard-autosync` (contrainte Android + plan auto-sync).
