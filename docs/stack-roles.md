# 🧩 Linkup — Rôle de chaque langage & technologie

> Document de référence pour comprendre qui fait quoi dans l'architecture Linkup.

---

## Vue d'ensemble

```
┌─────────────────────────────────────────────────────────┐
│                    PC (Windows / Linux)                 │
│                                                         │
│  ┌──────────────┐   HTTP local    ┌──────────────────┐  │
│  │   Laravel    │◄───────────────►│  FastAPI Python  │  │
│  │   (PHP)      │   127.0.0.1     │  (pont système)  │  │
│  │              │   :8765         │                  │  │
│  │  • Pairing   │                 │  • Clipboard OS  │  │
│  │  • Routing   │                 │  • Terminal PTY  │  │
│  │  • Sécurité  │                 │  • yt-dlp        │  │
│  │  • SQLite    │                 │  • Whisper       │  │
│  │  • Jobs      │                 │  • ffmpeg        │  │
│  └──────┬───────┘                 │  • MPRIS / SMTC  │  │
│         │                         │  • v4l2loopback  │  │
│         │ WebSocket (Reverb)      └──────────────────┘  │
│    ┌────▼──────┐                                        │
│    │  Reverb   │  ← fil temps réel entre tous           │
│    └────┬──────┘                                        │
│         │                                               │
│  ┌──────▼───────┐                                       │
│  │   Next.js    │  ← interface web dans le navigateur   │
│  │ (TypeScript) │                                       │
│  └──────────────┘                                       │
└─────────────────┬───────────────────────────────────────┘
                  │ Wi-Fi local (ou tunnel VPS fallback)
                  │ WebSocket + WebRTC
┌─────────────────▼───────────────────────────────────────┐
│                 Téléphone Android                        │
│                                                         │
│              App Flutter (Dart)                         │
│         • Scan QR        • Caméra / Micro (WebRTC)      │
│         • 16 modules     • Notifications Android        │
│         • Transferts     • Service arrière-plan         │
└─────────────────────────────────────────────────────────┘
```

---

## 🐘 PHP — Laravel 12 (`agent/`)

**Rôle : Chef d'orchestre.**

PHP via Laravel est le cerveau du système côté PC. Il ne touche jamais directement au système d'exploitation — il coordonne les autres composants.

### Ce qu'il fait

| Responsabilité | Détail |
|---|---|
| **Appairage** | Génère le QR code, gère le handshake Noise IK, émet les tokens persistants |
| **Sécurité** | Liste blanche d'appareils, validation des tokens argon2id, audit log |
| **Routing des modules** | Reçoit un événement du tel → décide quoi appeler (bridge Python, Reverb, SQLite) |
| **WebSocket (Reverb)** | Héberge le serveur Reverb, crée les channels privés par device |
| **Base de données** | Gère les 15 tables SQLite (devices, transfers, clipboard_log, audit…) |
| **File de jobs** | Envoie les jobs lourds (yt-dlp, Whisper, ffmpeg) au worker Python |
| **API HTTP** | Expose les routes REST consommées par le dashboard Next.js |

### Ce qu'il ne fait PAS

- Accéder au clipboard de l'OS → délégué à Python
- Ouvrir un terminal PTY → délégué à Python
- Piloter le lecteur de médias → délégué à Python
- Traiter de la vidéo ou de l'audio → délégué à Python

### Analogie

> Laravel est le chef d'orchestre. Il donne les ordres, coordonne, garde l'état. Il ne joue pas lui-même les instruments.

---

## 🐍 Python — FastAPI (`bridge/`)

**Rôle : Technicien système.**

Python est le seul composant qui touche directement aux ressources de l'OS. Il tourne en parallèle de Laravel sur le même PC.

> **Mise à jour S1.J4 (cf. ADR-002) :** le bridge écoute sur `0.0.0.0:8765` (et non plus `127.0.0.1`) pour permettre (a) le heartbeat mDNS inter-PC sur le LAN et (b) le LAN sweep de découverte côté téléphone. **Seule la route `GET /health` est publique sans authentification** (elle ne révèle rien que mDNS ne broadcast déjà). Toutes les autres routes (`/system/info`, `/mdns/*`, futures `/clipboard`, `/transfer`, etc.) requièrent un token Bearer. Une fois le pairing établi, toute la communication métier passe par Laravel.

PHP est très limité pour accéder aux ressources bas-niveau. Python a des bibliothèques matures pour tout ça.

### Ce qu'il fait

| Module Linkup | Ce que Python fait concrètement | Lib utilisée |
|---|---|---|
| Presse-papier | Lire / écrire le clipboard de l'OS | `pyperclip` (Win), `xclip`/`wl-clipboard` (Linux) |
| Lien rapide | Ouvrir une URL dans le navigateur par défaut | `os.startfile()` (Win), `xdg-open` (Linux) |
| Transfert fichiers | Recevoir / envoyer des chunks binaires, vérifier les SHA-256 | `aiofiles` |
| Galerie distante | Générer des vignettes 200×200 JPEG | `Pillow` |
| Téléchargeur | Lancer yt-dlp, suivre la progression | `yt-dlp` |
| Transcription | Lancer Whisper, streamer le résultat | `faster-whisper` |
| Conversion média | Convertir des formats (mp4→mp3, webp→png…) | `ffmpeg-python` |
| Terminal distant | Ouvrir un vrai shell interactif (PTY) | `ptyprocess` (Linux), `pywinpty` (Win) |
| Contrôle média | Piloter le lecteur actif (Spotify, VLC…) | `dbus-python` MPRIS (Linux), `winrt` SMTC (Win) |
| Notifs miroir | Afficher une notification système côté PC | `plyer` / `notify-send` (Linux), `win10toast` (Win) |
| Caméra virtuelle | Pousser des frames vers le driver webcam virtuel | `pyvirtualcam` + `v4l2loopback` (Linux) |
| Télécommande slides | Simuler les touches flèches du clavier | `pyautogui` |
| Preview localhost | Faire un reverse proxy HTTP vers un port local | `httpx` async |
| Faire sonner | Trigger relayé par Reverb (pas de code Python direct ici) | — |

### Ce qu'il ne fait PAS

- Gérer la sécurité (tokens, appairage) → Laravel
- Persister des données en base → Laravel
- Communiquer directement avec le téléphone → Reverb

### Analogie

> Python est le technicien qui a les clés de la salle des machines. Laravel lui dit quoi faire, il l'exécute.

---

## 🎯 Dart — Flutter 3 (`mobile/`)

**Rôle : L'application sur le téléphone Android.**

Flutter est le framework de Google pour créer des apps mobiles natives. On écrit en Dart, et on obtient une vraie app Android (pas un site web dans une webview). Un seul code source couvre Android — et iOS en Phase 2.

### Ce qu'il fait

| Responsabilité | Détail | Lib Flutter |
|---|---|---|
| **Appairage** | Scanner le QR code, établir le handshake Noise IK | `mobile_scanner`, `flutter_sodium` |
| **Communication temps réel** | Connexion WebSocket à Reverb, recevoir/émettre des événements | `web_socket_channel` |
| **Transfert de fichiers** | Sélectionner des fichiers, envoyer en chunks avec progression | `file_picker`, `dio` |
| **Presse-papier** | Lire le presse-papier Android (action manuelle) | `super_clipboard` |
| **Caméra** | Capturer le flux vidéo et l'envoyer en WebRTC au PC | `flutter_webrtc` |
| **Micro** | Capturer l'audio et l'envoyer en WebRTC au PC | `flutter_webrtc` |
| **Notifications Android** | Capturer toutes les notifs et les relayer au PC | `notification_listener_service` |
| **Service arrière-plan** | Rester connecté même quand l'écran est éteint | `flutter_background_service` |
| **Faire sonner** | Jouer un son + vibrer sur ordre du PC | foreground service |
| **Galerie** | Accéder aux photos/vidéos Android | `photo_manager` |
| **UI des 16 modules** | Afficher les boutons, listes, terminal, galerie, flux vidéo | shadcn-like widgets |

### Ce qu'il ne fait PAS

- Traiter de la vidéo côté téléphone → le PC reçoit le flux WebRTC brut
- Gérer la base de données des appareils → Laravel
- Exécuter des commandes système côté tel → c'est le PC qui a le terminal

### Analogie

> Flutter est la télécommande intelligente. Elle donne les ordres et affiche les résultats, mais tout le traitement lourd se passe sur le PC.

---

## ⚡ TypeScript — Next.js 15 (`dashboard/`)

**Rôle : Interface web sur le PC, accessible depuis n'importe quel navigateur.**

Le dashboard est optionnel — le téléphone suffit pour tout utiliser. Mais il donne accès à Linkup sans installer l'app Android. C'est aussi là que se fait l'approbation des appareils (popup côté PC).

### Ce qu'il fait

| Page / Section | Contenu |
|---|---|
| `/pair` | Affiche le QR code d'appairage, popup d'approbation avec empreinte SHA-256 |
| `/devices` | Liste des appareils connectés (nom, statut, transport LAN/VPS, révoquer) |
| `/transfer` | Zone drag & drop pour envoyer des fichiers au téléphone |
| `/gallery` | Grille de vignettes des photos du téléphone, import sélectif |
| `/camera` | Flux webcam du téléphone dans le navigateur (WebRTC) |
| `/terminal` | Shell du PC embarqué (xterm.js), mode restreint/full |
| `/notifications` | Centre de notifs Android reçues, historique |
| `/media` | Artwork + titre + contrôles du lecteur actif sur le PC |
| `/localhost` | Exposer un port local du PC et générer l'URL + QR |
| `/observability` | Jobs en cours (yt-dlp, Whisper), logs, sessions actives |

### Librairies clés

| Lib | Rôle |
|---|---|
| `shadcn/ui` + Tailwind CSS | Composants UI accessibles et rapides à assembler |
| `Laravel Echo` | Client WebSocket pour se connecter à Reverb |
| `TanStack Query` | Fetching et cache des données serveur |
| `Zustand` | État global léger (device actif, transport mode…) |
| `xterm.js` | Émulateur de terminal dans le navigateur |
| `react-pdf` | Affichage PDF pour la télécommande slides |

### Ce qu'il ne fait PAS

- Appeler directement le bridge Python → passe toujours par Laravel
- Stocker des données → lecture seule via API Laravel
- Remplacer l'app mobile → complément, pas substitut

### Analogie

> Next.js est le tableau de bord. Un écran de contrôle lisible par un humain, branché sur Laravel via Reverb et l'API HTTP.

---

## 🔌 Reverb — WebSocket (`inclus dans Laravel`)

**Rôle : Le fil électrique temps réel entre tous les composants.**

Reverb n'est pas un langage — c'est un serveur WebSocket qui tourne à côté de Laravel. Il implémente le protocole Pusher, ce qui permet à Flutter (`web_socket_channel`) et au navigateur (`Laravel Echo`) de s'y connecter nativement.

### Ce qu'il transporte

| Événement | Émis par | Reçu par | Effet |
|---|---|---|---|
| `DevicePaired` | Laravel | Flutter + Dashboard | Active les modules |
| `ClipboardUpdated` | Flutter ou Laravel | L'autre côté | Sync presse-papier |
| `LinkOpenRequested` | Flutter | Laravel → Python | Ouvre l'URL |
| `NotificationMirrored` | Flutter | Laravel → Python | Affiche notif PC |
| `FileTransferRequested` | Flutter ou PC | L'autre | Ouvre canal HTTP |
| `WebRtcOffer/Answer/Ice` | Flutter ou navigateur | L'autre | Signaling WebRTC |
| `MediaControlIssued` | Flutter | Laravel → Python | Play/pause/volume |
| `TerminalSessionRequested` | Flutter | Laravel → Python | Ouvre PTY |
| `TranscriptionJobQueued` | Flutter | Laravel (job) | Lance Whisper |
| `DownloadJobQueued` | Flutter | Laravel (job) | Lance yt-dlp |

### Ce qu'il ne fait PAS

- Transporter les gros fichiers → un canal HTTP dédié (FastAPI) gère ça
- Transporter la vidéo/audio → WebRTC s'en charge directement
- Authentifier les messages → les channels sont privés (token par device)

### Analogie

> Reverb est le système nerveux. Tout passe par lui pour les petits messages rapides. Pour les gros volumes (fichiers, vidéo), on ouvre un tuyau dédié.

---

## Résumé en une ligne

| Technologie | Langage | Rôle en une ligne |
|---|---|---|
| **Laravel 12** | PHP | Chef d'orchestre : pairing, sécurité, routing, base de données |
| **FastAPI** | Python | Technicien OS : clipboard, terminal, médias, webcam, yt-dlp, Whisper |
| **Flutter 3** | Dart | App téléphone : interface, caméra, micro, notifications, transferts |
| **Next.js 15** | TypeScript | Dashboard web PC : approbation, galerie, terminal web, monitoring |
| **Reverb** | — | Fil temps réel : tous les événements entre Laravel, Flutter et Next.js |

---

## Règle d'or

> **Chaque composant fait ce qu'il fait le mieux, et ne déborde pas sur le rôle des autres.**
>
> — PHP orchestre. Python touche l'OS. Dart pilote le téléphone. TypeScript affiche. Reverb relie.
