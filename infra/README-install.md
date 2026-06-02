# Installer Linkup sur Linux (alpha v0.5, LAN-only)

`install-linux.sh` installe les 3 composants PC (agent Laravel, bridge Python,
dashboard Next.js) sous `/opt/linkup` et les lance en **services systemd
utilisateur**. Cible : Ubuntu 24.04 / Debian 12 (gère aussi dnf/pacman/zypper).

## Lancer

```bash
# depuis ce dépôt (copie locale) :
bash infra/install-linux.sh

# ou depuis un dépôt distant :
GIT_URL=https://github.com/…/linkup.git bash install-linux.sh
```

Ne PAS lancer en root : le script appelle `sudo` seulement pour installer les
paquets système et écrire dans `/opt`. Les services tournent en `--user` (le
bridge doit être dans la session graphique pour le presse-papier Wayland/X11).

## Ce qu'il fait

1. Dépendances système (php + extensions, composer, python3, nodejs, npm,
   xdg-utils, **wl-clipboard | xclip | xsel**).
2. Sources → `/opt/linkup` (copie locale ou `git clone`).
3. Build : `composer --no-dev`, venv Python, `next build` standalone (+ copie des
   assets statiques).
4. Config : `APP_KEY`, base SQLite migrée, **token partagé agent↔bridge**
   (`openssl rand`), dossiers `~/Linkup/{Inbox,Outbox}`, env dans
   `~/.config/linkup/`.
5. Services `linkup-{bridge,agent,reverb,dashboard}` activés + `enable-linger`
   (démarrage au boot). UI : http://localhost:3000.

## Gérer les services

```bash
systemctl --user status 'linkup-*'
systemctl --user restart linkup-agent
journalctl --user -u linkup-bridge -f
```

## Statut (S6.5.J1)

- [x] Script écrit, syntaxe validée (`bash -n`).
- [ ] **T6.5.2** — testé sur VM **Ubuntu 24.04** fraîche.
- [ ] **T6.5.3** — testé sur VM **Debian 12** fraîche.

> Non encore exécuté de bout en bout : à valider sur VM propre (étapes T6.5.2/3
> du plan). Points à surveiller : extensions PHP selon distro, `php artisan
> reverb:start` (config Reverb/.env), accès session graphique du bridge.

Alternative : un scaffold `.deb` existe sous `packaging/` (plus natif Debian/
Ubuntu mais exige `debhelper`). Ce script `.sh` est plus portable.
