# 🗺️ Linkup — Plan d'Exécution Détaillé
### *Du jour 1 à la soutenance — 25 semaines, 9 briques, ~16 modules*

| | |
|---|---|
| **Projet** | Linkup v2.0 — Hub Cross-Device |
| **CDC référent** | `Linkup-CDC-v2_0.md` |
| **Auteur** | Mahamane Korobara |
| **Stack** | Laravel 12 + Python 3 (FastAPI) + Flutter 3 (Android) + Next.js 15 |
| **Cibles** | Android 8.0+ • Windows 10/11 • Linux (Ubuntu/Debian/Fedora) |
| **Durée totale** | 25 semaines (≈ 6 mois) + W0 préparation |
| **Cadence** | 5 jours/semaine, 6-8h/jour effectifs (solo dev) |
| **Date début prévue** | À fixer — premier lundi disponible |

---

## 📐 Conventions du plan

- **Tx.y** = Tâche y de la semaine x (ex. T3.4 = 4e tâche de la semaine 3)
- **DoD** = Definition of Done (critères de complétion mesurables)
- **🔴 Bloquant** = doit être livré avant la semaine suivante, sinon glissement
- **🟠 Important** = peut glisser de 1-2 jours sans impact majeur
- **🟢 Best-effort** = polish, peut être repoussé si temps manque
- **🧪** = tâche de test (Pest, pytest, flutter_test, integration)
- **📝** = documentation
- **🔧** = config/infra

Chaque semaine est structurée en :
1. **Objectif** (1 ligne)
2. **Sortie attendue** (livrable concret)
3. **Tâches jour-par-jour** (Lun-Ven)
4. **Tests à écrire**
5. **Definition of Done**

---

# 📦 W0 — Préparation (1 semaine offert au projet)

**🎯 Objectif :** environnement de dev opérationnel sur les 2 OS cibles + monorepo initialisé + outillage CI prêt.

**📤 Sortie attendue :** repo Git poussé sur GitHub avec scaffolds vides + CI verte sur 4 jobs (PHP / Python / Flutter / Next.js).

## W0.J1 — Setup machine principale (Linux Ubuntu 24.04)
- T0.1 🔧 Installer PHP 8.4 + extensions (`php-sodium`, `php-sqlite`, `php-mbstring`, `php-zip`, `php-curl`)
- T0.2 🔧 Installer Composer + Laravel installer (`composer global require laravel/installer`)
- T0.3 🔧 Installer Python 3.11+ + `pip` + `pipenv` ou `poetry`
- T0.4 🔧 Installer Flutter 3 + Android Studio + SDK Android 34
- T0.5 🔧 Installer Node 22 + pnpm
- T0.6 🔧 Installer Docker + Docker Compose (utile pour Reverb + Sentry locaux)

## W0.J2 — Setup machine secondaire (Windows 11)
- T0.7 🔧 Installer PHP 8.4 Windows (via `php.net` + ajout PATH)
- T0.8 🔧 Installer Python 3.11+ Windows (cocher « Add to PATH »)
- T0.9 🔧 Installer Composer Windows + Git for Windows
- T0.10 🔧 Tester Flutter Windows (juste pour build APK depuis Win optionnel)
- T0.11 🔧 Installer WSL2 Ubuntu (pour tester en miroir le pont Python si besoin)

## W0.J3 — Monorepo + scaffolds vides
- T0.12 🔧 Créer repo GitHub `linkup` (public ou privé, au choix)
- T0.13 🔧 Structure dossiers :
  ```
  linkup/
  ├── agent/        # Laravel 12
  ├── bridge/       # FastAPI Python
  ├── mobile/       # Flutter Android
  ├── dashboard/    # Next.js 15
  ├── docs/         # CDC, plan, ADRs
  ├── infra/        # scripts install, systemd, docker
  └── .github/workflows/
  ```
- T0.14 🔧 `laravel new agent` → commit
- T0.15 🔧 `mkdir bridge && poetry init` + structure `bridge/app/{routes,services,os}` → commit
- T0.16 🔧 `flutter create mobile --org tech.sahelstack.linkup --org-platforms android` → commit
- T0.17 🔧 `pnpm create next-app dashboard` (App Router, TS, Tailwind) → commit

## W0.J4 — Outillage CI/CD GitHub Actions
- T0.18 🔧 Workflow `agent.yml` : PHPStan + Pest stub
- T0.19 🔧 Workflow `bridge.yml` : ruff + pytest stub
- T0.20 🔧 Workflow `mobile.yml` : `flutter analyze` + `flutter test` stub
- T0.21 🔧 Workflow `dashboard.yml` : `pnpm lint` + `pnpm build`
- T0.22 🔧 Activer Dependabot pour les 4 stacks
- T0.23 🔧 Pre-commit hooks (`husky` + `lint-staged` pour le monorepo)

## W0.J5 — VPS + outillage observabilité
- T0.24 🔧 Vérifier accès SSH `sahelstack.tech`
- T0.25 🔧 Installer Nginx + Certbot (Let's Encrypt) sur sous-domaine `linkup.sahelstack.tech`
- T0.26 🔧 Créer projet Sentry (free tier), récupérer DSN agent + dashboard + mobile
- T0.27 📝 Rédiger ADR-001 « Stack choisie et raisons » dans `docs/adr/`
- T0.28 📝 README initial du monorepo avec instructions setup

**🧪 DoD W0 :**
- [ ] 4 CI vertes
- [ ] `agent && php artisan serve` répond
- [ ] `bridge && poetry run uvicorn app.main:app` répond `/health`
- [ ] `mobile && flutter run` affiche écran d'accueil sur émulateur
- [ ] `dashboard && pnpm dev` affiche page d'accueil

---

# 🏗️ BRIQUE 1 — Noyau & Pairing (S1 → S3 • 3 semaines)

**🎯 Objectif global :** Tel et PC appairés en moins de 5 secondes avec approbation côté PC, reconnexion auto, base de données complète, sécurité crypto en place.

## S1 — Reverb + mDNS + FastAPI health

**🎯 Objectif :** Les 3 briques démarrent, se découvrent sur le LAN, échangent un ping signé.

**📤 Sortie :** L'app Flutter détecte un agent PC via mDNS, affiche son nom et son empreinte.

### S1.J1 — Laravel + Reverb
- T1.1 🔴 Installer `laravel/reverb` (`composer require laravel/reverb`)
- T1.2 🔴 `php artisan reverb:install` → config Pusher
- T1.3 🔴 Démarrer Reverb (`php artisan reverb:start`) sur port 8080
- T1.4 🔴 Créer event de test `PingEvent` + channel public
- T1.5 🧪 Test Pest : authentification ABILITIES de base

### S1.J2 — FastAPI + structure pont Python
- T1.6 🔴 `bridge/app/main.py` avec FastAPI, endpoint `/health`
- T1.7 🔴 Endpoints stub : `/clipboard/read`, `/clipboard/write`, `/notify`, `/system/info`
- T1.8 🔴 Token Bearer interne (agent Laravel ↔ bridge) — pas exposé extérieur
- T1.9 🧪 pytest : `/health` retourne `200 OK`

### S1.J3 — mDNS Linux + Windows
- T1.10 🔴 Lib `php-zeroconf` ou wrapper Avahi (Linux) / Bonjour (Windows) pour annoncer `_linkup._tcp.local`
- T1.11 🔴 Service `MdnsAnnouncer` Laravel démarré au boot agent
- T1.11bis 🔴 Service Laravel `MdnsAnnouncer` = façade métier sur le bridge local pour `/mdns/info`, `/mdns/services`, `/health`
- T1.12 🔴 Tester depuis un autre PC : `avahi-browse -a` voit l'annonce
- T1.12bis 🔴 Modèle de présence : heartbeat HTTP `/health` toutes les 5 s + `last_seen` + TTL 15 s + purge des agents fantômes
- T1.13 🔴 Fallback : si mDNS échoue, afficher IP+port dans console + page dashboard `/setup`

> Note d'alignement au 24 mai 2026 : l'annonce mDNS bas niveau est actuellement implémentée dans `bridge/app/main.py` via Python Zeroconf. Pour rester fidèle à l'architecture cible, Laravel porte désormais la façade `MdnsAnnouncer` et consomme l'état du bridge au lieu d'exposer directement ce détail au reste du projet.

### S1.J4 — Découverte Flutter
- T1.14 🔴 Lib `multicast_dns` Flutter, scan des `_linkup._tcp`
- T1.15 🔴 Écran « Sélectionner un agent » liste les résultats
- T1.16 🔴 Permission Android : `CHANGE_WIFI_MULTICAST_STATE` + acquire `WifiManager.MulticastLock`
- T1.17 🔴 Saisie manuelle IP en fallback

### S1.J5 — Glue + tests intégration
- T1.18 🔴 Endpoint Laravel `/api/agent/info` retourne nom + empreinte (placeholder)
- T1.19 🔴 Flutter affiche les infos de l'agent après sélection
- T1.20 🧪 Test manuel : 2 PC sur le même Wi-Fi, Flutter découvre les deux
- T1.21 📝 ADR-002 « Choix mDNS Linux/Windows »

**🧪 DoD S1 :**
- [ ] Reverb actif, accepte au moins un client (test avec `curl` + protocole Pusher)
- [ ] FastAPI répond sur `/health` avec uptime + OS + version
- [ ] Annonce mDNS visible depuis un autre device sur le LAN
- [ ] Flutter liste 1+ agent et affiche ses infos

---

## S2 — Pairing QR + Noise IK + approbation PC

**🎯 Objectif :** Pairing crypto sécurisé bout-à-bout.

**📤 Sortie :** Scan QR → handshake → popup d'approbation PC → device approuvé en SQLite → channel Reverb privé créé.

### S2.J1 — Crypto Ed25519 et stockage clés
- T2.1 🔴 Installer `paragonie/sodium_compat` ou utiliser `ext-sodium` natif
- T2.2 🔴 Service `KeyManager` : génère paire Ed25519 au premier lancement, stocke dans `~/.linkup/keys/agent_ed25519.{pub,sec}` chmod 600
- T2.3 🔴 Côté Flutter : `flutter_sodium` ou `cryptography`, génération paire au premier lancement, stockée dans secure storage
- T2.4 🧪 Test : générer 100 paires, aucune collision, charger/sauver round-trip

### S2.J2 — Génération QR + OTP
- T2.5 🔴 Service `PairingService::createOtp()` génère token aléatoire 32 bytes base64, TTL 60s en SQLite table `pairing_otps`
- T2.6 🔴 QR contient `linkup://<ip>:<port>?pk=<base64>&otp=<base64>&v=1`
- T2.7 🔴 Endpoint `/api/pairing/qr.png` génère QR via `endroid/qr-code`
- T2.8 🔴 Dashboard Next.js affiche le QR (page `/pair`) + auto-refresh à expiration
- T2.9 🧪 Pest : OTP réutilisé refusé, OTP expiré refusé

### S2.J3 — Scan QR Flutter + handshake Noise IK
- T2.10 🔴 Écran scan QR Flutter (`mobile_scanner`)
- T2.11 🔴 Parser URL `linkup://` + extraction `pk` + `otp`
- T2.12 🔴 Implémenter Noise IK côté Flutter (lib `dart_noise` ou réimpl minimale sur `flutter_sodium`)
- T2.13 🔴 Connexion WebSocket à `ws://<ip>:<port>/api/pairing/handshake` (endpoint Laravel custom hors Reverb)
- T2.14 🔴 Échange Noise IK : 3 messages, dérivation clé de session XChaCha20-Poly1305

### S2.J4 — Approbation côté PC + persistance
- T2.15 🔴 Post-handshake : Laravel insère dans `devices(name, public_key, fingerprint_sha256, approved=false)`
- T2.16 🔴 Reverb event `PairingPendingApproval` broadcasté au dashboard
- T2.17 🔴 Dashboard `/devices` affiche popup avec empreinte SHA-256 (8 chars), boutons Approuver / Refuser
- T2.18 🔴 Approbation → `approved=true`, émission `DeviceApproved` à l'app Flutter
- T2.19 🔴 Émission token persistant (32 bytes), stocké hashé argon2id dans `device_tokens`

### S2.J5 — Reconnexion auto + tests
- T2.20 🔴 Flutter stocke token + ip + port dans secure storage
- T2.21 🔴 Au lancement, si device connu → reconnexion auto WebSocket avec token
- T2.22 🔴 Channel privé Reverb `private-device.{id}` créé, abonnement Flutter
- T2.23 🧪 Pest : pairing complet, refus avec mauvais OTP, refus avec QR expiré, refus avec clé pub différente
- T2.24 🧪 Test intégration : pairing → kill app → relance → reconnecté < 2s

**🧪 DoD S2 :**
- [ ] Scan QR → connecté + approuvé en < 5s sur 10 essais consécutifs
- [ ] Reconnexion auto fonctionne (kill app + relance)
- [ ] QR expiré, OTP réutilisé, device non approuvé refusés
- [ ] Empreinte SHA-256 affichée côté PC matche celle du tel

---

## S3 — Modèle de données complet + dashboard + audit

**🎯 Objectif :** Toutes les tables du CDC §15 créées, indexées, testées. Dashboard liste tous les devices avec actions.

**📤 Sortie :** Schéma SQLite complet déployé, dashboard `/devices` fonctionnel, `security_audit` actif.

### S3.J1 — Migrations Laravel
- T3.1 🔴 Migrations pour les 15 tables (cf. CDC §15) : devices, device_tokens, sessions, transfers, file_chunks, clipboard_log, links_log, notifications_mirror, terminal_sessions, terminal_commands, gallery_cache, media_jobs, security_audit, module_settings, localhost_tunnels
- T3.2 🔴 Index sur `device_id`, `created_at` partout
- T3.3 🔴 Foreign keys avec `cascade on delete` sur `device_id`
- T3.4 🧪 Pest migrations : up + down fonctionnent

### S3.J2 — Modèles Eloquent + Repositories
- T3.5 🔴 Models : Device, DeviceToken, Session, Transfer, FileChunk, etc.
- T3.6 🔴 Relations Eloquent (`hasMany`, `belongsTo`)
- T3.7 🔴 Repositories : `DeviceRepository`, `SessionRepository`, `SecurityAuditRepository`
- T3.8 🧪 Pest : CRUD basique sur chaque model

### S3.J3 — SecurityAuditService + middleware
- T3.9 🔴 Service `SecurityAuditService::log($event, $device, $payload)`
- T3.10 🔴 Middleware `LogSecurityEvents` qui catch les rejets (token invalide, device non approuvé) et les loggue
- T3.11 🔴 Tous les rejets de S2 doivent passer par ce service
- T3.12 🧪 Pest : un rejet OTP génère bien une entrée audit

### S3.J4 — Dashboard `/devices` enrichi
- T3.13 🔴 Liste des devices : nom, empreinte courte, dernière connexion, transport, statut
- T3.14 🔴 Bouton « Révoquer » : `device.approved = false`, supprime tokens, déconnecte
- T3.15 🔴 Bouton « Renommer », modal édition
- T3.16 🔴 Section `/security` : audit log temps réel via Reverb event `SecurityEvent`

### S3.J5 — Tests sécurité + rotation tokens
- T3.17 🔴 Tâche planifiée : rotation des tokens > 25 jours
- T3.18 🔴 Tâche planifiée : purge `pairing_otps` expirés (toutes les 5 min)
- T3.19 🧪 Pest : token rotation, purge OTP
- T3.20 🧪 Test sécu : 5 scénarios attaquant (rejeu, MITM simulé, token volé, QR doublé, clé pub falsifiée)
- T3.21 📝 ADR-003 « Modèle de données et raisons »

**🧪 DoD S3 :**
- [ ] 15 tables créées, migrations idempotentes
- [ ] Dashboard `/devices` affiche, révoque, renomme
- [ ] `security_audit` reçoit toutes les tentatives rejetées
- [ ] 5 tests d'attaque échouent (= sécurité tient)

**🚦 Gate B1 :** Pairing + audit + reconnexion stables sur 30 essais. **Si fail, +1 semaine avant B2.**

---

# 📤 BRIQUE 2 — Transferts & Clipboard (S4 → S6 • 3 semaines)

**🎯 Objectif global :** 4 modules « fichiers & contenu » fonctionnels avec services Laravel partagés.

## S4 — Transfert de fichiers (chunked + reprise)

**🎯 Objectif :** Envoyer un fichier 500 Mo dans les 2 sens avec reprise après coupure.

### S4.J1 — Endpoint upload chunked FastAPI
- T4.1 🔴 `POST /transfer/upload` : reçoit chunk binaire, vérifie SHA-256 chunk, écrit dans `~/.linkup/transfers/<transfer_id>/chunk_NNNN`
- T4.2 🔴 `HEAD /transfer/upload/{id}` : retourne JSON `{ received_chunks: [0,1,3,...] }`
- T4.3 🔴 `POST /transfer/finalize/{id}` : concat les chunks, SHA-256 final, déplacement vers destination
- T4.4 🔴 Destination configurable : `~/Linkup/Inbox/` par défaut
- T4.5 🧪 pytest : envoi 100 Mo en 100 chunks, finalize OK

### S4.J2 — Endpoint download FastAPI + Laravel orchestration
- T4.6 🔴 `GET /transfer/download/{id}?chunk=N` : retourne le chunk N
- T4.7 🔴 Côté Laravel : `TransferService::initiate($deviceId, $direction, $filename, $size)` crée entrée `transfers` + `transfer_id` UUID
- T4.8 🔴 Reverb event `FileTransferRequested` notifie l'autre côté
- T4.9 🔴 Pour PC→Tel : Laravel prépare les chunks, Flutter télécharge

### S4.J3 — Flutter upload UI
- T4.10 🔴 Écran « Envoyer fichier » avec `file_picker` multi-fichiers
- T4.11 🔴 Service `TransferClient` : chunke avec `dio`, parallélise 4 chunks max
- T4.12 🔴 Barre de progression par fichier + global
- T4.13 🔴 Bouton annuler : `DELETE /transfer/{id}`, cleanup serveur

### S4.J4 — Flutter download UI + reprise
- T4.14 🔴 Notif Flutter à la réception : « PC veut t'envoyer X »
- T4.15 🔴 Auto-accept configurable (réglage par device)
- T4.16 🔴 Reprise : si app fermée pendant transfert, au relancement, `HEAD` pour récupérer la liste des chunks manquants, reprendre uniquement ceux-là
- T4.17 🔴 Coupure simulée : kill réseau, reprise OK

### S4.J5 — Dashboard drag&drop + tests
- T4.18 🔴 Dashboard `/transfer` : zone drop, sélection device cible, progression
- T4.19 🔴 Limite configurable (default 2 Go) dans `module_settings`
- T4.20 🧪 Pest + pytest : transfert complet, reprise après kill, refus si > limite
- T4.21 🧪 Manuel : 10 fichiers (1 Ko à 500 Mo) tel→PC et PC→tel

**🧪 DoD S4 :**
- [ ] 500 Mo transféré en moins de 30s sur LAN gigabit
- [ ] Coupure réseau → reprise propre sans corruption
- [ ] 10 transferts consécutifs sans crash

---

## S5 — Presse-papier + Lien rapide

**🎯 Objectif :** Sync clipboard manuelle (limitation Android) + ouverture de liens cross-device.

### S5.J1 — ClipboardService Laravel + anti-boucle
- T5.1 🔴 Service `ClipboardService::receive($deviceId, $content, $hash, $origin)`
- T5.2 🔴 Anti-boucle : rejet si hash dans `recent_hashes` (TTL 2s in-memory Redis ou cache Laravel)
- T5.3 🔴 Persistance dans `clipboard_log`
- T5.4 🔴 Reverb event `ClipboardUpdated` aux autres devices

### S5.J2 — Pont Python clipboard OS
- T5.5 🔴 `bridge/app/os/clipboard.py` : abstraction Linux (`xclip` + `wl-paste`) + Windows (`pyperclip`)
- T5.6 🔴 Endpoint `POST /clipboard/write` + `GET /clipboard/read`
- T5.7 🔴 Détection X11 vs Wayland (Linux)
- T5.8 🧪 pytest : round-trip texte ASCII, UTF-8, emojis, multi-ligne

### S5.J3 — Flutter UI clipboard
- T5.9 🔴 Bouton FAB « Envoyer presse-papier » (lecture manuelle, Android 10+ toast inévitable)
- T5.10 🔴 Lecture via `super_clipboard` au tap utilisateur
- T5.11 🔴 Réception : notification « Texte copié depuis PC » + bouton « Copier »
- T5.12 🔴 Historique des 50 derniers items synchronisés (table `clipboard_log`)

### S5.J4 — Lien rapide (LinkService)
- T5.13 🔴 Détection auto : si contenu clipboard est URL valide, propose « Ouvrir sur PC ? »
- T5.14 🔴 Reverb event `LinkOpenRequested` → pont Python `os.startfile()` Windows ou `xdg-open` Linux
- T5.15 🔴 Endpoint pont Python `POST /link/open` avec validation URL (refus `file://`, `javascript:`, etc.)
- T5.16 🔴 Côté tel : ouverture lien envoyé depuis PC via `url_launcher`

### S5.J5 — Historique + tests
- T5.17 🔴 Écran historique : items clipboard + liens, recherche, copy-back
- T5.18 🔴 Purge auto > 30 jours
- T5.19 🧪 Pest : anti-boucle clipboard, refus URL dangereuse
- T5.20 🧪 Manuel : copie 20 contenus variés (texte, URL, multi-ligne, emoji)

**🧪 DoD S5 :**
- [ ] Texte copié sur tel → coller sur PC en < 1s après tap utilisateur
- [ ] URL envoyée depuis tel s'ouvre dans navigateur PC en < 2s
- [ ] Anti-boucle prouvée (push d'un même contenu n'aller-retourne pas)

---

## S6 — Galerie distante

**🎯 Objectif :** Parcourir 5000 photos Android depuis le PC avec pagination et cache vignettes.

### S6.J1 — Permission MediaStore + indexation tel
- T6.1 🔴 Permissions `READ_MEDIA_IMAGES` + `READ_MEDIA_VIDEO` Android 13+
- T6.2 🔴 Indexer la galerie tel (lib `photo_manager` Flutter)
- T6.3 🔴 Envoyer index initial paginé : `GET /api/gallery/{deviceId}?page=N&size=50` retourne metadata (id, mime, taken_at, size)

### S6.J2 — Vignettes générées tel
- T6.4 🔴 Génération vignettes 200×200 JPEG (~10 Ko) côté Flutter
- T6.5 🔴 Endpoint `POST /api/gallery/thumb` reçoit vignette → stockage `storage/gallery_cache/<device_id>/<media_id>.jpg`
- T6.6 🔴 Mise à jour `gallery_cache` SQLite

### S6.J3 — Dashboard galerie
- T6.7 🔴 Page `/gallery` : grille de vignettes, lazy load, scroll infini
- T6.8 🔴 Sélection multiple, bouton « Importer » → déclenche `FileTransferRequested` pour les originaux
- T6.9 🔴 Filtres : date, album, type (photo/vidéo)
- T6.10 🔴 Aperçu plein écran avec EXIF affichés

### S6.J4 — Import sélectif + indicateur consentement
- T6.11 🔴 Import effectif passe par module de transfert (S4)
- T6.12 🔴 Indicateur Flutter « PC parcourt actuellement ta galerie » (UX honnêteté)
- T6.13 🔴 Possibilité de couper le module galerie à tout moment depuis le tel

### S6.J5 — Tests + perfs
- T6.14 🔴 Test perf : 5000 items, première page < 3s
- T6.15 🔴 Test fiabilité : reload page galerie sans crash
- T6.16 🧪 Pest : pagination, refus si device non approuvé
- T6.17 🧪 Manuel : importer 30 photos en un click

**🧪 DoD S6 :**
- [ ] 50 vignettes affichées en < 3s sur LAN
- [ ] Import 10 originaux en parallèle fonctionne
- [ ] Indicateur tel s'allume bien pendant parcours PC

**🚦 Gate B2 :** 4 modules « fichiers & contenu » utilisables. **Démo interne : envoie un fichier, copie un texte, ouvre un lien, importe 5 photos.**

---

# 📦 BRIQUE 2.5 — Alpha publique LAN (S6.5 • 1 semaine)

> **Décision 2026-05-30 :** au lieu d'attendre S23 pour packager Linkup, on livre une **alpha publique LAN-only** dès la fin de la brique 2. Objectif : mettre Linkup entre les mains de vrais utilisateurs (5-20 testeurs) avec 5 modules sur 9, et récolter du feedback pendant que le reste se développe.

**🎯 Objectif global :** Linkup installable en double-clic sur Linux + Windows + APK signé téléchargeable, page de download publique. Limitation assumée : usage **sur même Wi-Fi uniquement** (le tunnel VPS arrive S20-S21).

**📤 Sortie :** `linkup.sahelstack.tech` avec 3 boutons (Linux .sh • Windows .exe • Android .apk), README utilisateur, version v0.5.0-alpha taguée sur GitHub.

## S6.5.J1 — Installateur Linux
- T6.5.1 🔴 Script `infra/install-linux.sh` :
  - Détection apt/dnf
  - Install PHP 8.4, Python 3.11, dépendances système
  - Clone du repo dans `/opt/linkup/`
  - Génération clés Ed25519 + APP_KEY Laravel
  - Création 3 services systemd : `linkup-agent.service`, `linkup-bridge.service`, `linkup-reverb.service`
  - Démarrage auto au boot
- T6.5.2 🔴 Tester sur Ubuntu 24.04 LTS fresh VM
- T6.5.3 🔴 Tester sur Debian 12 fresh VM

## S6.5.J2 — Installateur Windows
- T6.5.4 🔴 Inno Setup `infra/installer-win.iss`
- T6.5.5 🔴 Bundler PHP 8.4 portable + Python 3.11 embedded (~150 Mo)
- T6.5.6 🔴 Service Windows via `nssm` (3 services)
- T6.5.7 🔴 Tester sur Windows 11 fresh VM

## S6.5.J3 — APK Android signé
- T6.5.8 🔴 Générer keystore production (sauvegardé chiffré dans coffre-fort)
- T6.5.9 🔴 `flutter build apk --release` signé
- T6.5.10 🔴 Tester sideload sur 3 modèles Android différents

## S6.5.J4 — Page de download + GitHub Releases
- T6.5.11 🔴 Page statique `linkup.sahelstack.tech` (3 boutons + screenshots)
- T6.5.12 🔴 GitHub Release `v0.5.0-alpha` avec les 3 binaires
- T6.5.13 🔴 README utilisateur clair : « Linkup v0.5 = 5 modules livrés, 4 à venir »
- T6.5.14 🔴 Mention explicite : « Alpha LAN-only, usage hors Wi-Fi prévu pour v0.7 (mi-S21) »

## S6.5.J5 — Feedback channel + observabilité
- T6.5.15 🔴 Lien « Signaler un bug » → GitHub Issues template pré-rempli
- T6.5.16 🔴 Sentry actif sur les 3 binaires (DSN dédiés alpha)
- T6.5.17 🔴 Tutoriel vidéo court (3 min) : install + pairing + transfert fichier
- T6.5.18 📝 ADR-003.5 « Pourquoi alpha publique anticipée »

**🧪 DoD S6.5 :**
- [ ] Linkup installable en double-clic sur Linux + Windows fresh OS
- [ ] APK installable sideload sur Android 8+ sans erreur
- [ ] Page de download publique en ligne
- [ ] 3 testeurs externes ont installé, appairé et transféré un fichier sans aide

**🚦 Gate B2.5 :** Linkup est public. **Démo : envoyer le lien à 3 personnes différentes, elles installent toutes seules, elles transfèrent un fichier de leur tel à leur PC.**

> **Note planning :** ce bloc d'1 semaine décale toutes les semaines suivantes de +1 (S7 devient S8, etc.). Total projet passe à **26 semaines** au lieu de 25. Webcam virtuelle Windows reste sacrifiable si glissement (cf. Annexe C). Les installeurs S23 deviennent un simple **refresh des installeurs** alpha pour la version v1.0 finale (~2-3 jours au lieu d'une semaine entière).

---

# 📷 BRIQUE 3 — WebRTC Caméra & Micro (S7 → S10 • 4 semaines)

**🎯 Objectif global :** Flux vidéo + audio fluide tel → PC en navigateur, latence < 300 ms LAN.

## S7 — Signaling WebRTC + connexion PC↔tel basique

### S7.J1 — Compréhension Noise/WebRTC + ADR
- T7.1 🔴 ADR-004 « Architecture WebRTC : signaling via Reverb, PeerConnection unique vidéo+audio »
- T7.2 🔴 STUN public + TURN local placeholder (sera coturn en B7)

### S7.J2-J3 — Signaling via Reverb
- T7.3 🔴 Service `MediaStreamService` Laravel
- T7.4 🔴 Reverb events : `WebRtcOffer`, `WebRtcAnswer`, `WebRtcIceCandidate`
- T7.5 🔴 Route Laravel pour générer credentials TURN éphémères (REST API coturn-compatible, dummy en S7)

### S7.J4 — flutter_webrtc côté tel
- T7.6 🔴 Permissions caméra + micro
- T7.7 🔴 Création PeerConnection, capture caméra arrière par défaut
- T7.8 🔴 Envoi offer via Reverb, attente answer

### S7.J5 — Dashboard côté PC reçoit le flux
- T7.9 🔴 Page `/camera/{deviceId}` Next.js avec `RTCPeerConnection` navigateur
- T7.10 🔴 Affichage `<video>` du remote stream
- T7.11 🧪 Manuel : flux visible en navigateur sur LAN

**🧪 DoD S7 :** Flux caméra visible sur dashboard, latence < 500 ms (sera optimisée S8).

---

## S8 — Audio (micro) + qualité

### S8.J1-J2 — Ajout piste audio dans PeerConnection
- T8.1 🔴 `flutter_webrtc` : ajouter track micro à la même PeerConnection que caméra
- T8.2 🔴 Codec audio : Opus 48 kHz mono
- T8.3 🔴 Atténuation écho côté Flutter (`getUserMedia` constraints)

### S8.J3 — Indicateur qualité
- T8.4 🔴 `getStats()` RTCPeerConnection → RTT, jitter, packet loss
- T8.5 🔴 Affichage badge qualité (vert/orange/rouge) sur dashboard et Flutter

### S8.J4 — UX caméra : switch avant/arrière, mute, stop
- T8.6 🔴 Boutons Flutter : flip caméra, mute micro, stop tout
- T8.7 🔴 Boutons dashboard : capture screenshot, plein écran

### S8.J5 — Tests latence + bande passante
- T8.8 🔴 Mesure latence end-to-end (timestamp video frame)
- T8.9 🔴 Test bande passante constrainte : limiter à 1 Mbps, vérifier dégradation gracieuse
- T8.10 🧪 Manuel : flux fluide LAN, latence mesurée < 300 ms

**🧪 DoD S8 :** Vidéo + audio simultanés stables 5 minutes LAN.

---

## S9 — Robustesse WebRTC (déconnexions, re-établissement)

### S9.J1 — Re-négociation
- T9.1 🔴 Switch caméra → re-négociation propre
- T9.2 🔴 Coupure Wi-Fi → reconnexion ICE

### S9.J2 — Permissions + gestion erreurs
- T9.3 🔴 UI claire si permission refusée
- T9.4 🔴 Gestion du cas "autre app utilise la caméra"

### S9.J3 — Économie batterie
- T9.5 🔴 Foreground service Flutter pour ne pas être tué pendant un appel
- T9.6 🔴 Reduce framerate quand l'écran tel est éteint

### S9.J4-J5 — Tests croisés
- T9.7 🧪 Test 10 sessions consécutives : démarrer, 1 min, stop, redémarrer
- T9.8 🧪 Test bascule réseau : 4G ↔ Wi-Fi pendant session
- T9.9 📝 Tutoriel vidéo « démarrer la caméra Linkup »

**🧪 DoD S9 :** 10 sessions sans crash, recovery propre après coupure réseau.

---

## S10 — Polish + intégration future (préparation webcam virtuelle)

### S10.J1-J2 — API pont Python pour recevoir le flux PC
- T10.1 🔴 Pont Python lance navigateur headless (`playwright`) ou écoute WebRTC native via `aiortc` → reçoit le flux côté Python
- T10.2 🔴 Sortie : raw frames disponibles pour la suite (B6 webcam virtuelle)

### S10.J3-J4 — Sélection caméra avancée + résolution
- T10.3 🔴 Liste des caméras tel (avant, arrière, large, télé)
- T10.4 🔴 Sélecteur résolution : 480p / 720p / 1080p

### S10.J5 — Tests + ADR
- T10.5 🧪 Démo complète : caméra, micro, switch, stop, latence mesurée
- T10.6 📝 ADR-005 « Choix Opus + VP8 + résolution adaptative »

**🚦 Gate B3 :** Caméra + micro fonctionnels en navigateur, prêts pour la couche virtuelle. **Si latence > 400 ms persistante, investiguer avant B4.**

---

# ⌨️ BRIQUE 4 — Pont OS Python : 5 modules contrôle PC (S11 → S14 • 4 semaines)

**🎯 Objectif global :** Terminal, contrôle média, notifs miroir, preview localhost, faire sonner.

## S11 — Terminal distant (le plus risqué)

### S11.J1 — Conception sécurité
- T11.1 🔴 ADR-006 « Terminal restreint : allow-list par défaut, opt-in PC »
- T11.2 🔴 Liste blanche par défaut : `ls`, `pwd`, `cd`, `cat`, `head`, `tail`, `grep`, `git`, `php artisan`, `npm`, `pnpm`, `docker ps`, `docker logs`, `systemctl status`, `journalctl`

### S11.J2 — PTY pont Python
- T11.3 🔴 Lib `ptyprocess` (Linux) + `pywinpty` (Windows), abstraction `bridge/os/pty.py`
- T11.4 🔴 WebSocket binaire `/term/ws?session={sid}` avec auth token
- T11.5 🔴 Frames typées `[type:u8][len:u32][payload]`

### S11.J3 — Filtre allow-list + escape ANSI
- T11.6 🔴 Parsing commande (premier mot avant espace), vérification allow-list
- T11.7 🔴 Refus mode shell expansion (`$()`, backticks) sauf mode full
- T11.8 🔴 Filtrage séquences ANSI `OSC` dangereuses dans stdout

### S11.J4 — UI tel + dashboard
- T11.9 🔴 Flutter : vt100 minimal, clavier virtuel, historique commandes
- T11.10 🔴 Dashboard `xterm.js` : terminal embarqué pour monitoring

### S11.J5 — Confirmation + audit
- T11.11 🔴 Popup PC à l'ouverture session : « X veut ouvrir un terminal restreint/full »
- T11.12 🔴 Log de chaque commande dans `terminal_commands`
- T11.13 🧪 Pest : refus commande hors allow-list, audit présent
- T11.14 🧪 Manuel : 20 commandes shell, kill session propre

**🧪 DoD S11 :**
- [ ] Allow-list bloque `rm -rf /`, `curl | sh`, etc.
- [ ] Toutes commandes loggées
- [ ] Latence frappe < 100 ms LAN

---

## S12 — Contrôle média (MPRIS Linux + SMTC Windows)

### S12.J1 — MPRIS Linux
- T12.1 🔴 `dbus-python` ou `pydbus`, listing des players MPRIS actifs
- T12.2 🔴 Endpoints pont : `/media/players`, `/media/play`, `/media/pause`, `/media/next`, `/media/prev`, `/media/volume`

### S12.J2 — SMTC Windows
- T12.3 🔴 Lib `winrt-Windows.Media.Control` (pip `winrt`)
- T12.4 🔴 Mêmes endpoints, abstraction identique

### S12.J3 — Récupération artwork + métadonnées
- T12.5 🔴 Titre + artiste + album + position + duration
- T12.6 🔴 Artwork base64 (MPRIS) ou via cache Spotify (Windows fallback)

### S12.J4 — UI Flutter
- T12.7 🔴 Écran « Now Playing » avec artwork, contrôles, slider position
- T12.8 🔴 Auto-refresh toutes les 2s

### S12.J5 — Tests
- T12.9 🧪 Manuel : tester Spotify, VLC, Firefox YouTube, lecteur Films Win11
- T12.10 🧪 Pest + pytest : mocks MPRIS/SMTC

**🧪 DoD S12 :** Pilotage de 3 players différents sur les 2 OS.

---

## S13 — Notifs miroir Android → PC

### S13.J1 — NotificationListenerService
- T13.1 🔴 Lib `notification_listener_service` Flutter
- T13.2 🔴 Permission spéciale Android Settings (guide utilisateur)
- T13.3 🔴 Filtre apps : whitelist configurable (par défaut : WhatsApp, Signal, Telegram, Gmail, Slack)

### S13.J2 — Envoi à PC
- T13.4 🔴 Reverb event `NotificationMirrored` avec `{package, title, body, icon_base64, timestamp}`
- T13.5 🔴 Stockage `notifications_mirror`

### S13.J3 — Affichage PC Linux + Windows
- T13.6 🔴 `notify-send` Linux (libnotify)
- T13.7 🔴 `win10toast` Windows (ou `winrt.Windows.UI.Notifications`)
- T13.8 🔴 Cliquer une notif PC → marqué `dismissed_at`

### S13.J4 — Dashboard notifications
- T13.9 🔴 Centre de notifs sur dashboard (liste, filtre, archive)

### S13.J5 — Tests
- T13.10 🧪 Manuel : recevoir notifs WhatsApp, vérifier affichage PC
- T13.11 🧪 Test perf : 100 notifs en 5 min sans saturation

**🧪 DoD S13 :** Notif Android visible PC en < 2s.

---

## S14 — Faire sonner + Preview localhost

### S14.J1-J2 — Faire sonner
- T14.1 🔴 Foreground service Flutter joue son + vibration + flash écran
- T14.2 🔴 Confirmation PC avant émission
- T14.3 🔴 Réception : même en veille (foreground service permanent)

### S14.J3-J5 — Dev Preview (localhost mobile)

> **Refonte 2026-06-04** (cf. CDC §16.5, [[linkup-dev-preview]]). Remplace l'ancien
> « reverse proxy L7 httpx + tunnel VPS ». Le besoin réel : un dev teste sur son tél,
> **sans déployer**, un projet web qui tourne sur le PC, avec le **même comportement**
> que dans le navigateur du PC (multi-services, WebSocket, contexte sécurisé). Approche :
> **proxy TCP transparent par projet** (relais d'octets bruts → HTTP **et** WS), servi en
> **HTTPS** (caméra/PWA exigent un contexte sécurisé). Plus de tunnel VPS pour ce module
> (LAN-only), plus de table `localhost_tunnels` (état en mémoire dans le bridge).

**Lot A — proxy transparent multi-ports + WS (bridge) — ✅ FAIT (2026-06-04)**
- ✅ T14.4 `bridge/app/services/preview.py::ProxyManager` : un listener LAN éphémère
  par projet, relais d'octets bruts vers `127.0.0.1:<port>` (HTTP + WebSocket sans parsing),
  idempotent, `connect_host` figé à 127.0.0.1 (anti-SSRF).
- ✅ T14.5 Détection des serveurs de dev via `/proc/net/tcp{,6}` (`scan_listening_ports`,
  Linux), nom de process best-effort, exclut le port du bridge + proxies actifs.
- ✅ T14.6 Routes `bridge/app/routes/preview.py` (token agent) : `GET /preview/ports`,
  `POST /preview/expose`, `GET /preview/exposed`, `POST /preview/unexpose`. Câblé dans
  `main.py` (manager en `app.state`, fermé à l'arrêt).
- ✅ T14.7 Tests `bridge/tests/test_preview.py` : 9 ✓ (relais bidirectionnel, idempotence,
  port injoignable → `ProxyError`/404, scan détecte/exclut, flux des routes).

**Lot B — HTTPS + CA de confiance — ✅ FAIT côté bridge (2026-06-04)**
- ✅ T14.8 `bridge/app/services/cert.py::CertManager` : **CA Linkup** générée une fois
  sous `~/.linkup/ca` (`cryptography`, Python pur, sans droits admin) + cert serveur
  (SAN = IP LAN + 127.0.0.1 + localhost) régénéré au démarrage ; clé privée en `0o600`.
  `ProxyManager(ssl_context=…)` → TLS terminé au listener, relais vers le dev-server en
  clair en local. Route publique `GET /preview/ca.crt` (MIME `x-x509-ca-cert`) pour
  l'install sur le tél. `cryptography` ajouté à `pyproject` + `collect_all` dans le `.spec`.
- ✅ Tests `tests/test_cert.py` : 7 ✓ (CA = autorité, cert signé par la CA + SAN loopback,
  CA stable entre démarrages, **relais HTTPS accepté si CA de confiance / refusé sinon**).
- 🔴 T14.9 App tél (Flutter) : flux d'**installation/approbation de la CA** (1 fois, via
  `/preview/ca.crt`) + ouverture du projet `https://<host-bridge>:<listen_port>` dans le
  **navigateur externe**. → fait partie du Lot C.

**Lot C — orchestration tél (Laravel + Flutter) — 🔴 À FAIRE**
- 🔴 T14.10 Laravel `/api/preview/*` (auth.device) relaie vers le bridge (token agent).
- 🔴 T14.11 Écran Flutter : liste des projets détectés → « Exposer » → ouvrir.

**Lot D — détecteur de compatibilité — 🟠 PHASE 1.5**
- 🟠 T14.12 Scan source : alerte sur `localhost`/`127.0.0.1` codés en dur, recommande
  URL relative / variable d'env, liste les fichiers concernés.

**Différé (version finale) :** « Mode Compatibilité » = réécriture auto des `localhost` en
dur (HTML+JS+WS+CORS) — hors MVP.

- T14.13 🧪 Manuel : `python -m http.server 3000` (puis un vrai projet Vite + Reverb),
  exposer, ouvrir sur le tél, vérifier HMR + WebSocket + (en HTTPS) la caméra navigateur.

**🧪 DoD S14 :** Tel sonne même en veille ; projet localhost (front + WS) ouvrable depuis le
tél **en HTTPS**, avec HMR/temps réel fonctionnels.

**🚦 Gate B4 :** 5 modules de contrôle PC stables. **Démo intermédiaire : terminal + contrôle Spotify + notif WhatsApp + faire sonner + exposer un Vite localhost.**

---

# ⬇️ BRIQUE 5 — Médias lourds + slides + scanner (S15 → S17 • 3 semaines)

## S15 — Téléchargeur yt-dlp + Conversion ffmpeg

### S15.J1-J2 — yt-dlp wrapper
- T15.1 🔴 Endpoint pont `/media/download {url, format}` lance job
- T15.2 🔴 Job queue Laravel + worker Python, statut dans `media_jobs`
- T15.3 🔴 Destination `~/Linkup/Downloads/`, sous-dossier par device
- T15.4 🔴 Cron hebdo `pip install -U yt-dlp` via systemd timer

### S15.J3 — UI tel téléchargement
- T15.5 🔴 Paste URL ou partage Android intent vers Linkup
- T15.6 🔴 Choix qualité (best, 720p, audio only)
- T15.7 🔴 Liste téléchargements + statut + bouton « Ouvrir sur PC »

### S15.J4-J5 — Conversion ffmpeg
- T15.8 🔴 Endpoint pont `/media/convert {file, target_format}`
- T15.9 🔴 Présets : mp4→mp3, webp→png, mov→mp4, gif→mp4, image→pdf
- T15.10 🔴 UI tel : sélection fichier (galerie ou inbox) + format
- T15.11 🧪 Manuel : DL YouTube + conv mp4→mp3 + conv webp→png

**🧪 DoD S15 :** yt-dlp et ffmpeg fonctionnels avec UI.

---

## S16 — Transcription Whisper

### S16.J1 — Setup faster-whisper
- T16.1 🔴 `pip install faster-whisper`, modèle `base` (290 Mo) téléchargé lazy
- T16.2 🔴 Détection GPU (CUDA Win/Linux, ROCm Linux), fallback CPU
- T16.3 🔴 Stockage modèle `~/.linkup/models/`

### S16.J2 — Endpoint + job
- T16.4 🔴 Endpoint `/media/transcribe {file, language}`
- T16.5 🔴 Progress stream via WebSocket (chunks de transcription)
- T16.6 🔴 Stockage résultat `.txt` à côté du source

### S16.J3 — UI Flutter
- T16.7 🔴 Upload audio (depuis enregistrement tel direct ou fichier)
- T16.8 🔴 Choix langue (auto, fr, en, ar)
- T16.9 🔴 Affichage progressif + bouton copier dans clipboard

### S16.J4-J5 — Tests précision
- T16.10 🧪 Manuel : 3 audios FR (1 min, 5 min, 15 min), mesurer WER
- T16.11 🧪 Test mémoire : audio 30 min, pas d'OOM

**🧪 DoD S16 :** Transcription FR fonctionnelle, WER < 15% sur audio clair.

---

## S17 — Télécommande slides + Scanner QR

### S17.J1-J2 — Télécommande slides
- T17.1 🔴 Endpoint pont `/slides/key {key}` → `pyautogui.press(key)`
- T17.2 🔴 UI Flutter : grandes flèches gauche/droite, bouton « écran noir » (B), timer
- T17.3 🔴 Optionnel : upload PDF + sync slide actuel via `pdfx` Flutter

### S17.J3-J4 — Scanner QR
- T17.4 🔴 Écran scan QR Flutter (lib `mobile_scanner` déjà installée)
- T17.5 🔴 Mode : pousser vers PC, mode auto-ouvrir si URL
- T17.6 🔴 Affichage PC : popup avec contenu + actions

### S17.J5 — Tests + démo
- T17.7 🧪 Manuel : présentation 30 slides Impress + LibreOffice
- T17.8 🧪 Manuel : scanner 10 QR (URL, texte, vCard, Wi-Fi)

**🚦 Gate B5 :** 14 modules sur 16 fonctionnels (manque webcam virtuelle + tunnel VPS).

---

# 📹 BRIQUE 6 — Webcam virtuelle système (S18 → S19 • 2 semaines)

## S18 — Linux v4l2loopback

### S18.J1-J2 — Setup v4l2loopback
- T18.1 🔴 Script install : `sudo apt install v4l2loopback-dkms` + `sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="Linkup Camera"`
- T18.2 🔴 systemd unit pour load au boot
- T18.3 🔴 Documentation install user

### S18.J3-J5 — pyvirtualcam bridge
- T18.4 🔴 Pont Python reçoit flux WebRTC (via `aiortc`)
- T18.5 🔴 Décode frames, push vers `/dev/video10` via `pyvirtualcam`
- T18.6 🔴 UI Flutter : toggle « Activer webcam système »
- T18.7 🔴 Indicateur PC : « Webcam Linkup active »
- T18.8 🧪 Manuel : ouvrir Zoom, Meet, OBS, sélectionner « Linkup Camera », vérifier flux

**🧪 DoD S18 :** Linkup Camera visible et fonctionnelle dans 3 apps minimum.

---

## S19 — Windows via wrapper OBS Virtual Camera

### S19.J1-J2 — Détection OBS installé
- T19.1 🔴 Pont Python vérifie présence OBS dans Program Files
- T19.2 🔴 Si absent, dashboard affiche « Installer OBS Studio (lien) »
- T19.3 🔴 Activation OBS Virtual Camera via script PowerShell ou intégration `obs-websocket`

### S19.J3-J5 — Bridge flux vers OBS
- T19.4 🔴 Soit : pont Python crée scène OBS avec navigateur source pointant flux WebRTC
- T19.5 🔴 Soit : pont Python pousse frames vers OBS via `obs-websocket` plugin
- T19.6 🔴 Documenter clairement la procédure
- T19.7 🧪 Manuel : Zoom Windows utilise Linkup via OBS VC

**🧪 DoD S19 :** Webcam Linkup fonctionnelle Windows (avec OBS comme dépendance assumée).

---

# 🌐 BRIQUE 7 — Tunnel VPS fallback + coturn (S20 → S21 • 2 semaines)

## S20 — Relais Reverb VPS

### S20.J1 — Sous-domaine + Nginx
- T20.1 🔴 `relay.sahelstack.tech` : Nginx reverse proxy vers Reverb local sur VPS
- T20.2 🔴 Certbot Let's Encrypt
- T20.3 🔴 CORS strict (seul `linkup.sahelstack.tech` accepté)
- T20.4 🔴 Rate limiting Nginx (100 req/s par token)

### S20.J2 — Reverse SSH tunnel agent PC → VPS
- T20.5 🔴 Script `autossh` + systemd unit `linkup-tunnel.service`
- T20.6 🔴 Agent PC s'enregistre côté VPS via API (table `agents_remote`)
- T20.7 🔴 Génération token Bearer par-device

### S20.J3 — Bascule auto LAN ↔ tunnel
- T20.8 🔴 Flutter ping LAN (mDNS) → si fail 3 fois en 5s, bascule tunnel
- T20.9 🔴 UI : badge « Local » / « Distant »
- T20.10 🔴 Tâche planifiée : retest LAN toutes les 60s, rebasculer si dispo

### S20.J4-J5 — Tests
- T20.11 🧪 Depuis 4G, pairing complet via tunnel
- T20.12 🧪 Pendant transfert, couper Wi-Fi → bascule tunnel sans perte
- T20.13 🧪 Test sécurité : token volé d'un device → autres devices intacts

**🧪 DoD S20 :** Pairing + transfert + clipboard fonctionnels via tunnel depuis 4G.

---

## S21 — coturn TURN server pour WebRTC distant

### S21.J1-J2 — Install coturn sur VPS
- T21.1 🔴 `sudo apt install coturn`
- T21.2 🔴 Config `/etc/turnserver.conf` : long-term credentials, realm `sahelstack.tech`, TLS port 5349
- T21.3 🔴 Génération credentials éphémères via Laravel (REST API coturn)

### S21.J3 — Intégration WebRTC
- T21.4 🔴 `MediaStreamService` génère TURN credentials TTL 1h par session
- T21.5 🔴 ICE servers Flutter + navigateur incluent STUN + TURN

### S21.J4-J5 — Tests vidéo hors LAN
- T21.6 🧪 4G ↔ Wi-Fi : flux vidéo doit passer (avec latence dégradée)
- T21.7 🧪 Mesurer débit utilisé (qualité réduite acceptée)
- T21.8 📝 ADR-007 « coturn config + politique credentials »

**🧪 DoD S21 :** Vidéo passe hors LAN (qualité ≥ 480p).

**🚦 Gate B7 :** Produit utilisable hors LAN. **Démo intermédiaire complète : appairer un nouveau device depuis 4G, transférer, copier, ouvrir caméra.**

---

# 🧪 BRIQUE 8 — Tests, sécurité, packaging (S22 → S24 • 3 semaines)

## S22 — Tests exhaustifs

### S22.J1 — Coverage Pest backend
- T22.1 🔴 Atteindre 70% coverage Laravel (`pest --coverage`)
- T22.2 🔴 Tests d'intégration pairing + chaque module
- T22.3 🔴 Tests de charge : 100 events Reverb/s

### S22.J2 — Coverage pytest pont Python
- T22.4 🔴 70% coverage `bridge/`
- T22.5 🔴 Mock OS calls (clipboard, MPRIS, PTY)

### S22.J3 — Tests Flutter
- T22.6 🔴 Widget tests pour écrans clés
- T22.7 🔴 Integration tests : pairing flow, transfert, caméra

### S22.J4 — Tests E2E manuels
- T22.8 🧪 Scenario 1 : nouveau user, install agent, scan QR, transfert 5 fichiers
- T22.9 🧪 Scenario 2 : utilisation 1h continue, 50 actions variées
- T22.10 🧪 Scenario 3 : bascule LAN/4G en cours d'utilisation

### S22.J5 — Audit sécurité
- T22.11 🔴 Pentest manuel : rejeu nonce, MITM LAN simulé (mitmproxy), token volé d'un device, fuzzing terminal (séquences ANSI hostiles)
- T22.12 🔴 Audit dépendances (`composer audit`, `pnpm audit`, `pip-audit`, `flutter pub outdated`)

---

## S23 — Installateurs + packaging

### S23.J1-J2 — Installateur Linux
- T23.1 🔴 Script `infra/install-linux.sh` :
  - Détection distrib (apt / dnf)
  - Install PHP 8.4, Python 3.11, ffmpeg, v4l2loopback
  - Composer install, pip install
  - Génération clés Ed25519
  - systemd units : `linkup-agent.service`, `linkup-bridge.service`, `linkup-reverb.service`
  - Notification user : « Linkup installé, dashboard sur http://localhost:8000 »
- T23.2 🔴 Tester sur Ubuntu 24.04 LTS fresh
- T23.3 🔴 Tester sur Debian 12 fresh
- T23.4 🔴 Tester sur Fedora 39 fresh (best-effort)

### S23.J3-J4 — Installateur Windows
- T23.5 🔴 Inno Setup script `infra/installer-win.iss`
- T23.6 🔴 Bundler PHP 8.4 portable + Python 3.11 portable embarqué (~150 Mo)
- T23.7 🔴 Service Windows via `nssm` ou tâche planifiée
- T23.8 🔴 Vérifier OBS détecté ou proposer installation
- T23.9 🔴 Tester sur Windows 11 fresh VM

### S23.J5 — APK Android signé
- T23.10 🔴 Générer keystore production (sauvegardé chiffré dans coffre-fort)
- T23.11 🔴 Build release signé `flutter build apk --release`
- T23.12 🔴 Upload sur GitHub Releases
- T23.13 🔴 Test install sideload sur 3 téléphones différents

---

## S24 — Documentation + polish

### S24.J1-J2 — README + Wiki
- T24.1 📝 README monorepo avec quick start 5 min
- T24.2 📝 Wiki GitHub : installation détaillée par OS
- T24.3 📝 Documentation API REST agent (OpenAPI auto via Scribe)
- T24.4 📝 Documentation des 16 modules avec captures

### S24.J3 — Guide utilisateur PDF
- T24.5 📝 Guide PDF illustré : install + pairing + tour des 16 modules
- T24.6 📝 Section dépannage : pare-feu, mDNS, OBS

### S24.J4-J5 — Polish UX
- T24.7 🟢 Animations Flutter (transitions, splash)
- T24.8 🟢 Thème dark/light Flutter + dashboard
- T24.9 🟢 i18n FR + EN (Flutter + dashboard)
- T24.10 🟢 Onboarding tour première utilisation

**🧪 DoD S24 :**
- [ ] Installateurs Linux + Windows + APK fonctionnels sur fresh OS
- [ ] Documentation publique complète
- [ ] 0 bug critique connu

---

# 🎓 BRIQUE 9 — Recette + soutenance (S25 • 1 semaine)

## S25 — Démo + slides + Q&A

### S25.J1 — Vidéo démo
- T25.1 📝 Script démo 7 min : pairing → transfert → presse-papier → caméra → webcam virtuelle (Zoom) → terminal → contrôle Spotify → notif WhatsApp → preview localhost → bascule tunnel
- T25.2 📝 Enregistrement OBS, montage simple

### S25.J2 — Slides
- T25.3 📝 25 slides : pitch (3) + problèmes (3) + vision (2) + architecture (5) + démo points clés (5) + sécurité (3) + planning livré (2) + Phase 2 (1) + Q&A intro (1)

### S25.J3 — Q&A préparées
- T25.4 📝 Document Q&A : 30 questions probables avec réponses
  - Pourquoi Flutter ? Pourquoi hybride PHP+Python ? Pourquoi Reverb ?
  - Sécurité Noise IK : compare à TLS ? rotation ? révocation ?
  - Webcam virtuelle : pourquoi pas une vraie solution Windows ?
  - Performance Whisper, coût VPS, scalabilité…

### S25.J4 — Répétitions
- T25.5 🔴 Démo live × 5 en conditions réelles (Wi-Fi du lieu + hotspot 4G backup)
- T25.6 🔴 Préparer plan B : vidéo enregistrée si démo échoue

### S25.J5 — Soutenance
- T25.7 🎯 J-Day !

**🚦 Gate B9 :** Soutenance OK = projet livré.

---

# 📊 ANNEXE A — Vue calendaire condensée

| Semaine | Brique | Modules livrés en fin de semaine | Critère go/no-go |
|---|---|---|---|
| W0 | Setup | — | Scaffolds + CI verts |
| S1 | B1 | Reverb + FastAPI + mDNS live | Flutter découvre l'agent |
| S2 | B1 | Pairing QR + Noise IK + approbation | Pairing < 5s |
| S3 | B1 | Modèle de données + audit complet | 5 attaques échouent |
| S4 | B2 | Transfert fichiers (1) | 500 Mo + reprise OK |
| S5 | B2 | Presse-papier + Lien (3) | < 1s sync clipboard |
| S6 | B2 | Galerie distante (4) | 50 vignettes < 3s |
| **S6.5** | **B2.5** | **Alpha publique LAN (installeurs Linux+Win+APK)** | **3 testeurs externes OK** |
| S7 | B3 | Signaling WebRTC | Flux navigateur |
| S8 | B3 | Vidéo + audio | < 300 ms latence |
| S9 | B3 | Robustesse WebRTC | 10 sessions sans crash |
| S10 | B3 | Polish caméra (5) | Production ready |
| S11 | B4 | Terminal restreint (6) | Allow-list tient |
| S12 | B4 | Contrôle média (7) | 3 players OK |
| S13 | B4 | Notifs miroir (8) | < 2s tel → PC |
| S14 | B4 | Faire sonner + Preview (10) | Tel sonne en veille |
| S15 | B5 | yt-dlp + Conversion (12) | YouTube + mp3 OK |
| S16 | B5 | Transcription (13) | WER < 15% |
| S17 | B5 | Slides + Scanner (15) | Présentation 30 slides |
| S18 | B6 | Webcam virtuelle Linux | Zoom détecte |
| S19 | B6 | Webcam Windows wrapper (16) | Zoom Win OK |
| S20 | B7 | Tunnel VPS Reverb | 4G pairing OK |
| S21 | B7 | coturn vidéo distante | Vidéo 4G OK |
| S22 | B8 | Tests + audit sécu | 70% coverage |
| S23 | B8 | Installateurs + APK | Install fresh OS OK |
| S24 | B8 | Documentation complète | Guide PDF prêt |
| S25 | B9 | Démo + soutenance | ✅ |

---

# 🛠️ ANNEXE B — Outillage récurrent

## B.1 Routines hebdo (chaque vendredi 17h)
- Backup chiffré du keystore Android + clés Ed25519 → cloud chiffré
- `composer audit && pnpm audit && pip-audit && flutter pub outdated`
- Mise à jour journal de bord `docs/journal/SXX.md` (ce qui a été fait, blocages, decisions)
- Commit final de la semaine + tag `wXX-end`

## B.2 ADRs à produire
| # | Titre | Semaine |
|---|---|---|
| ADR-001 | Stack choisie et raisons | W0 |
| ADR-002 | Choix mDNS Linux/Windows | S1 |
| ADR-003 | Modèle de données | S3 |
| ADR-004 | Architecture WebRTC | S7 |
| ADR-005 | Codecs vidéo/audio | S10 |
| ADR-006 | Terminal restreint sécurité | S11 |
| ADR-007 | coturn config | S21 |

## B.3 Convention de branches Git
- `main` : prod-ready, jamais cassée
- `dev` : intégration semaine en cours
- `feat/SXX-<module>` : branche par tâche
- Merge `feat/*` → `dev` quotidien, `dev` → `main` chaque vendredi soir

## B.4 Definition of Done universelle (toute tâche)
- [ ] Code écrit + commité
- [ ] Test associé écrit + vert (sauf 🟢 best-effort)
- [ ] Documentation locale mise à jour si nécessaire
- [ ] Aucun secret commité (`git diff --staged | grep -i 'secret\|key\|token'`)
- [ ] Code formaté (Pint pour PHP, Black pour Python, dart_format, prettier)
- [ ] Pas de `dd()`, `var_dump()`, `print()`, `console.log()` traînant

## B.5 Communication & accountability
- **Stand-up perso quotidien** (5 min, voix mémo ou journal écrit) : hier / aujourd'hui / blocages
- **Bilan hebdo** vendredi : vélocité réelle vs prévue, ajustements
- **Revue mensuelle** (S4, S8, S12, S16, S20, S24) : re-priorisation si glissement

---

# ⚠️ ANNEXE C — Plan de gestion des risques

## C.1 Top 5 risques projet

| # | Risque | Probabilité | Impact | Mitigation primaire | Plan B |
|---|---|---|---|---|---|
| R1 | Webcam virtuelle Windows trop complexe | 60% | Moyen | Wrapper OBS dès S19 | Documenter limitation, prioriser Linux |
| R2 | WebRTC latence trop forte sur LAN | 25% | Élevé | Tester dès S7 sur vrai matériel | Reverb-only fallback pour modules critiques |
| R3 | Whisper trop lent sur CPU faible | 40% | Moyen | Modèle `base` par défaut, GPU si dispo | Modèle `tiny` en fallback configurable |
| R4 | NotificationListenerService refusé Play Store | 90% | Faible | Distribution sideload | Phase 2 : justifier Google |
| R5 | Glissement planning > 2 semaines | 50% | Élevé | Buffer en S25 + Gates B1-B7 | Couper Phase 1 modules secondaires (scanner, télécommande) |

## C.2 Procédure si retard > 1 semaine
1. Identifier la cause racine (technique / périmètre / fatigue)
2. Si technique : escalader en réduisant le périmètre du module en cours
3. Si périmètre : reporter le module en Phase 2 si non-bloquant
4. Si fatigue : 2 jours off, ne pas accumuler

## C.3 Modules « sacrifiables » si urgence

Si grosse galère, **par ordre de sacrifice possible** :
1. Webcam virtuelle Windows (B6 partiel)
2. Scanner QR (B5)
3. Télécommande slides (B5)
4. Conversion média (B5)
5. Galerie distante (B2 partiel — garder transfert simple)

**Modules intouchables (cœur de produit) :**
- Pairing + sécurité (B1)
- Transfert fichiers (B2)
- Clipboard + lien (B2)
- Caméra navigateur (B3)
- Terminal (B4)
- Notifs miroir (B4)
- Tunnel VPS (B7)

---

# 🏁 Conclusion

**Total :** 26 semaines (W0 + 25 semaines de dev), structurées en 9 briques avec 7 gates de validation.

**Approche :** Build → Test → Fix chaque semaine. Pas de big-bang testing à la fin. Tests Pest dès S1.

**Honnêteté technique :** webcam virtuelle Windows en wrapper (OBS), pas en filtre natif → assumé dans le CDC, à expliquer en soutenance.

**Backup mental :** 6 modules sont sacrifiables si glissement > 2 semaines, sans tuer le produit.

**Tu peux démarrer ce lundi.** Premier jour = T0.1, premier commit = T0.13. Et si quelque chose ne marche pas à la première semaine, c'est T1.20 (test manuel découverte mDNS multi-device) qui dira si tu pars sur de bonnes bases.

Bonne route. 🛣️
