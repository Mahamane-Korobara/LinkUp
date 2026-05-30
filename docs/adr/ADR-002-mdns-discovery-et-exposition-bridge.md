# ADR-002 — Découverte mDNS, LAN sweep, exposition du bridge

**Date :** 2026-05-30
**Statut :** Accepté
**Contexte semaine :** S1.J4

## Contexte

La brique 1 du plan d'exécution (S1) demande que **le téléphone Android découvre automatiquement les agents Linkup sur le LAN**, sans saisie manuelle d'IP. Deux questions architecturales se sont posées :

1. **Quelle techno de découverte ?** mDNS pur, scan IP, broadcast UDP, autre ?
2. **Quel composant le téléphone doit-il atteindre ?** Laravel uniquement (façade), ou directement le bridge Python ?

Le document `stack-roles.md` stipule à l'origine :

> Python tourne en parallèle de Laravel sur le même PC, **écoute sur `127.0.0.1:8765` (jamais exposé sur le réseau)**, et Laravel l'appelle quand il a besoin d'une action système.

Cette règle a été remise en cause par deux constats faits en S1.J4.

## Décisions

### 1. Découverte mDNS bidirectionnelle via zeroconf

Le bridge Python utilise la lib `zeroconf` pour :
- **Annoncer** ce PC sur le LAN sous le service type `_linkup._tcp.local.`
- **Browser** les annonces des autres PCs sur le même LAN
- **Heartbeat HTTP** toutes les 5 s sur les agents découverts, purge après 15 s sans réponse

Côté Android, le téléphone utilise la lib Dart `multicast_dns` pour scanner le même service type.

**Pourquoi mDNS plutôt qu'un broadcast UDP custom :**
- Standard IETF (RFC 6762/6763), interopérable avec `avahi-browse`, Service Browser, etc.
- Pas de protocole à concevoir, juste des records DNS standards
- Le téléphone n'a même pas besoin de connaître l'IP du serveur à l'avance

### 2. LAN sweep HTTP en fallback

Le multicast mDNS est **bloqué dans plusieurs cas réels** rencontrés en test :
- Hotspot Wi-Fi Samsung (filtre le multicast entre clients et AP)
- Wi-Fi public avec isolation client activée
- Containers / VPN avec multicast non routé

Décision : doubler la découverte mDNS d'un **LAN sweep HTTP en parallèle**. Le téléphone :
- Lit son IP locale (`NetworkInterface.list`)
- Calcule le sous-réseau `/24`
- Tape `GET http://192.168.x.N:8765/health` sur les 254 IPs en batchs de 64 parallèles, timeout 600 ms
- Toute IP qui répond `{"service": "linkup-bridge"}` est ajoutée à la liste

C'est invisible pour l'utilisateur final et garantit la découverte sur **tout type de réseau LAN**, multicast actif ou non. C'est le pattern utilisé par Sonos, Chromecast, Spotify Connect.

### 3. Le bridge Python écoute sur `0.0.0.0:8765` (LAN reachable)

C'est une **divergence assumée** par rapport à `stack-roles.md` original.

**Raisons :**
- Le **heartbeat mDNS inter-PC** (un bridge Linkup A probe le `/health` d'un bridge Linkup B sur le LAN) nécessite que B soit joignable depuis A. Si B écoutait sur `127.0.0.1`, le heartbeat retournerait toujours en échec.
- Le **LAN sweep du téléphone** (point 2) doit atteindre le bridge sur `:8765`. Faire transiter par Laravel (port 8000) ajouterait une indirection sans bénéfice tangible : Laravel proxifierait simplement la même réponse.

**Garde-fous de sécurité :**
- Une **seule route est publique sans authentification** : `GET /health`. Elle ne retourne aucun secret au-delà de ce que mDNS broadcast déjà publiquement (`agent_id`, `host`, `user`, `version`).
- Toutes les autres routes (`/system/info`, `/mdns/info`, `/mdns/services`, futures routes `/clipboard`, `/transfer`, `/term`) **requièrent un token Bearer** stocké côté Laravel et configuré dans `.env`.
- Le pairing QR de S2 ajoute la couche crypto session (Noise IK + token persistant argon2id) qui sécurise le canal applicatif.

### 4. Le téléphone attaque directement le bridge en LAN sweep

Pour la **découverte uniquement**, le téléphone parle directement à `http://<ip>:8765/health` du bridge sans passer par Laravel. Une fois un agent sélectionné et le pairing établi (S2), **toute la communication métier passe par Laravel** (port 8000) qui orchestre :
- L'authentification du device (token Bearer émis au pairing)
- Le routing vers Reverb / bridge / SQLite
- L'audit log de chaque action

Donc le pattern « Flutter → Laravel → bridge » est respecté pour tout sauf la phase de découverte initiale, où il est court-circuité au profit de la simplicité.

## Conséquences

### Positives
- Découverte robuste sur tout LAN (multicast OK ou non)
- Pas de friction utilisateur : agent visible en 1-3 s à l'ouverture de l'app
- Architecture cohérente : Laravel reste le point d'entrée pour tout le métier post-pairing
- Le bridge devient un peer adressable, pas un détail d'implémentation cachée

### Négatives
- `stack-roles.md` initial est désormais obsolète sur ce point précis → mis à jour dans cet ADR
- Surface d'attaque légèrement élargie : `/health` est public sur le LAN. Mitigation : ne retourne aucun secret, juste les mêmes champs que l'annonce mDNS visible de toute façon.
- Le LAN sweep côté Flutter génère 254 requêtes HTTP à chaque scan (mais en batchs parallèles, ~2 s au total, négligeable)
- Le user doit ouvrir le port 8765 dans son pare-feu (documenté dans `Linkup-Runbook-Local.md`)

### À mettre à jour suite à cette décision
- [x] Créer cet ADR
- [ ] Mettre à jour `stack-roles.md` ligne 83 (suppression mention « jamais exposé sur le réseau »)
- [ ] Documenter dans `Linkup-Tutoriel-Architecture.md` la phase de découverte
- [ ] Ajouter dans l'installeur S6.5 l'ouverture des ports 8765 (TCP) et 5353 (UDP) dans le pare-feu
- [ ] À S20-S21 (tunnel VPS), prévoir que le bridge expose `/health` également via tunnel (pour le LAN sweep distant ne marche évidemment plus, mais Reverb signale présence)

## Alternatives écartées

### A. Bridge en `127.0.0.1` strict + Flutter cible Laravel
- Demande à Laravel d'exposer `/api/health` enrichi avec `host`, `user`, etc.
- Pose un problème pour le heartbeat mDNS inter-PC (impossible)
- Ajoute une indirection à chaque sweep (Laravel doit re-proxy vers bridge)
- **Rejeté** : plus complexe pour un gain de sécurité marginal (toutes les routes sensibles sont déjà token-protected)

### B. Discovery via broadcast UDP custom (sans mDNS)
- Demande de coder un protocole maison
- Pas d'interop avec les outils standards (avahi-browse, Bonjour)
- **Rejeté** : réinvente la roue

### C. Discovery via serveur central VPS
- Le PC enregistre son IP LAN sur un endpoint VPS, le tel interroge le VPS
- Demande un VPS toujours actif, casse le mode 100% LAN
- **Rejeté** : Linkup est volontairement peer-to-peer LAN-first (cf. mémoire projet `linkup_scope`)

## Références

- Plan d'exécution : `Linkup-Plan-Execution.md` semaine S1
- Doc d'audit S1.J4 : `Linkup-Audit-S1J4.md` point 16 « Architecture vs stack-roles.md »
- Code bridge : `bridge/app/services/mdns.py`, `bridge/app/main.py`
- Code mobile : `mobile/lib/services/linkup_discovery.dart`, `mobile/lib/services/lan_sweep.dart`
