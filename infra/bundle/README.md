# Bundle Linkup — runtimes embarqués (zéro installation système)

Stratégie packaging retenue : **bundler les runtimes** plutôt qu'installer des
paquets système (évite les conflits type php7.1/sury, et l'utilisateur lambda ne
fait que **décompresser + double-clic**). Tout le PC tient en **2 binaires**.

```
linkup-linux/
├── frankenphp        # agent Laravel (/api/*) + sert le dashboard — PHP embarqué
├── linkup-bridge     # presse-papier / ouvrir / mDNS — Python embarqué
├── Caddyfile         # route : /api → PHP, le reste → dashboard statique
├── linkup-run.sh     # lanceur (1er run : APP_KEY + token + SQLite)
├── agent/            # app Laravel + vendor (sans dev)
└── dashboard-out/    # export statique Next (HTML/JS)
```

Aucun PHP / Python / Node / MySQL à installer sur la machine cible.

## Construire (machine de dev)

```bash
infra/bundle/build-bundle-linux.sh        # → dist/linkup-linux.tar.gz
```

Prérequis de **build** uniquement : composer, node/npm, python3-venv, pyinstaller,
curl. La machine **cible** n'a besoin de rien.

## Utiliser (machine cible)

```bash
tar xzf linkup-linux.tar.gz
./linkup-linux/linkup-run.sh      # → http://localhost:8000
```

## Validé (2026-06-02, sur cette machine)

- [x] dashboard → export statique (`out/`, 9 pages, 1,4 Mo, zéro Node).
- [x] bridge → binaire PyInstaller 25 Mo : démarre seul, `/health` 200 (sans Python).
- [x] FrankenPHP fait tourner l'agent : `/api/health` 200, extensions OK
      (sodium, pdo_sqlite, mbstring, …) sous PHP 8.5.
- [x] un seul FrankenPHP sert **dashboard** (`/`, `/devices`, assets `_next`) **et**
      **API** (`/api/health`) via le Caddyfile.

## Reste à faire

- [ ] Lancer `build-bundle-linux.sh` de bout en bout + tester `linkup-run.sh` sur
      une machine **propre** (le 1er-run init key/migrate n'a pas encore été
      éprouvé end-to-end).
- [ ] Note PHP 8.5 : Laravel 12 cible 8.2–8.4 ; surveiller les dépréciations (au
      besoin, épingler une release FrankenPHP en PHP 8.4).
- [ ] Équivalent **Windows** (`frankenphp.exe` + `linkup-bridge.exe` PyInstaller +
      un `.bat`/lanceur), puis installeur double-clic.
- [ ] mDNS : vérifier que le bridge annonce bien le service depuis le binaire gelé.
