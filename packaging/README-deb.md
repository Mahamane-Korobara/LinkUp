# Paquet `.deb` Linkup (scaffold)

Empaquette les 3 composants PC — **agent** (Laravel), **bridge** (Python),
**dashboard** (Next.js) — dans un seul `.deb`, avec services systemd et
**dépendances tirées automatiquement** (dont le presse-papier). But : l'utilisateur
final installe **une** chose et n'a **rien** à installer à la main.

## Construire

```bash
sudo apt install -y dpkg-dev debhelper composer php-cli python3-venv nodejs npm
./packaging/build-deb.sh        # depuis la racine du dépôt
# → ../linkup_0.5.0-1_all.deb
```

`build-deb.sh` met `packaging/debian/` à la racine le temps du build (dpkg
l'attend en `./debian`), lance `dpkg-buildpackage -b`, puis nettoie.

## Installer / désinstaller

```bash
sudo apt install ./linkup_0.5.0-1_all.deb   # tire php-*, python3, nodejs,
                                            # xdg-utils, wl-clipboard|xclip|xsel
# Démarrer tout de suite (sinon au prochain login) :
systemctl --user start linkup-bridge linkup-agent linkup-dashboard
# UI : http://localhost:3000
```

## Choix de conception

- **Services utilisateur** (`systemctl --user`), pas système : le bridge doit être
  dans la session graphique pour accéder au presse-papier Wayland/X11 (cf.
  `system-dependencies.md`). Le postinst fait `systemctl --global enable`.
- **Dépendances presse-papier** déclarées en `Depends: … wl-clipboard | xclip |
  xsel` → apt installe l'alternative manquante. Windows n'a besoin de rien.
- **Bridge** : venv embarqué (`pip install ./bridge`, via `pyproject.toml`).
- **Dashboard** : build Next.js `output: standalone` → `node server.js` sans npm
  sur la machine cible.
- **Agent** : `php artisan serve --host=0.0.0.0` (suffisant pour l'alpha LAN ;
  une vraie prod = php-fpm + nginx, hors périmètre v0.5).

## Statut — ce qui reste

> C'est un **scaffold** : la structure, les dépendances et les services sont en
> place et cohérents, mais le pipeline n'a pas encore été exécuté de bout en bout
> sur cette machine (build lourd : composer + pip + next build).

- [ ] Lancer `build-deb.sh` sur une machine propre et corriger les extensions PHP
      manquantes éventuelles (Laravel est exigeant).
- [ ] Générer/poser `~/.config/linkup/{agent,bridge}.env` au 1ᵉʳ démarrage
      (token partagé agent↔bridge, `LINKUP_HOME_DIR`) — aujourd'hui à la main.
- [ ] `Architecture: all` à revoir si `node_modules` embarque du natif → passer
      en arch-dépendant (`amd64`/`arm64`).
- [ ] Équivalents `.rpm` (Fedora) et installeur Windows (`.msi`).
