# 🔗 Linkup

*Ton téléphone Android et ton PC (Windows/Linux), reliés en un scan.*

Linkup est un hub cross-device : un seul scan de QR code suffit à appairer ton téléphone et ton PC, et 16 modules deviennent disponibles des deux côtés — transfert de fichiers, presse-papier, galerie, caméra/micro réutilisés, terminal restreint, notifs miroir, contrôle média, téléchargeur, transcription, et plus.

Pas de compte, pas de câble, pas de cloud tiers.

---

## 🗂️ Structure du monorepo

```
linkup/
├── agent/        # Laravel 12 (PHP 8.4) — orchestrateur, pairing, Reverb
├── bridge/       # FastAPI Python — pont OS (clipboard, caméra, PTY, yt-dlp, Whisper, ffmpeg)
├── mobile/       # Flutter 3 — app Android
├── dashboard/    # Next.js 15 — interface web
├── docs/         # CDC, plan d'exécution, ADRs
├── infra/        # scripts d'install, systemd units, configs déploiement
└── .github/      # CI workflows + Dependabot
```

## 🚀 Quick start (Linux Ubuntu / Debian)

### Prérequis
- PHP 8.4 + Composer
- Python 3.11+
- Node 20+ + pnpm 9
- Flutter 3.41+ (pour rebuild l'APK)
- SQLite

### Lancer l'agent + le bridge en local

```bash
# 1. Agent Laravel
cd agent
composer install
cp .env.example .env && php artisan key:generate
php artisan migrate
php artisan serve              # HTTP API :8000
php artisan reverb:start &     # WebSocket :8080

# 2. Bridge Python (nouveau terminal)
cd bridge
python3 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env
uvicorn app.main:app --host 127.0.0.1 --port 8765

# 3. Dashboard Next.js (nouveau terminal)
cd dashboard
pnpm install
pnpm dev                       # http://localhost:3000

# 4. App mobile : installer l'APK depuis GitHub Releases ou flutter run
cd mobile && flutter run
```

## 📚 Documentation

- **[Cahier des Charges v2.0](docs/Linkup-CDC-v2_0.md)** — spec produit + technique
- **[Plan d'exécution 25 semaines](docs/Linkup-Plan-Execution.md)** — découpage jour par jour
- **[ADRs](docs/adr/)** — décisions d'architecture

## 🛠️ Tests

```bash
# Agent
cd agent && ./vendor/bin/pest

# Bridge
cd bridge && pytest

# Mobile
cd mobile && flutter test

# Dashboard
cd dashboard && pnpm lint && pnpm build
```

## 🔒 Sécurité

- Handshake **Noise IK** (libsodium) + paire **Ed25519** par device
- Tokens persistants hashés **argon2id**, rotation 30 jours
- Liste blanche d'appareils avec approbation explicite côté PC
- Terminal distant **opt-in** + shell restreint par défaut
- Cf. `docs/Linkup-CDC-v2_0.md` §10 et §18

## 🗺️ Roadmap

**Phase 1 (25 semaines)** — 16 modules core sur Android + Windows + Linux.
**Phase 2** — Identification audio, iOS, macOS, webcam virtuelle Windows native.

## 📄 Licence

À définir avant publication (probablement MIT ou Apache 2.0).

## 👤 Auteur

Mahamane Korobara — [@sahelstack.tech](https://sahelstack.tech)
