# ADR-001 — Stack technique choisie

**Statut :** Accepté
**Date :** 2026-05-24
**Décideur :** Mahamane Korobara

---

## Contexte

Linkup est un produit cross-device qui doit relier un téléphone Android et un PC (Windows/Linux) sans câble ni compte. Il faut :
- du temps réel bidirectionnel fiable (WebSocket)
- un accès système côté PC (clipboard OS, processus, caméra, ffmpeg)
- une app mobile native côté Android (caméra, capteurs, notifs)
- une interface web pour le pairing et les outils accessibles sans installer l'app
- une sécurité crypto bout-à-bout
- un développement solo soutenable sur 6 mois

## Décision

| Couche | Technologie | Pourquoi |
|---|---|---|
| Orchestrateur PC | **Laravel 12** (PHP 8.4) | Stack maîtrisée ; Reverb (WebSocket Pusher) natif ; structure modulaire ; déjà utilisée sur Laravel Ship et CollectIA |
| Pont système PC | **FastAPI Python 3.12** | Indispensable pour ce que PHP fait mal : clipboard OS multi-plateforme, ptyprocess/pywinpty, yt-dlp, faster-whisper, ffmpeg, v4l2loopback. Maîtrisée via Catch et DocuMind. |
| App mobile | **Flutter 3** (Android only) | Codebase unique, accès caméra/capteurs/notifs natif via plugins matures. iOS reporté en Phase 2 à cause des restrictions (clipboard, notifs, multicast). |
| Interface web | **Next.js 15** (App Router) | Maîtrisée, shadcn/ui + Tailwind pour vélocité UI ; Laravel Echo client pour Reverb. |
| Temps réel | **Laravel Reverb** | Inclus Laravel 11+, protocole Pusher supporté nativement par Flutter (`web_socket_channel`) et navigateur (Echo). |
| Crypto | **Noise IK + libsodium** | Standard moderne pour handshake mutuellement authentifié, plus simple que TLS+mTLS pour un pairing pair-à-pair sans CA. |
| Stockage local agent | **SQLite** | Suffisant pour un produit local mono-PC ; pas de serveur à gérer ; portable Windows/Linux ; fichier unique facile à backup. |
| Tunnel distant | **autossh + Nginx** (existant sahelstack.tech) + **coturn** | Pattern déjà déployé sur Laravel Ship. coturn ajouté pour permettre WebRTC en NAT-traversal. |

## Alternatives écartées

| Alternative | Raison du rejet |
|---|---|
| Tout en Rust (Tauri + axum) | Langue non maîtrisée. Risque d'écraser le calendrier. |
| Tout en Electron + Node | Empile une stack déjà couverte par Laravel + Next.js, sans gain net. |
| Native Android (Kotlin + Compose) | Double la charge UI pour un solo dev. |
| React Native | Moins maîtrisé que Flutter, écosystème plugins moins solide pour camera/notifs. |
| Firebase / Supabase pour le sync | Compte tiers obligatoire = violation du positionnement « zéro compte ». |
| WebRTC sans serveur TURN | Échec garanti hors LAN dans la moitié des cas (NAT symétrique). |

## Conséquences

✅ **Positives**
- Démarrage immédiat sur stacks maîtrisées.
- Réutilisation de l'infra VPS existante (Laravel Ship pattern).
- Couplage faible entre les 4 sous-projets (monorepo mais déployables séparément).

⚠️ **Négatives / dette acceptée**
- 4 langages à maintenir (PHP, Python, Dart, TypeScript) — coût cognitif réel.
- Le pont Python introduit une dépendance native par OS pour certains modules (v4l2loopback Linux, winrt Windows) → testabilité CI partielle.
- Pas d'iOS en Phase 1 → on accepte de perdre temporairement un segment d'utilisateurs.

## Suivi

- ADR-002 : choix mDNS Linux/Windows (à venir S1)
- ADR-003 : modèle de données complet (à venir S3)
- ADR-004 : architecture WebRTC (à venir S7)
