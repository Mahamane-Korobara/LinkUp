# 🔗 Linkup

*Ton téléphone Android et ton PC (Linux ; Windows bientôt), reliés en un scan — plus des outils qui marchent même sans PC.*

Linkup, c'est deux choses :

1. **Un hub cross-device.** Un seul scan de QR code appaire ton téléphone et ton PC sur le même Wi-Fi, et des modules deviennent disponibles des deux côtés : transfert de fichiers, presse-papier partagé, galerie à distance, aperçu de dev (le `localhost` du PC sur le tél). Un mode **tél ↔ tél** permet aussi d'échanger entre deux téléphones, **sans aucun PC**.
2. **Des outils autonomes** (juste une connexion internet, aucun PC) : un **téléchargeur de vidéos** multi-plateformes (YouTube, TikTok, Instagram, X, Vimeo…) et une **transcription par IA** qui met la parole en texte — **même sans sous-titres** — exportable en **PDF**.

Pas de compte, pas de câble, pas de cloud tiers pour le partage local.

---

## 🗂️ Structure du monorepo

```
linkup/
├── agent/        # Laravel 12 (PHP 8.4) — orchestrateur, pairing, Reverb (LAN)
├── bridge/       # FastAPI Python — pont OS local du PC (clipboard, caméra, PTY, ffmpeg)
├── mobile/       # Flutter 3 — app Android
├── dashboard/    # Next.js 15 — tableau de bord web local (côté PC)
├── vitrine/      # Next.js — landing publique sur Vercel (linkup-landing.sahelstack.tech)
├── videohub/     # FastAPI sur le VPS (internet) — téléchargeur vidéo + transcription IA
├── infra/        # déploiement (videohub, bundle PC, configs Apache/supervisor)
├── packaging/    # build des installeurs PC (AppImage, .deb)
├── docs/         # CDC, plan d'exécution, ADRs
└── .github/      # CI workflows + Dependabot
```

> **`bridge` vs `videohub`** : le `bridge` tourne **en local sur le PC** (réseau Wi-Fi, ponts OS).
> Le `videohub` est un service **internet sur le VPS** (yt-dlp + ffmpeg + Gemini/Whisper) qui
> sert le téléchargeur vidéo et la transcription — indépendant de l'appairage tél↔PC.

## 📦 Télécharger / installer

Tout part de la vitrine : **[linkup-landing.sahelstack.tech](https://linkup-landing.sahelstack.tech)**

| Plateforme | Lien direct |
|---|---|
| Android — récent (64-bit) | `https://linkup.sahelstack.tech/dl/linkup.apk` |
| Android — anciens tél (32-bit) | `https://linkup.sahelstack.tech/dl/linkup-32bit.apk` |
| PC Linux — AppImage (universel) | `https://linkup.sahelstack.tech/dl/linkup.AppImage` |
| PC Debian/Ubuntu/Mint — `.deb` | `https://linkup.sahelstack.tech/dl/linkup-pc.deb` |

## 🧰 Les outils

**Avec appairage tél ↔ PC** (Wi-Fi local) : transfert de fichiers (reprise auto), presse-papier partagé, galerie à distance, aperçu de dev (HTTPS de confiance + caméra/micro/géoloc).
**Sans aucun PC** : partage tél ↔ tél (un QR suffit), téléchargeur vidéo, transcription IA.

### Téléchargeur vidéo + transcription (`videohub`)
- Multi-plateformes via **yt-dlp** (≈ 1700 sites). YouTube est débloqué sur le VPS via cookies + PO-token provider + Deno/EJS — cf. **[infra/videohub/README.md](infra/videohub/README.md)**.
- **Transcription en cascade** : sous-titres → **Gemini audio** (ASR) → **Whisper** (faster-whisper, dernier recours). Mise en forme en document propre, **export PDF rendu côté téléphone**.
- **Cache local** des transcriptions (2 jours) pour économiser les requêtes IA.
- Téléchargement/transcription continuent **en arrière-plan** (service de premier plan + notification de progression).

## 🚀 Quick start (dev local — Linux Ubuntu/Debian)

### Prérequis
- PHP 8.4 + Composer · Python 3.11+ · Node 20+ + pnpm 9 · Flutter 3.41+ · SQLite

### Lancer l'agent + le bridge + le dashboard

```bash
# 1. Agent Laravel
cd agent
composer install
cp .env.example .env && php artisan key:generate
php artisan migrate
php artisan serve --host 0.0.0.0 --port 8000   # API HTTP (0.0.0.0 = accessible au tél)
php artisan reverb:start &                      # WebSocket :8080

# 2. Bridge Python (nouveau terminal)
cd bridge
python3 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env
uvicorn app.main:app --host 127.0.0.1 --port 8765

# 3. Dashboard Next.js (nouveau terminal)
cd dashboard
pnpm install && pnpm dev                        # http://localhost:3000

# 4. App mobile : installer l'APK (cf. ci-dessus) ou
cd mobile && flutter run
```

> Le **`videohub`** est un service séparé (VPS, internet) — son déploiement est décrit dans
> **[infra/videohub/README.md](infra/videohub/README.md)** (ffmpeg, venv, supervisor, Apache,
> cookies YouTube, faster-whisper). L'app mobile y pointe via `linkup.sahelstack.tech/video`.

## 📚 Documentation

- **[Cahier des Charges v2.0](docs/Linkup-CDC-v2_0.md)** — spec produit + technique
- **[Plan d'exécution](docs/Linkup-Plan-Execution.md)** — découpage jour par jour
- **[ADRs](docs/adr/)** — décisions d'architecture
- **[infra/videohub/README.md](infra/videohub/README.md)** — déploiement du service vidéo

## 🛠️ Tests

```bash
cd agent && ./vendor/bin/pest         # Agent Laravel
cd bridge && pytest                   # Bridge Python (LAN)
cd videohub && .venv/bin/pytest       # Service vidéo (VPS)
cd mobile && flutter test             # App Flutter
cd dashboard && pnpm lint && pnpm build
```

## 🔒 Sécurité

- Appairage tél↔PC : handshake + paire de clés par device, tokens hashés, liste blanche
  d'appareils avec approbation explicite côté PC, terminal distant **opt-in**.
- `videohub` : token de service Bearer partagé app↔VPS + rate-limit par IP (garde-fou
  anti-abus). Cookies/secrets jamais commités (cf. `.gitignore`).
- Cf. `docs/Linkup-CDC-v2_0.md` §10 et §18.

## 🗺️ Roadmap

- **Maintenant** : hub tél↔PC (fichiers, presse-papier, galerie, dev preview) + tél↔tél,
  téléchargeur vidéo et transcription IA. Android + Linux.
- **Ensuite** : Windows, partage entrant iOS, autres outils (webcam déportée, conversion,
  notifs miroir…), et plus au fil des mises à jour.

## 📄 Licence

À définir avant publication (probablement MIT ou Apache 2.0).

## 👤 Auteur

Mahamane Korobara — [sahelstack.tech](https://sahelstack.tech)
