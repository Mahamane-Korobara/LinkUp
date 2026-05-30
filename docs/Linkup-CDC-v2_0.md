# 🔗 Linkup
### *Ton téléphone et ton PC, reliés en un scan*

| | |
|---|---|
| **Document** | Cahier des Charges Technique |
| **Version** | 2.0 — Hub Cross-Device complet |
| **Date** | Mai 2026 |
| **Auteur** | Mahamane Korobara |
| **Type de produit** | Application de pont sans-fil PC ↔ téléphone |
| **Stack Backend (agent PC)** | Laravel 12 (PHP 8.4) + Reverb |
| **Pont système PC** | Agent Python (FastAPI local) piloté par Laravel |
| **App mobile** | Flutter 3 — **Android uniquement** |
| **Interface web** | Next.js 15 (dashboard + outils navigateur) |
| **OS PC supportés** | **Windows 10/11** + **Linux (Ubuntu/Debian/Fedora)** |
| **Connexion** | Wi-Fi local (mDNS) + tunnel VPS Hostinger en fallback |
| **Appairage** | QR code à usage unique, token persistant ensuite |
| **Comptes / câbles** | Aucun compte tiers, aucun câble |
| **Cible exécution** | Local + VPS perso + soutenance |
| **Budget total** | 0 € incrémental (VPS sahelstack.tech déjà payé, sideload Android, distribution open source) |
| **Statut** | Spécification finalisée — démarrage immédiat |

---

## 📝 Pourquoi Linkup

**Le constat :** transférer un fichier, un lien ou un bout de texte entre son téléphone et son PC reste pénible — câble, WhatsApp Web, email à soi-même, clé USB. Les solutions existantes (KDE Connect, AirDroid, Phone Link) sont soit trop techniques, soit liées à un compte/serveur tiers, soit limitées à un OS.

**La réponse :** un hub unique. On scanne un QR une fois, et **tous les outils du quotidien** (fichiers, presse-papier, médias, caméra, micro, contrôle PC, terminal, notifs, galerie, télécommande, téléchargeur, transcription, conversion, preview, scanner) deviennent disponibles, sans câble et sans compte.

---

## ⚠️ Limites assumées de la v2.0

- **iOS hors scope** : Apple restreint trop l'accès aux notifs/clipboard/multicast pour offrir une expérience cohérente. iOS arrivera en Phase 2 avec un périmètre dégradé connu.
- **macOS hors scope** : pas de matériel de test sous la main ; CoreMediaIO (webcam virtuelle) et MediaRemote (contrôle média) demandent une expertise spécifique. Reporté en Phase 2.
- **Webcam virtuelle système** : livrée sur Linux (v4l2loopback) en Phase 1. Sur Windows, l'utilisateur passe par OBS Virtual Camera en wrapper ; un vrai filtre DirectShow viendra en Phase 2.
- **Identification audio (Shazam-like)** : reportée en Phase 2 (dépend d'un service tiers payant ou d'un modèle ML lourd à intégrer).
- **Latence en fallback VPS** : hors Wi-Fi local, vidéo/audio passent par coturn → qualité dégradée acceptée pour fichiers/texte, vidéo/audio limités au LAN.

---

## PARTIE 1 • LE PROJET

# 1. Le Problème & La Vision

## 1.1 Des situations que tout le monde vit

**📖 Scène 1 — Le fichier prisonnier du téléphone**
Mahamane vient de prendre 12 photos d'un tableau blanc avec son téléphone. De retour à son PC, il veut les intégrer dans un document. Pas de câble. Il finit par se les envoyer par WhatsApp à lui-même, perd la qualité, copie-colle une par une.

**📖 Scène 2 — Le lien qu'on retape à la main**
Fatou trouve un article intéressant sur son téléphone et veut l'ouvrir sur son grand écran. Elle finit par retaper l'URL à la main, en faisant deux fautes de frappe.

**📖 Scène 3 — La réunion sans webcam**
Karim doit faire un appel vidéo depuis son PC fixe, sa webcam est cassée. Son téléphone a une excellente caméra. Il ne sait pas comment l'utiliser comme webcam sans installer trois logiciels douteux et créer un compte.

**📖 Scène 4 — Le développeur en déplacement**
Aïcha déploie depuis son laptop dans le train. Son téléphone reçoit une OTP à chaque login serveur. Elle veut copier l'OTP du tel au PC instantanément, taper une commande sudo dans un terminal distant sur son serveur préview localhost, et voir les logs s'afficher sur son téléphone.

**📖 Scène 5 — La présentation orale**
Yacine présente un PDF en amphi. Il veut tourner les slides depuis son téléphone, sans pointeur USB. Et capter le son ambiant via le micro du téléphone (mieux placé) pour la vidéo enregistrée.

## 1.2 La vision de Linkup

**💡 Linkup en une phrase :**
Tu scannes un QR code une seule fois — ton téléphone et ton PC sont reliés, et une boîte à outils complète (15 modules) devient disponible des deux côtés, sans câble, sans compte, sans serveur tiers.

| Problème actuel | Ce que Linkup apporte |
|---|---|
| Câble ou clé USB pour transférer un fichier | Transfert sans fil instantané dans les deux sens |
| S'envoyer des liens/textes par WhatsApp à soi-même | Presse-papier et liens partagés en un tap |
| Photos du téléphone inaccessibles sur le PC | Galerie du tel parcourue depuis le PC |
| Webcam ou micro PC absents/cassés | Caméra et micro du téléphone réutilisés |
| Solutions liées à un compte ou un cloud tiers | Zéro compte, données sur ton réseau ou ton VPS |
| Outils éparpillés (1 app par fonction) | Une seule app, **15 outils** regroupés |
| Télécharger une vidéo, transcrire un audio, convertir un format : 3 apps | Tout depuis le téléphone, traitement sur le PC |
| Contrôler un slide ou un media player en présentation | Télécommande native depuis le tel |

# 2. Les Utilisateurs

## 2.1 Qui utilise Linkup ?

| Profil | Besoin principal | Modules clés |
|---|---|---|
| 👨‍💻 Développeur | Envoyer logs, liens, OTP, commandes entre tel et PC | Terminal, snippets, preview localhost, presse-papier |
| 🎓 Étudiant | Récupérer photos de cours, partager fichiers, transcrire un cours enregistré | Fichiers, galerie, presse-papier, transcription |
| 📊 Pro / bureau | Webcam d'appoint, transfert de docs, notifs centralisées | Caméra, micro, fichiers, notifs miroir |
| 🎬 Créateur de contenu | Télécharger des vidéos, convertir un format, scanner un QR de set | Téléchargeur média, conversion, scanner |
| 👨‍🏫 Présentateur | Tourner les slides à distance, micro déporté | Télécommande slides, micro |
| 👨‍👩‍👧 Utilisateur lambda | Transférer photos, ouvrir un lien sur grand écran, retrouver son tel | Fichiers, liens, faire sonner le tel |

## 2.2 Deux appareils, un seul système

| Appareil | Rôle | Ce qui tourne dessus |
|---|---|---|
| 🖥️ PC (hôte) — Windows ou Linux | Héberge l'agent, exécute les actions système | Agent Laravel + Reverb + pont Python |
| 📱 Téléphone Android (client) | Pilote, scanne le QR, déclenche les outils | App Flutter |
| 🌐 Navigateur (optionnel) | Accès rapide à certains outils sans installer l'app | Dashboard Next.js |

# 3. La Boîte à Outils — 15 Modules Core

**🎯 Principe de regroupement :** Linkup n'invente pas une fonction unique : c'est l'agrégateur de tous les petits ponts utiles entre téléphone et PC. Chaque module est indépendant et activable depuis les réglages.

## 3.1 Fichiers & Contenu (4 modules)

| Module | Description | OS PC |
|---|---|---|
| 📤 Transfert de fichiers | Envoyer/recevoir tout fichier PC ↔ tel, multi-fichiers, reprise sur coupure | Win + Linux |
| 📋 Presse-papier partagé | Copier sur un appareil → coller sur l'autre, avec confirmation (anti-spam OS) | Win + Linux |
| 🔗 Lien rapide | Envoyer une URL → s'ouvre dans le navigateur de l'autre appareil | Win + Linux |
| 🖼️ Galerie distante | Parcourir et importer les photos/vidéos du tel depuis le PC, pagination + cache vignettes | Win + Linux |

## 3.2 Médias (3 modules in-scope + 1 en Phase 2)

| Module | Description | OS PC |
|---|---|---|
| ⬇️ Téléchargeur (yt-dlp) | Envoyer une URL vidéo depuis le tel → yt-dlp télécharge sur le PC | Win + Linux |
| 🎙️ Transcription | Audio enregistré sur le tel → transcrit sur le PC (Whisper `base`, CPU OK) | Win + Linux |
| 🔄 Conversion média | Envoyer un fichier → choisir le format de sortie (ffmpeg) | Win + Linux |
| 🎵 *Identification audio* | *Identifier un son ambiant capté par le tel — **Phase 2*** | *Phase 2* |

## 3.3 Caméra & Audio (4 modules)

| Module | Description | OS PC |
|---|---|---|
| 📷 Caméra du téléphone | Flux caméra du tel affiché/utilisé sur le PC (WebRTC), navigateur **et** webcam virtuelle | Win (via OBS VC) + Linux (v4l2loopback) |
| 🎤 Micro du téléphone | Entrée audio du tel disponible côté PC (WebRTC) | Win + Linux |
| 📊 Télécommande slides | Contrôler une présentation PDF/PPT depuis le tel (simulation clavier) | Win + Linux |
| 🔳 Scanner QR/code-barre | Scanner avec le tel → résultat affiché sur le PC (texte, URL ouvrable) | Win + Linux |

## 3.4 Contrôle PC & Outils dev (5 modules)

| Module | Description | OS PC |
|---|---|---|
| 🔔 Notifs miroir | Notifications Android affichées sur le PC (NotificationListenerService) | Win + Linux |
| ⌨️ Terminal distant | Accès au shell du PC depuis le tel, **shell restreint configurable**, opt-in PC | Win (PowerShell) + Linux (bash) |
| ▶️ Contrôle média | Play/pause/volume du PC pilotés depuis le tel (MPRIS Linux, SMTC Windows) | Win + Linux |
| 📍 Faire sonner le tel | Localiser un téléphone perdu depuis le PC, foreground service Android | Win + Linux |
| 🌍 Preview localhost | Exposer un port local du PC → ouvrable sur le tel via QR (reverse proxy L7) | Win + Linux |

**Total Phase 1 : 16 modules** (4 + 3 + 4 + 5).

# 4. Connexion & Appairage

**💡 Pourquoi le QR code :** Le QR encode l'adresse de l'agent PC, un token à usage unique et la **clé publique** de l'agent. Le téléphone le scanne, vérifie la clé, échange une clé éphémère via handshake, et la liaison est établie. Aucune saisie manuelle d'IP, aucun compte. Après le premier appairage, le token persistant reconnecte automatiquement les appareils connus.

## 4.1 Le flux d'appairage

| Étape | Ce qui se passe | Technologie |
|---|---|---|
| 1. Lancement agent PC | L'agent démarre, génère une paire de clés Ed25519 et un QR | Laravel + Reverb + libsodium |
| 2. Découverte locale | L'agent s'annonce sur le réseau Wi-Fi (`_linkup._tcp`) | mDNS / Bonjour |
| 2bis. Fallback découverte | UI dashboard affiche IP + port + QR avec ces infos | (mDNS-free) |
| 3. Scan QR | Le tel lit `linkup://<ip>:<port>?pk=<ed25519_pub>&otp=<token60s>` | Flutter mobile_scanner |
| 4. Handshake | Protocole **Noise IK** (libsodium) : authentification mutuelle + clé de session | WebSocket + Noise |
| 5. Validation user | Côté PC, popup « Approuver l'appareil X ? » avec empreinte SHA-256 | Dashboard Next.js |
| 6. Connexion établie | Channel privé Reverb créé, modules disponibles | Reverb channels |
| 7. Reconnexion auto | Token persistant (rotation 30j) + clé pinning | Token stocké hashé argon2 |

## 4.2 Saisie manuelle (fallback mDNS)

Si mDNS échoue (Wi-Fi entreprise, Livebox isolée), l'utilisateur peut saisir manuellement `IP:port` ou scanner un QR affiché dans le dashboard PC qui contient les mêmes infos.

## 4.2 bis Présence agent sur le LAN

Le LAN discovery ne doit pas seulement trouver un agent, il doit aussi savoir s'il est encore vivant.

**Mais tu n'as pas encore le vrai modèle de présence :**

- pas de heartbeat applicatif,
- pas de TTL d'expiration,
- pas de purge automatique des fantômes.

**Modèle retenu pour Phase 1 :**

- le bridge expose `GET /health` avec `status=alive`, `agent_id` et `timestamp`
- le scanner mDNS met à jour `last_seen` quand un agent répond encore sur `/health`
- `/mdns/services` ne retourne que les agents dont `last_seen` reste dans une fenêtre TTL de 15 secondes
- au shutdown propre, le service mDNS est désenregistré explicitement

## 4.3 Les deux modes de transport

| Mode | Quand | Caractéristiques |
|---|---|---|
| **Wi-Fi local** (prioritaire) | Les deux appareils sur le même réseau | Rapide, direct, aucune donnée hors LAN |
| **Tunnel VPS** (fallback) | Appareils sur des réseaux différents | Relais via VPS Hostinger (Reverb relay + coturn TURN), chiffré, plus lent |

**✅ Réutilisation de l'infra existante :** Le tunnel fallback réutilise le pattern de Laravel Ship (reverse SSH tunnel autossh + systemd). Le serveur **coturn** sur le VPS est ajouté pour permettre WebRTC en NAT-traversal.

---

## PARTIE 2 • CHOIX TECHNIQUES JUSTIFIÉS

# 5. Architecture Globale

**✅ Règle d'or :** Linkup est un produit solo. Pas de microservices. Un agent Laravel modulaire sur le PC, un pont Python pour les fonctions système que PHP ne fait pas bien, une app Flutter Android cliente. **Chaque module = un channel Reverb + un service Laravel partagé.**

## 5.1 Composants

| Composant | Responsabilité |
|---|---|
| **Agent Laravel** (PC) | Cerveau : appairage, routage modules, broadcasting Reverb, sécurité, persistance SQLite |
| **Pont Python** (PC) | Mains système : clipboard OS, processus, caméra v4l2loopback, yt-dlp, Whisper, ffmpeg, PTY, MPRIS/SMTC, notifs OS |
| **App Flutter Android** | Client : scan QR, UI des 16 modules, caméra/micro, capteurs, NotificationListenerService |
| **Dashboard Next.js** | Vue navigateur : gestion appareils, approbation pairing, outils accessibles sans app |
| **Reverb** (WebSocket) | Canal temps réel bidirectionnel entre tous les acteurs (signaling) |
| **Tunnel VPS** | Relais chiffré (Reverb relay + coturn TURN) quand les appareils ne sont pas sur le même LAN |

**Note d'implémentation S1 :** le plan cible un `MdnsAnnouncer` côté Laravel. Le bas niveau mDNS reste porté par le bridge Python pour gérer Zeroconf multi-OS, mais Laravel redevient la façade métier via un service `MdnsAnnouncer` qui interroge le bridge local.

## 5.2 Services partagés Laravel (anti-duplication)

Pour éviter la duplication entre 16 modules :

- `DeviceRegistryService` : pairing, tokens, approbation, liste blanche
- `TransferService` : chunks binaires, reprise, checksum (utilisé par fichiers + galerie)
- `ClipboardService` : sync clipboard, anti-boucle, historique (utilisé par presse-papier + lien)
- `MediaStreamService` : signaling WebRTC, peer connections (utilisé par caméra + micro)
- `OsBridgeService` : pont vers FastAPI Python, normalisation par-OS (utilisé par 8 modules)
- `SecurityAuditService` : log des actions sensibles, alertes (utilisé par terminal + pairing)

# 6. Agent PC — Laravel 12 + Pont Python

**🎯 Pourquoi un hybride Laravel + Python :**
**Laravel :** terrain maîtrisé — Reverb pour le temps réel, structure modulaire, sécurité, déjà utilisé sur tous tes projets. C'est l'orchestrateur.
**Python :** indispensable pour ce que PHP fait mal — accès caméra/audio, clipboard système multi-OS, yt-dlp, Whisper, ffmpeg, PTY. Un petit serveur FastAPI local que Laravel appelle. C'est aussi le terrain de Catch et DocuMind, déjà explorés.

| Option | Pour Linkup | Verdict |
|---|---|---|
| Laravel 12 (orchestrateur) | Reverb natif, modulaire, maîtrisé | ✅ RETENU |
| Pont Python FastAPI (système) | Clipboard OS, caméra v4l2loopback, yt-dlp, Whisper, ffmpeg, PTY | ✅ RETENU |
| Tout en Rust/Go | Idéal techniquement mais langages non maîtrisés | ❌ Écarté |
| Tout en Electron/Node | Lourd, et duplique ce que Laravel fait déjà mieux | ❌ Écarté |

# 7. App Mobile — Flutter 3 (Android)

| Option | Pour Linkup | Verdict |
|---|---|---|
| Flutter 3 (Android) | Codebase unique, terrain maîtrisé, accès caméra/capteurs/notifs natif | ✅ RETENU |
| React Native | Possible mais moins maîtrisé | ❌ Écarté |
| Native Android Kotlin | Charge de travail UI doublée | ❌ Écarté |
| iOS | Restrictions multicast/clipboard/notifs trop fortes | ⏭️ Phase 2 |

## 7.1 Librairies Flutter clés

| Librairie | Rôle |
|---|---|
| `mobile_scanner` | Scan du QR d'appairage |
| `web_socket_channel` | Connexion temps réel à Reverb (protocole Pusher) |
| `flutter_webrtc` | Flux caméra/micro du téléphone vers le PC |
| `file_picker` + `dio` | Sélection et transfert de fichiers chunkés |
| `super_clipboard` | Lecture/écriture du presse-papier (en mode manuel, cf. limitation Android 10+) |
| `flutter_local_notifications` | Affichage et capture des notifications |
| `notification_listener_service` | Capture des notifs Android pour le module miroir |
| `flutter_background_service` | Foreground service pour reconnexion + faire sonner |
| `pdfx` ou `photo_view` | Affichage des slides reçus pour la télécommande |
| `flutter_pty` ou WebSocket terminal natif | Affichage shell du PC |
| `permission_handler` | Permissions runtime Android 13+ |

## 7.2 Permissions Android requises

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
                 tools:ignore="ProtectedPermissions"/>
```

# 8. Interface Web — Next.js 15

| Option | Pour Linkup | Verdict |
|---|---|---|
| Next.js 15 (App Router) | Dashboard appareils + outils navigateur, shadcn/ui, maîtrisé | ✅ RETENU |
| Inertia + Laravel | Limite le temps réel et l'UI avancée | ❌ Écarté |

## 8.1 Librairies UI

| Librairie | Rôle |
|---|---|
| shadcn/ui + Tailwind CSS | Composants accessibles |
| Laravel Echo (client) | Connexion temps réel à Reverb |
| TanStack Query | Fetching et caching server state |
| Zustand | État global léger |
| `qrcode.react` | Génération du QR d'appairage côté dashboard |
| `react-pdf` | Aperçu PDF pour la télécommande slides côté PC |
| `xterm.js` | Terminal embarqué dans le dashboard (pour le module terminal) |

# 9. Temps Réel & Transport

**✅ Reverb comme colonne de signaling, transports dédiés pour le reste.**

## 9.1 Matrice module × transport

| Module | Transport | Justification |
|---|---|---|
| Pairing | WebSocket (Noise IK) | Auth mutuelle initiale |
| Clipboard | Reverb event | Petits payloads, faible fréquence |
| Lien rapide | Reverb event | URL = < 2 Ko |
| Notifs miroir | Reverb event | Push, payload < 1 Ko |
| Faire sonner | Reverb event | Trigger simple |
| Télécommande slides | Reverb event | Commandes clavier, latence OK |
| Contrôle média | Reverb event | Play/pause/volume |
| Scanner QR | Reverb event | Texte court |
| **Transfert fichiers** | **HTTP chunked dédié** (FastAPI) | Gros volumes, reprise, hors WebSocket |
| **Galerie distante** | **HTTP paginé** (vignettes) + transfert sélectif | Volumes potentiellement gros |
| **Caméra** | **WebRTC** (signaling via Reverb) | Vidéo SRTP, NAT traversal via coturn |
| **Micro** | **WebRTC** (mux dans la même PeerConnection que caméra si actives) | Audio Opus SRTP |
| **Terminal distant** | **WebSocket binaire dédié** | Streaming PTY, latence critique |
| **Preview localhost** | **HTTP reverse proxy L7** (tunnel) | URL accessible navigateur |
| **Téléchargeur yt-dlp** | Reverb event (trigger) + HTTP (résultat) | Lance le job, livre le fichier |
| **Transcription Whisper** | Reverb event (trigger) + HTTP (résultat) | Lance le job, livre le texte |
| **Conversion média** | Reverb event (trigger) + HTTP (résultat) | Lance le job, livre le fichier |

## 9.2 Événements Reverb principaux

| Événement | Émis par | Effet |
|---|---|---|
| `DevicePaired` | Agent PC | Active les modules des deux côtés |
| `DeviceApproved` | Dashboard PC | Confirme l'autorisation utilisateur |
| `FileTransferRequested` | Tel ou PC | Ouvre un canal HTTP de transfert |
| `ClipboardUpdated` | L'un ou l'autre | Synchronise le presse-papier |
| `LinkOpenRequested` | Tel ou PC | Ouvre l'URL dans le navigateur cible |
| `CameraStreamStarted` | Tel | Démarre la PeerConnection WebRTC |
| `MicStreamStarted` | Tel | Ajoute la piste audio à la PeerConnection |
| `NotificationMirrored` | Tel | Affiche notif côté PC |
| `TerminalSessionRequested` | Tel | Demande ouverture PTY (avec confirm PC) |
| `MediaControlIssued` | Tel | Pilote MPRIS/SMTC |
| `RingPhoneRequested` | PC | Sonne le tel via foreground service |
| `LocalhostExposed` | PC | Crée le tunnel L7 + retourne l'URL publique |
| `TranscriptionJobQueued` | Tel | Lance Whisper |
| `DownloadJobQueued` | Tel | Lance yt-dlp |
| `ConvertJobQueued` | Tel ou PC | Lance ffmpeg |
| `QrScanResult` | Tel | Pousse le contenu scanné vers le PC |
| `SlideCommandIssued` | Tel | next/prev/start/stop |

# 10. Sécurité de la Liaison

## 10.1 Crypto

- **Identité agent PC :** paire **Ed25519** générée à l'install, conservée en local (`~/.linkup/keys/`), jamais transmise.
- **Handshake :** protocole **Noise IK** via `libsodium` (PHP `ext-sodium` + `flutter_sodium`), authentifie mutuellement et établit une clé de session XChaCha20-Poly1305.
- **Token persistant :** émis post-handshake, durée 30 jours, **rotation à chaque reconnexion réussie**, stocké hashé **argon2id** côté agent.
- **QR code :** TTL **60 secondes**, OTP à usage unique, contient la clé publique Ed25519 pour pinning à la première connexion.
- **TLS local :** non requis car Noise IK couvre déjà le chiffrement. Pour le dashboard web local, certificat auto-signé épinglé via le QR (option avancée).
- **Tunnel VPS :** TLS (Let's Encrypt sur `sahelstack.tech`) + token Bearer **par-device** (jamais partagé).

## 10.2 Contrôle d'accès

- **Liste blanche d'appareils :** seuls les appareils appairés ET approuvés via popup PC peuvent se reconnecter.
- **Empreinte affichée :** SHA-256 tronqué (8 chars) de la clé publique du tel affiché côté PC lors de l'approbation.
- **Révocation :** un click depuis le dashboard supprime le device, invalide tous ses tokens, ferme ses channels.
- **Anti-rejeu :** chaque message contient un nonce + timestamp ; messages > 30s rejetés.

## 10.3 Confirmation des actions sensibles

- **Terminal distant :** opt-in **côté PC** (désactivé par défaut), confirmation à l'ouverture de session, log de chaque commande.
- **Shell restreint configurable :** allow-list par défaut (`ls`, `pwd`, `git`, `php artisan`, `npm`, `pnpm`, `docker ps`…) ; mode full shell sur opt-in explicite.
- **Faire sonner :** confirmation côté PC avant émission.
- **Galerie :** consentement Android (permission MediaStore) + indicateur visible quand le PC parcourt activement.

## 10.4 Anti-boucle clipboard

Chaque update porte un `(hash, origin_device_id, timestamp)`. L'agent rejette une réémission si :
- hash identique reçu dans les **2 dernières secondes**, ou
- `origin_device_id` correspond à un device de la session.

# 11. (Réservé — voir Partie 4)

---

## PARTIE 3 • PLAN DE DÉVELOPPEMENT

**🔄 Philosophie :** Build → Test → Fix chaque semaine. Un module n'est pas "fait" tant qu'il ne marche pas de bout en bout (tel → PC → tel) sur **vrai matériel Android + Windows + Linux**. Tests Pest dès la première semaine, pas reportés.

# 12. Vue d'ensemble

## 12.1 Planning Phase 1 (25 semaines • ≈ 6 mois)

Regroupement par **briques techniques partagées** plutôt que par module isolé, pour mutualiser le code.

| Brique | Sem. | Modules livrés | Livrable |
|---|---|---|---|
| **B1 — Noyau & pairing** | S1-S3 | Pairing QR, Noise IK, mDNS, Reverb channels, modèle de données complet, dashboard pairing | Tel et PC appairés en < 5s sur LAN |
| **B2 — Transferts & clipboard** | S4-S6 | Transfert fichiers, presse-papier, lien rapide, galerie distante | 4 modules « fichiers & contenu » fonctionnels |
| **B3 — WebRTC caméra & micro** | S7-S10 | Caméra navigateur, micro, signaling WebRTC, indicateurs qualité, gestion permissions | Flux vidéo + audio fluide sur LAN |
| **B4 — Pont OS Python (5 modules)** | S11-S14 | Terminal PTY restreint, contrôle média MPRIS/SMTC, notifs miroir, preview localhost, faire sonner | Tous modules « contrôle PC » fonctionnels Win + Linux |
| **B5 — Médias lourds** | S15-S17 | Téléchargeur yt-dlp, transcription Whisper `base`, conversion ffmpeg, scanner QR, télécommande slides | 5 derniers modules fonctionnels |
| **B6 — Webcam virtuelle système** | S18-S19 | v4l2loopback bridge Linux + intégration OBS Virtual Camera Windows | Tel reconnu comme webcam système |
| **B7 — Fallback tunnel VPS + coturn** | S20-S21 | Reverse SSH tunnel, relais Reverb, coturn TURN, bascule auto LAN ↔ tunnel | Tout fonctionne hors LAN (vidéo dégradée acceptée) |
| **B8 — Tests, sécurité, packaging** | S22-S24 | Tests Pest exhaustifs, audit sécu, installateur Linux (script bash + systemd), installateur Windows (Inno Setup), APK signé | Produit installable par un non-tech |
| **B9 — Recette + soutenance** | S25 | README complet, vidéo démo, slides, backup hotspot 4G | Démo des 16 modules prête |

## 12.2 Phase 2 (post-livraison, périmètre dégradé connu)

| Module | Limitation |
|---|---|
| 🎵 Identification audio | Intégration AcoustID ou Shazam API (clé tierce) |
| iOS | Modules clipboard/notifs en mode manuel, mDNS conditionnel |
| macOS | Webcam virtuelle CoreMediaIO, contrôle média MediaRemote |
| Webcam virtuelle Windows native | Filtre DirectShow (remplace le wrapper OBS) |

# 13. Briques détaillées (Phase 1)

## 🏗️ B1 — Noyau & pairing (S1-S3)

**🎯 Objectif :** Les 3 briques (agent Laravel, pont Python, app Flutter) démarrent, se découvrent, et un téléphone s'appaire en moins de 5 secondes avec approbation côté PC.

| ⚙️ Backend (Laravel + Python) | 📱 Frontend (Flutter / Next.js) |
|---|---|
| Monorepo : `agent/` (Laravel) + `bridge/` (Python) + `mobile/` (Flutter) + `dashboard/` (Next.js) | Scaffold Flutter 3 + structure 16 modules en tabs |
| Agent Laravel + Reverb : `php artisan reverb:start` | Scaffold Next.js 15 + Tailwind + shadcn/ui |
| Pont Python FastAPI : endpoints `/health`, `/clipboard`, `/notify` | Écran d'accueil + état de connexion |
| Découverte mDNS : agent s'annonce `_linkup._tcp` | Écran scan QR (`mobile_scanner`) |
| Génération QR (Ed25519 pub + OTP 60s) | Page dashboard `/devices` |
| Handshake Noise IK via `libsodium` | Écran « appareil connecté » + statut |
| Liste blanche d'appareils en SQLite | Dashboard : QR affiché + popup approbation par empreinte SHA-256 |
| Channel privé Reverb par device | Reconnexion auto des devices connus |
| Modèle de données complet créé (cf. §15) | Saisie manuelle d'IP en fallback mDNS |
| **Tests Pest dès S1** : auth, pairing, rejet QR expiré | **Test :** scan → connecté + approuvé en < 5s |

## 📤 B2 — Transferts & clipboard (S4-S6)

**🎯 Objectif :** 4 modules « fichiers & contenu » fonctionnels, services Laravel partagés en place.

| ⚙️ Backend (Laravel + Python) | 📱 Frontend (Flutter / Next.js) |
|---|---|
| `TransferService` : chunks 1 Mo, SHA-256 par chunk, reprise sur coupure | Sélecteur fichiers (`file_picker`) sur tel |
| Endpoint HTTP FastAPI `/transfer/upload` + `/transfer/download` | Drag & drop sur dashboard PC |
| Table `file_chunks` pour reprise | Barre de progression temps réel |
| Pont Python : R/W clipboard OS (Win clip + xclip/wl-clipboard Linux) | Bouton « envoyer presse-papier » manuel (cf. limitation Android 10+) |
| `ClipboardService` + anti-boucle (hash+TTL 2s) | Bouton « ouvrir ce lien sur le PC » |
| Événement `LinkOpenRequested` → ouverture navigateur | Affichage dernier contenu reçu |
| Galerie : endpoint paginé `/gallery?page=N`, vignettes 200×200 | Liste historique 50 partages |
| Cache vignettes PC : `storage/gallery_cache/<device_id>/` | UI galerie : grille de vignettes, sélection multiple, import |
| **Tests Pest :** reprise transfert après kill, anti-boucle clipboard | **Test :** 10 fichiers tel→PC, copie texte, import 20 photos |

## 📷 B3 — WebRTC caméra & micro (S7-S10)

**🎯 Objectif :** Flux vidéo + audio fluide entre tel et PC, navigateur d'abord.

| ⚙️ Backend (Laravel + Python) | 📱 Frontend (Flutter / Next.js) |
|---|---|
| `MediaStreamService` : signaling WebRTC via Reverb | Capture caméra + micro (`flutter_webrtc`) |
| Génération offer/answer/ICE | Choix caméra avant/arrière, choix micro |
| Configuration STUN public + TURN local (Phase 1 LAN) | Affichage du flux dans dashboard |
| Mux vidéo+audio dans une PeerConnection unique | Boutons changer caméra, mute micro, stop |
| Mesure RTT/jitter pour indicateur qualité | Indicateur qualité connexion |
| **Tests :** auth signaling, refus stream sans approval | **Test :** flux fluide LAN, latence < 300 ms |

## ⌨️ B4 — Pont OS Python : 5 modules contrôle PC (S11-S14)

**🎯 Objectif :** Terminal, contrôle média, notifs miroir, preview localhost, faire sonner.

| ⚙️ Backend (Laravel + Python) | 📱 Frontend (Flutter / Next.js) |
|---|---|
| **Terminal** : WebSocket binaire `/term/ws`, `ptyprocess` Linux / `pywinpty` Windows | UI terminal Flutter (vt100 minimal) + dashboard `xterm.js` |
| Shell restreint configurable, allow-list par défaut | Toggle « shell restreint / full » dans réglages PC |
| Log chaque commande dans `security_audit` | |
| **Contrôle média** : MPRIS Linux (`dbus-python`), SMTC Windows (`winrt-Windows.Media.Control`) | UI : artwork + titre + play/pause/next/prev/volume |
| **Notifs miroir** : `notification_listener_service` Flutter → Reverb → Plyer (PC Linux) / win10toast (PC Windows) | UI notifs côté dashboard avec actions |
| **Preview localhost** : reverse proxy FastAPI (`httpx` async) | UI : input port + bouton expose, affiche URL + QR généré |
| **Faire sonner** : foreground service Flutter, son boucle + vibration | Bouton dashboard, confirmation côté PC |
| **Tests :** PTY échappement ANSI, refus commande hors allow-list | **Test :** terminal réel sur Win + Linux, notif WhatsApp affichée PC |

## ⬇️ B5 — Médias lourds + slides + scanner (S15-S17)

**🎯 Objectif :** Téléchargeur, transcription, conversion, télécommande slides, scanner QR.

| ⚙️ Backend (Laravel + Python) | 📱 Frontend (Flutter / Next.js) |
|---|---|
| **yt-dlp** : queue Laravel + worker Python, destination `~/Linkup/Downloads/` | UI : paste URL + choix qualité + progress |
| Cron hebdo `pip install -U yt-dlp` | Liste téléchargements en cours / historique |
| **Whisper** : `faster-whisper` modèle `base` (290 Mo), téléchargement lazy au premier usage, GPU si dispo | UI : upload audio + langue + transcription affichée |
| **Conversion** : `ffmpeg` wrapper, présets (mp4→mp3, webp→png, etc.) | UI : sélection fichier + format cible |
| **Slides** : Laravel reçoit `SlideCommandIssued`, pont Python `pyautogui.press('right')` | UI tel : grandes flèches + timer + bouton noir |
| **Scanner QR** : Flutter scanne, push résultat Reverb | UI PC : popup avec contenu, bouton « ouvrir si URL » |
| **Tests :** kill Whisper en cours, ffmpeg avec fichier corrompu | **Test :** vidéo YT 5min DL, transcription audio 1min, présentation 30 slides |

## 📹 B6 — Webcam virtuelle système (S18-S19)

**🎯 Objectif :** Le tel reconnu comme vraie webcam par les apps (Zoom, Meet, OBS).

| ⚙️ Backend (Laravel + Python) | 📱 Frontend (Flutter / Next.js) |
|---|---|
| **Linux** : script d'install `v4l2loopback-dkms`, pont Python pousse frames WebRTC → `/dev/video10` via `pyvirtualcam` | UI : bouton « activer webcam système » + indicateur |
| **Windows** : détection OBS installé, sinon notice + lien install, pont pousse vers OBS Virtual Camera via plugin | Notice claire : « ouvre Zoom et choisis "Linkup Camera" » |
| Gestion start/stop propre, libération device | Toggle dans réglages module caméra |
| **Tests :** Zoom détecte Linkup, OBS détecte Linkup | **Test manuel :** appel Meet avec webcam Linkup, 5 min |

## 🌐 B7 — Fallback tunnel VPS + coturn (S20-S21)

**🎯 Objectif :** Tout fonctionne hors LAN, vidéo dégradée mais audio/fichiers/clipboard OK.

| ⚙️ Backend (Laravel + Python) | 📱 Frontend (Flutter / Next.js) |
|---|---|
| Reverse SSH tunnel `autossh` + `systemd` sur VPS sahelstack.tech | Badge « Local » / « Distant » dans l'app |
| Relais Reverb via `relay.sahelstack.tech`, token Bearer par-device | Bascule transparente pour l'utilisateur |
| **coturn** installé sur VPS, credentials TURN éphémères par session | Avertissement latence mode distant |
| Détection auto : ping LAN OK ? sinon tunnel | Indicateur transport actif (LAN / VPS) |
| Token Bearer par-device, rate limiting Nginx | Test depuis réseau mobile 4G |
| Sécurisation : CORS strict, audit logs | **Test :** transfert + clipboard + caméra hors LAN |

## 🧪 B8 — Tests, sécurité, packaging (S22-S24)

**🎯 Objectif :** 0 bug critique, installable par un non-tech.

- **Tests Pest exhaustifs** : pairing, sécurité (QR expiré, device non approuvé, rate limiting), routage 16 modules
- **Tests pont Python** : pytest sur clipboard, transfert, PTY, MPRIS/SMTC mocké
- **Tests Flutter** : widget tests + integration tests pour pairing + transfert + WebRTC
- **Audit sécurité** : test de rejeu, MITM LAN simulé, token volé, fuzzing terminal
- **Installateur Linux** : script bash `install.sh` + service systemd `linkup-agent.service`
- **Installateur Windows** : Inno Setup avec PHP portable + Python portable embarqués
- **APK Android** : signé avec keystore Linkup, distribué via GitHub Releases
- **Test multi-appareils** : 2 téléphones sur 1 PC sans collision
- **Test vrai matériel** : Surface Pro (Windows 11), Ubuntu 24.04, téléphone Android

## 🎓 B9 — Recette + soutenance (S25)

- **README** : installation Linux + Windows + build Flutter + APK signé
- **Guide utilisateur PDF** avec captures du parcours pairing + 16 modules
- **Vidéo démo 5-7 min** : pairing → transfert → presse-papier → caméra + webcam virtuelle → terminal → preview localhost → fallback tunnel
- **Slides** : problème, vision, architecture hybride, démo, Phase 2
- **Q&A préparées** : pourquoi Flutter, pourquoi pont Python, sécurité Noise IK, choix coturn, webcam virtuelle Linux vs Windows
- **Backup soutenance** : vidéo démo enregistrée + hotspot 4G personnel + démo offline scriptée

---

## PARTIE 4 • SPÉCIFICATIONS TECHNIQUES

# 14. Stack Technique Finale

| Couche | Technologie | Rôle |
|---|---|---|
| Agent PC | Laravel 12 + PHP 8.4 | Orchestrateur, appairage, routage |
| Pont système | Python 3.11+ + FastAPI | Clipboard OS, caméra, PTY, yt-dlp, Whisper, ffmpeg |
| App mobile | Flutter 3 (Android 8.0+) | Client : scan, modules, caméra |
| Interface web | Next.js 15 (App Router) | Dashboard appareils + outils navigateur |
| UI web | shadcn/ui + Tailwind CSS | Composants accessibles |
| Temps réel | Laravel Reverb | WebSocket, protocole Pusher |
| Client RT web | Laravel Echo | Connexion dashboard ↔ Reverb |
| Client RT mobile | `web_socket_channel` | Connexion Flutter ↔ Reverb |
| Vidéo/audio | WebRTC (`flutter_webrtc` + navigateur) | Flux caméra/micro |
| Découverte LAN | mDNS / Bonjour | Trouver l'agent sur le réseau |
| Crypto handshake | Noise IK via libsodium | Auth mutuelle + clé de session |
| Tunnel distant | Reverse SSH (autossh + systemd) + coturn | Relais via VPS Hostinger |
| Transfert fichiers | HTTP chunked (`dio` Flutter + FastAPI) | Envoi fiable et repris |
| Terminal | `ptyprocess` (Linux) + `pywinpty` (Windows) | Shell distant |
| Contrôle média | `dbus-python` (Linux MPRIS) + `winrt` (Windows SMTC) | Play/pause/volume |
| Notifs PC | Plyer + `notify-send` (Linux) + `win10toast` (Windows) | Affichage notifs |
| Webcam virtuelle | `v4l2loopback` + `pyvirtualcam` (Linux) + OBS VC (Windows) | Webcam système |
| Téléchargeur | yt-dlp + ffmpeg | Vidéo/audio web |
| Transcription | `faster-whisper` (CTranslate2) | Speech-to-text |
| Conversion | ffmpeg | Conversion média |
| Base locale agent | SQLite | Devices, tokens, transferts, audit |
| Tests backend | Pest + PHPUnit | Appairage, sécurité, routage |
| Tests Python | pytest + pytest-asyncio | Pont système |
| Tests Flutter | flutter_test + integration_test | UI + flows |
| CI/CD | GitHub Actions | Lint + tests + build APK + build installateurs |
| Erreurs prod | Sentry (free tier) | Monitoring |

# 15. Modèle de Données (Agent)

| Table | Colonnes clés | Notes |
|---|---|---|
| `devices` | id, name, public_key (Ed25519), fingerprint_sha256, approved, last_seen, created_at | Appareils appairés |
| `device_tokens` | id, device_id (FK), token_hash (argon2id), expires_at, rotated_from | Rotation tokens |
| `sessions` | id, device_id, transport (lan/tunnel), started_at, ended_at, ip | Connexions |
| `transfers` | id, device_id, filename, size, direction, status, sha256 | Historique fichiers |
| `file_chunks` | id, transfer_id, chunk_index, sha256, received_at | Reprise sur coupure |
| `clipboard_log` | id, device_id, content_type, content_hash, origin_device_id, created_at | Anti-boucle + historique |
| `links_log` | id, device_id, url, opened_at | Liens partagés |
| `notifications_mirror` | id, device_id, package, title, body, received_at, dismissed_at | Notifs Android côté PC |
| `terminal_sessions` | id, device_id, started_at, ended_at, restricted_mode, commands_count | Audit terminal |
| `terminal_commands` | id, session_id, command, exit_code, executed_at | Log commandes |
| `gallery_cache` | id, device_id, media_id, mime, thumb_path, fetched_at | Cache vignettes |
| `media_jobs` | id, device_id, type (yt-dlp/whisper/ffmpeg), input, output_path, status, started_at, finished_at | Jobs lourds |
| `security_audit` | id, device_id, event (qr_expired/unauthorized/etc.), payload (JSON), at | Audit sécurité |
| `module_settings` | id, device_id (nullable=global), module, enabled, config (JSON) | Activation par module/par device |
| `localhost_tunnels` | id, device_id, local_port, public_url, started_at, ended_at | Preview localhost actifs |

# 16. Protocoles bas niveau

## 16.1 Transfert binaire

- **Endpoint** : `POST /transfer/upload` (FastAPI), `GET /transfer/download/{id}` (idem)
- **Chunk** : 1 Mo, header binaire `[chunk_index:u32][sha256:32][payload]`
- **Reprise** : `HEAD /transfer/upload/{id}` retourne la liste des `chunk_index` reçus, client renvoie ceux qui manquent
- **Checksum global** : SHA-256 calculé côté serveur après concat, comparé au header `X-Linkup-Sha256` envoyé par le client
- **Limite** : 2 Go par fichier (configurable dans `module_settings`)

## 16.2 Signaling WebRTC

- Émis via Reverb, payloads : `offer`, `answer`, `ice-candidate`
- ICE servers : STUN public Google + TURN privé sahelstack.tech (credentials éphémères TTL 1h générés via `coturn` REST API)

## 16.3 Terminal PTY

- WebSocket binaire `/term/ws?session={sid}`
- Frames : `[type:u8][len:u32][payload]`, types : `0=stdin`, `1=stdout`, `2=stderr`, `3=resize`, `4=exit`
- Échappement ANSI filtré côté serveur (refus séquences `OSC` dangereuses)

## 16.4 Anti-boucle clipboard

```
on receive(content, hash, origin_device_id, ts):
  if hash in recent_hashes (TTL 2s): drop
  if origin_device_id == self.id: drop
  apply(content)
  recent_hashes.add(hash, ts)
  broadcast_to_others(content, hash, self.id, ts)
```

# 17. Matrice « Module × OS × Dépendances Python »

| Module | Linux | Windows | Bibliothèques Python |
|---|---|---|---|
| Transfert fichiers | ✅ | ✅ | `aiofiles`, `httpx` |
| Presse-papier | ✅ `xclip`/`wl-clipboard` | ✅ `pyperclip` | `pyperclip`, `subprocess` |
| Lien rapide | ✅ `xdg-open` | ✅ `os.startfile` | natif |
| Galerie distante | ✅ | ✅ | `Pillow` (thumbs) |
| yt-dlp | ✅ | ✅ | `yt-dlp` |
| Transcription | ✅ | ✅ | `faster-whisper`, `ffmpeg-python` |
| Conversion média | ✅ ffmpeg | ✅ ffmpeg | `ffmpeg-python` |
| Caméra (navigateur) | ✅ | ✅ | géré via WebRTC navigateur |
| Caméra (webcam système) | ✅ `v4l2loopback` | ⚠️ via OBS Virtual Camera | `pyvirtualcam` |
| Micro | ✅ | ✅ | WebRTC navigateur, pas Python |
| Télécommande slides | ✅ | ✅ | `pyautogui` |
| Scanner QR | ✅ | ✅ | côté Flutter, PC reçoit texte |
| Notifs miroir | ✅ `notify-send`/Plyer | ✅ `win10toast`/Plyer | `plyer` |
| Terminal distant | ✅ `ptyprocess` | ✅ `pywinpty` | `ptyprocess` ou `pywinpty` |
| Contrôle média | ✅ `dbus-python` (MPRIS) | ✅ `winrt-Windows.Media.Control` | `dbus-python` ou `winrt` |
| Faire sonner | ✅ côté Android | ✅ côté Android | trigger Reverb uniquement |
| Preview localhost | ✅ | ✅ | `httpx` async |

# 18. Sécurité (récap)

- QR d'appairage à usage unique, expiration 60 secondes
- Handshake Noise IK (libsodium), authentification mutuelle Ed25519
- Tokens persistants hashés argon2id, rotation 30j à chaque reconnexion
- Liste blanche d'appareils approuvés par empreinte SHA-256 affichée côté PC
- Terminal distant : opt-in PC, shell restreint par défaut, log de toutes commandes
- Tunnel VPS : token Bearer par-device + TLS Let's Encrypt + CORS strict + rate limiting Nginx
- coturn : credentials éphémères TTL 1h générés par session
- Anti-rejeu : nonce + timestamp 30s sur chaque message
- Anti-boucle clipboard : hash + origin + TTL 2s
- Secrets (token VPS, clés Ed25519) jamais commités, stockés dans `~/.linkup/keys/` chmod 600
- Audit sécurité : table dédiée, dashboard d'alertes

# 19. Observabilité

| Outil | Surveille | Quand |
|---|---|---|
| Logs Laravel | `storage/logs/linkup.log` — pairing, routage, erreurs | B1 |
| Logs pont Python | `~/.linkup/logs/bridge.log` — actions OS, échecs | B1 |
| Table `sessions` | Connexions, transport, durée | B1 |
| Table `security_audit` | Tentatives rejetées, QR expirés, commandes terminal | B1 |
| `journalctl -u linkup-agent` | État systemd Linux | B8 |
| Event Viewer Windows | État service Windows | B8 |
| `journalctl -u autossh-sahelstack` | État tunnel VPS | B7 |
| Sentry (free) | Erreurs agent + dashboard + Flutter | B1 |
| Dashboard `/observability` | Vue temps réel : devices connectés, transferts en cours, jobs lourds | B8 |

---

## PARTIE 5 • OBJECTIFS, GOUVERNANCE & RECETTE

# 20. Objectifs & Indicateurs

| Type | Objectif | Indicateur |
|---|---|---|
| Appairage | Connexion immédiate sans saisie | < 5 s du scan à connecté + approuvé |
| Transfert fichier | Fiable sur LAN | 100 % réussite sur 20 transferts dont 3 reprises |
| Presse-papier | Synchro perçue instantanée | < 1 s entre copie et disponibilité |
| Lien rapide | Ouverture immédiate | < 2 s entre tap et navigateur ouvert |
| Galerie distante | Liste rapide | < 3 s pour les 50 premières vignettes |
| Caméra | Flux exploitable sur LAN | Latence < 300 ms perçue |
| Micro | Audio clair | Latence < 200 ms perçue |
| Webcam virtuelle | Reconnue par Zoom/Meet | Test live sur Linux + Windows |
| Terminal distant | Réactivité shell | Latence frappe < 100 ms LAN |
| Notifs miroir | Affichage rapide | < 2 s entre notif tel et affichage PC |
| Contrôle média | Pilotage fiable | Play/pause/volume sur Spotify, VLC, lecteur navigateur |
| Faire sonner | Déclenchement fiable | Sonne dans les 3 s, même tel en veille |
| Preview localhost | URL accessible | URL ouvrable tel en < 5 s |
| yt-dlp | Téléchargement réussi | YouTube, Twitter, TikTok testés |
| Transcription | Précision raisonnable | WER < 15 % sur audio FR clair, modèle `base` |
| Conversion | Formats courants | mp4→mp3, webp→png, mov→mp4 |
| Slides | Réactivité | < 200 ms entre tap et changement slide |
| Scanner QR | Détection fiable | 100 % sur 10 QR variés |
| Fallback tunnel | Service continu hors LAN | Bascule auto en < 3 s |
| Stabilité | Pas de crash en démo | 0 erreur sur 5 démos répétées |
| Prise en main | Utilisable par un non-technique | 1er transfert en < 2 min |
| Sécurité | Aucune connexion non autorisée | QR expiré + device inconnu + token volé rejetés |

# 21. Périmètre Phase 1 (rappel)

**16 modules in-scope :**
- Fichiers : transfert, presse-papier, lien rapide, galerie distante
- Médias : téléchargeur yt-dlp, transcription Whisper, conversion ffmpeg
- Caméra/Audio : caméra navigateur **et** webcam virtuelle système, micro, télécommande slides, scanner QR
- Contrôle PC : notifs miroir, terminal distant, contrôle média, faire sonner, preview localhost

**Plateformes :** Android 8.0+, Windows 10/11, Linux (Ubuntu 22.04+, Debian 12+, Fedora 39+)

# 22. Phase 2 (différée, périmètre connu)

- **🎵 Identification audio** : intégration AcoustID (libre) ou Shazam API (payant) ; capter 5-10s d'audio, requête, retour titre/artiste
- **iOS** : portage Flutter avec dégradations connues (clipboard manuel, notifs locales seulement, multicast conditionnel)
- **macOS** : pont Python adapté (CoreMediaIO pour webcam virtuelle, MediaRemote pour contrôle média)
- **Webcam virtuelle Windows native** : filtre DirectShow C++ (remplace wrapper OBS)
- **Distribution Play Store** : justifier NotificationListenerService auprès de Google, payer le compte développeur 25 $

# 23. Risques & Mitigations

| Risque | Impact | Mitigation |
|---|---|---|
| Webcam virtuelle Windows complexe (driver kernel) | Module dégradé sur Windows | Wrapper OBS Virtual Camera en Phase 1, vrai filtre DirectShow en Phase 2 |
| Latence en mode tunnel | Vidéo peu fluide hors LAN | Vidéo/audio réservés au LAN, fallback pour fichiers/texte uniquement |
| Pare-feu bloque le LAN | Découverte mDNS échoue | Saisie manuelle d'IP en secours + doc pare-feu Windows Defender + UFW Linux |
| Pont Python diffère selon l'OS | Bugs spécifiques Windows/Linux | Abstraction par OS (pattern Strategy), tests CI sur les deux |
| Surcharge VPS (relais) | Ralentit sahelstack.tech | Rate limiting Nginx + monitoring + bascule LAN dès que possible |
| NotificationListenerService refusé par Google | Pas de Play Store | Distribution APK signé via GitHub Releases (sideload assumé Phase 1) |
| Whisper trop lent sur CPU | Transcription longue | Modèle `base` par défaut, info utilisateur sur le temps estimé |
| yt-dlp cassé sur YouTube | Module en panne | Cron hebdo `pip install -U yt-dlp` + notif admin si échec |
| Terminal distant compromis | Compromission PC | Opt-in PC + shell restreint par défaut + log + confirmation à l'ouverture |
| Token VPS volé | Accès relais non autorisé | Token par-device + rotation 30j + révocation un click |

# 24. Critères d'Acceptation (Soutenance)

- ✅ Un téléphone Android s'appaire au PC (Windows ou Linux) par scan QR en moins de 5 secondes avec approbation côté PC
- ✅ Un fichier de 500 Mo est transféré dans les deux sens, avec reprise après coupure simulée
- ✅ Un texte copié sur le tel se colle sur le PC (et inversement) en mode manuel
- ✅ Un lien envoyé depuis le tel s'ouvre dans le navigateur du PC en < 2 s
- ✅ La galerie du téléphone est parcourue depuis le PC, 50 vignettes en < 3 s
- ✅ La caméra du téléphone s'affiche dans le dashboard PC, latence < 300 ms
- ✅ La caméra du téléphone est utilisable comme webcam Linkup dans Zoom/Meet (Linux v4l2loopback ou Windows via OBS)
- ✅ Le micro du téléphone est utilisable côté PC
- ✅ Un terminal restreint sur le PC est piloté depuis le tel, avec confirmation et log
- ✅ Spotify/VLC est piloté play/pause/volume depuis le tel
- ✅ Une notification WhatsApp Android s'affiche côté PC en < 2 s
- ✅ Une URL YouTube envoyée depuis le tel se télécharge sur le PC via yt-dlp
- ✅ Un audio FR est transcrit via Whisper côté PC
- ✅ Un mp4 est converti en mp3 via ffmpeg
- ✅ Un PDF de slides est piloté next/prev depuis le tel
- ✅ Un QR scanné par le tel s'affiche côté PC
- ✅ Le port 3000 du PC est exposé via une URL ouvrable sur le tel hors LAN
- ✅ Le téléphone perdu sonne depuis le dashboard PC, même en veille
- ✅ Hors du même Wi-Fi, la liaison bascule sur le tunnel VPS automatiquement en < 3 s
- ✅ Aucune connexion non autorisée n'est acceptée (QR expiré, device inconnu, token volé, replay)

---

## 🎓 Mot de la fin

Linkup ne réinvente pas la roue : il réunit, dans une seule app appairée en un scan, **les 16 petits ponts** qu'on bricole aujourd'hui à la main entre son téléphone Android et son PC Windows ou Linux. La Phase 1 livre l'intégralité de la boîte à outils ; la Phase 2 ouvrira le produit à iOS, macOS, et ajoutera l'identification audio en bouquet final.

**Stack assumée :** Laravel 12 (orchestrateur), Python 3 (pont OS), Flutter 3 (Android), Next.js 15 (web).
**Sécurité :** Noise IK + libsodium, tokens par-device, opt-in pour le terminal.
**Calendrier :** 25 semaines de développement structuré en 9 briques techniques.
**Budget :** 0 € incrémental.
