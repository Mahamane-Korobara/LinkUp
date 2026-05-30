# Linkup - Schema ultra simple en ASCII de tous les flux

Ce document sert a voir le projet comme une carte.

Le but n'est pas d'etre elegant.
Le but est d'etre **clair**.

---

## 1. Vue ultra simple

```text
                           RESEAU LOCAL (LAN)
                    mDNS _linkup._tcp.local. + heartbeat

        +-----------------------------------------------------------+
        |                                                           |
        v                                                           v
+------------------------+                               +------------------------+
|       PC A             |                               |       PC B             |
|                        |                               |                        |
|  Laravel API :8000     |<------ HTTP local ------->   |  Laravel API :8000     |
|  Reverb WS   :8080     |                               |  Reverb WS   :8080     |
|  Bridge      :8765     |                               |  Bridge      :8765     |
|                        |                               |                        |
|  mDNS announce         |<---- mDNS + /health ---->    |  mDNS announce         |
|  mDNS browser          |                               |  mDNS browser          |
+------------------------+                               +------------------------+
          ^
          |
          | WebSocket / HTTP / plus tard WebRTC
          |
 +-------------------+        Wi-Fi local ou tunnel plus tard        +------------------+
 |   Flutter mobile  | <-------------------------------------------> |  Dashboard web    |
 |   Android         |                                               |  Next.js          |
 +-------------------+                                               +------------------+
```

---

## 2. Flux sur UNE machine

```text
                   MEME PC

      +-----------------------------------------------+
      |                 MACHINE LOCALE                |
      |                                               |
      |  +-------------------+                        |
      |  | Laravel agent     |                        |
      |  | port 8000         |                        |
      |  |                   |                        |
      |  | - routes /api/... |                        |
      |  | - logique metier  |                        |
      |  +---------+---------+                        |
      |            |                                  |
      |            | HTTP local                       |
      |            | 127.0.0.1:8765                   |
      |            v                                  |
      |  +-------------------+                        |
      |  | Python bridge     |                        |
      |  | port 8765         |                        |
      |  |                   |                        |
      |  | - /health         |                        |
      |  | - /mdns/info      |                        |
      |  | - /mdns/services  |                        |
      |  | - logique mDNS    |                        |
      |  +---------+---------+                        |
      |            |                                  |
      |            | mDNS announce / browse           |
      |            | UDP multicast 5353               |
      |            v                                  |
      |         reseau local                          |
      |                                               |
      |  +-------------------+                        |
      |  | Reverb            |                        |
      |  | port 8080         |                        |
      |  |                   |                        |
      |  | - WebSocket       |                        |
      |  | - events temps reel                       |
      |  +-------------------+                        |
      +-----------------------------------------------+
```

---

## 3. Flux Laravel <-> Python

```text
Client / navigateur / plus tard Flutter
                  |
                  | appelle Laravel
                  v
         +----------------------+
         | Laravel /api/...     |
         +----------+-----------+
                    |
                    | utilise le service MdnsAnnouncer
                    v
         +----------------------+
         | HTTP local           |
         | http://127.0.0.1:8765|
         +----------+-----------+
                    |
                    v
         +----------------------+
         | FastAPI bridge       |
         | /health              |
         | /mdns/info           |
         | /mdns/services       |
         +----------------------+
```

Exemple reel :

```text
GET /api/agent/info
    -> Laravel
    -> MdnsAnnouncer::localInfo()
    -> GET http://127.0.0.1:8765/mdns/info
    -> Python repond
    -> Laravel renvoie le JSON final
```

---

## 4. Flux mDNS sur le LAN

```text
Au demarrage du bridge Python :

Bridge Python
   |
   | annonce le service
   v
"_linkup._tcp.local."
port principal annonce = 8080
TXT contient aussi bridge_port = 8765


Quand un autre PC ecoute :

Autre bridge Python
   |
   | browse _linkup._tcp.local.
   v
detecte le service
   |
   | resolve details
   v
recupere:
- nom
- IP
- port 8080
- bridge_port 8765
- fingerprint
- version
```

---

## 5. Flux de presence actuel

```text
1. mDNS detecte un agent
2. le bridge cree un DiscoveredAgent
3. last_seen = maintenant
4. toutes les 5 secondes:
      GET http://<ip>:<bridge_port>/health
5. si status == alive:
      last_seen = maintenant
6. si last_seen trop vieux (> 15s):
      agent supprime de la liste
```

En ASCII :

```text
         mDNS found
            |
            v
     +--------------+
     | agent connu   |
     | last_seen=now |
     +------+-------+
            |
            | toutes les 5 s
            v
     GET /health
            |
      +-----+------+
      |            |
      v            v
   repond       ne repond pas
      |            |
      v            v
last_seen=now   temps passe
                     |
                     v
             > 15 secondes ?
                     |
               +-----+-----+
               |           |
               v           v
             non         oui
               |           |
               v           v
           on garde    on supprime
```

---

## 6. Flux temps reel Reverb

```text
Flutter / Dashboard / futurs clients
                 |
                 | WebSocket
                 v
             Reverb :8080
                 |
                 | event broadcast
                 v
              Laravel
```

Exemple actuel :

```text
POST /api/ping
    -> Laravel cree PingEvent
    -> Reverb broadcast sur channel "linkup-system"
    -> clients connectes recoivent l'event "ping"
```

---

## 7. Flux complet le plus important aujourd'hui

```text
                    +-----------------------------+
                    |   bridge Python demarre     |
                    +--------------+--------------+
                                   |
                   +---------------+----------------+
                   |                                |
                   v                                v
            annonce mDNS                    ecoute mDNS
             sur le LAN                     agents du LAN
                   |                                |
                   +---------------+----------------+
                                   |
                                   v
                          maintient la liste
                          des agents vivants
                                   |
                                   v
                     Laravel peut consulter cette liste
                     via GET /api/mdns/services
                                   |
                                   v
                          client lit la reponse
```

---

## 8. Tableau final des flux

| Source | Destination | Moyen | Pourquoi |
|---|---|---|---|
| Laravel | Python bridge | HTTP local `127.0.0.1:8765` | demander infos systeme / mDNS |
| Python bridge | LAN | mDNS UDP 5353 | annoncer l'agent et detecter les autres |
| Python bridge | autre bridge Python | HTTP `/health` | heartbeat de presence |
| Client | Laravel | HTTP | API metier |
| Client | Reverb | WebSocket | temps reel |
| Laravel | Reverb | broadcast | diffuser des events |
| Dashboard | Laravel | HTTP | lire/afficher des donnees |
| Flutter plus tard | Laravel/Reverb | HTTP + WebSocket | pilotage mobile |

---

## 9. Resume en une phrase

```text
Laravel coordonne -> Python bridge observe le LAN et le systeme ->
Reverb transporte le temps reel -> Flutter et Dashboard seront les interfaces.
```

