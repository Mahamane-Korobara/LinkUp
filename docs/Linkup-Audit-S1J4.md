# 🔍 Rapport d'Audit — Linkup (état S1.J4)

**Date :** 2026-05-30
**Stack :** Laravel 12 (PHP 8.4) + FastAPI (Python 3.12) + Flutter 3.41 (Dart 3.11) + Kotlin Android + Next.js 15 (scaffold)
**Périmètre audité :** `bridge/app/`, `agent/app/` (custom), `agent/routes/api.php`, `mobile/lib/`, `mobile/android/.../MainActivity.kt`
**Documents de référence :** `Linkup-CDC-v2_0.md`, `Linkup-Plan-Execution.md`, `stack-roles.md`
**Lignes de code analysées :** ~2 360 LOC (incl. tests, dont ~1 850 LOC métier)
**Problèmes trouvés :** 27 (🔴 4 critiques • 🟠 14 importants • 🟡 9 mineurs)
**Estimation dette :** ~6 à 8 heures de nettoyage

---

## 🟢 Mise à jour 2026-05-30 — 4 critiques corrigés

Les 4 items 🔴 du top critiques ont été traités dans la session S1.J4 (cf. commits à venir).
Récap des correctifs livrés :

| # | Problème | Fix appliqué |
|---|---|---|
| 1 | Divergence archi bridge LAN | **ADR-002** créé (`docs/adr/ADR-002-mdns-discovery-et-exposition-bridge.md`) + `stack-roles.md` mis à jour pour aligner avec la réalité. `/health` reconnu publique, autres routes token-protected. |
| 2 | Token bridge par défaut public | `config.py` : suppression du défaut, validation Pydantic refuse la valeur placeholder + `min_length=16` + ports validés `1..65535`. Tests `tests/test_config.py` (5 cas). `.env.example` documente la génération via `secrets.token_urlsafe(32)`. |
| 3 | Bug `_resolve` écrase l'agent | Méthode `_mergeAgent()` ajoutée dans `linkup_discovery.dart` qui utilise `copyWith` pour préserver les champs non-null existants (résout aussi le code mort `copyWith`). Le sweep et `_resolve` passent désormais par cette fusion. |
| 4 | Race `_emit()` après dispose | Flag `_cancelled` ajouté à `LinkupDiscovery`, propagé à `LanSweepDiscovery.sweep(isCancelled:)`. Le sweep vérifie le flag entre chaque batch HTTP → coupure propre au `dispose()` sans attendre les 254 timeouts. Test `linkup_discovery_test.dart`. |

**Tests verts après fixes :** pytest bridge 18/18 (+ 5 nouveaux pour `test_config.py`), Flutter 9/9 (+ 1 nouveau pour `linkup_discovery_test.dart`), `flutter analyze` 0 issue, `ruff` + `black` 0 issue.

---

## 📊 Résumé exécutif

### Top 5 problèmes critiques

1. **🔴 Divergence d'architecture vs `stack-roles.md`** — le bridge Python écoute sur `0.0.0.0:8765` au lieu de `127.0.0.1`, et Flutter l'attaque directement au lieu de passer par Laravel. C'est volontaire pour le LAN sweep, mais contredit le CDC §7 qui dit « le bridge n'est jamais exposé sur le réseau ». À acter dans un ADR ou à corriger.
2. **🔴 Token bridge par défaut `dev-shared-token-change-me`** (`bridge/app/config.py:10`) — si un user lance le bridge sans changer le `.env`, le token est public et lisible sur GitHub. À forcer en config obligatoire au boot, ou générer aléatoirement à l'install.
3. **🔴 `LinkupAgent` perd les infos sweep quand mDNS arrive après** (`linkup_discovery.dart:142`) — `_agents[uniqueKey] = agent` écrase l'agent existant sans merger. Si le sweep a trouvé `user="mahamane"` et que mDNS n'a pas le TXT user, on perd l'info.
4. **🔴 Race possible sur `_emit()` après `dispose()`** — `_runLanSweep` continue de tourner après que le widget soit unmount, et `_emit()` est gardé par `!_controller.isClosed`, OK — mais aucun guard côté sweep qui peut prendre 5-10s à finir. Risque de fuite mémoire si on push/pop ce screen souvent.

### Santé par catégorie

| Catégorie | 🔴 | 🟠 | 🟡 | Total |
|---|---|---|---|---|
| Code mort & inutilisé | 0 | 5 | 2 | 7 |
| Duplication (DRY) | 0 | 2 | 1 | 3 |
| Mauvaises pratiques / smells | 0 | 4 | 4 | 8 |
| Performance | 0 | 1 | 1 | 2 |
| Sécurité (signaux évidents) | 2 | 1 | 0 | 3 |
| Dette technique & structure | 2 | 1 | 1 | 4 |
| **Total** | **4** | **13** | **9** | **27** |

### Hot spots (fichiers les plus problématiques)

| Fichier | LOC | Problèmes |
|---|---|---|
| `mobile/lib/services/linkup_discovery.dart` | 247 | 7 |
| `mobile/lib/screens/agent_picker_screen.dart` | 354 | 6 |
| `mobile/lib/models/linkup_agent.dart` | 94 | 4 |
| `bridge/app/main.py` | 191 | 3 |
| `bridge/app/services/mdns.py` | 439 | 2 |
| Reste | — | 5 |

---

## 🗂️ Problèmes détaillés par fichier

### 1) `bridge/app/main.py` (191 lignes)

#### 🔴 Token bridge par défaut public — `config.py:10` (réf. globale, déclaré ici utilisé)
**Catégorie :** Sécurité
**Problème :** `agent_token: str = "dev-shared-token-change-me"` dans `Settings`. Si l'user ne crée pas son `.env` ou laisse cette valeur, le bridge accepte un token connu de tout GitHub. La route `/system/info` est alors ouverte à n'importe quel script du LAN.
**Avant :**
```python
class Settings(BaseSettings):
    agent_token: str = "dev-shared-token-change-me"
```
**Après :**
```python
class Settings(BaseSettings):
    agent_token: str  # pas de défaut → erreur au boot si absent
```
Ou alors le générer dans `install-linux.sh` / `installer-win.iss` (S6.5) avec `python -c "import secrets;print(secrets.token_urlsafe(32))"` et l'injecter dans le `.env`.

#### 🟠 `except Exception` trop large — `main.py:169`
**Catégorie :** Mauvaises pratiques
**Problème :** `_safe_username()` rattrape **toutes** les exceptions, masquant des erreurs imprévues.
**Avant :**
```python
def _safe_username() -> str:
    try:
        return getpass.getuser()
    except Exception:
        return "unknown"
```
**Après :**
```python
def _safe_username() -> str:
    try:
        return getpass.getuser()
    except (KeyError, OSError):
        # getpass.getuser() lève KeyError si HOME/LOGNAME absents,
        # OSError sur Windows en cas d'env dégradé.
        return "unknown"
```

#### 🟡 Bloc de commentaires verbeux qui dilue le code — `main.py:1-32`
**Catégorie :** Lisibilité
**Problème :** Chaque import a son commentaire "français" verbeux. Pour un projet ouvert sur GitHub avec contributeurs potentiels, c'est du bruit. Les noms parlent d'eux-mêmes.
**Avant :**
```python
import getpass  # Nom de l'utilisateur courant du PC
import platform  # Permet de récupérer les infos de l'ordinateur (OS, machine, version...)
import socket  # Nom de la machine (gethostname)
import time  # Permet de mesurer le temps (ici uptime du serveur)
```
**Après :** Garder UN commentaire d'en-tête de fichier qui résume le rôle du module. Supprimer les commentaires par import.

---

### 2) `bridge/app/services/mdns.py` (439 lignes)

#### 🟠 God class — `LinkupBrowser` (lignes 258-439)
**Catégorie :** Anti-pattern OOP
**Problème :** La classe fait 4 choses : (1) abonnement zeroconf, (2) résolution mDNS, (3) heartbeat HTTP périodique, (4) purge TTL. C'est 4 responsabilités → testabilité limitée, refactor douloureux quand on ajoutera la lecture des metrics dans S3.

**Suggestion :** extraire deux classes
```python
class LinkupBrowser:           # zeroconf seulement
class PresenceMonitor:         # heartbeat + TTL purge
```
À faire après S2 (pas urgent).

#### 🟡 Hostname `_local_ip` peut renvoyer l'IP cellular sur Android — n/a ici (côté Python)
**Catégorie :** Robustesse
**Problème :** `_local_ip()` (ligne 128) fait un `connect("8.8.8.8", 80)` pour deviner l'interface sortante. Sur un PC Linux avec VPN actif, ça retourne l'IP VPN au lieu de l'IP LAN, ce qui fait annoncer un mDNS visible depuis le VPN au lieu du Wi-Fi local.
**Action :** documenter en commentaire que ça suit la **route par défaut**, et qu'il faut configurer la priorité de route si VPN. Pas un bug ici, mais à signaler.

---

### 3) `bridge/app/routes/mdns.py` (82 lignes)

RAS. Code court, propre, bien typé. Pas de problème détecté.

---

### 4) `bridge/app/os/` — dossier vide

#### 🟡 Dossier squelette sans contenu — `bridge/app/os/__init__.py` (0 ligne)
**Catégorie :** Dette technique
**Problème :** Dossier créé pour la future couche OS (clipboard, terminal, MPRIS...) mais vide. Aucun import ne le référence (vérifié par `grep -rn "from app.os"`). Décourage les nouveaux contributeurs ("pourquoi ce dossier vide ?").
**Action :** soit y mettre un `clipboard.py` stub avec un commentaire « S5 », soit le supprimer jusqu'à utilité (suggéré).

---

### 5) `bridge/app/config.py` (19 lignes)

#### 🟠 Pas de validation des valeurs — `config.py:7-16`
**Catégorie :** Robustesse
**Problème :** Les ports sont des `int` sans contrainte. Rien n'empêche `port: int = 65536` (invalide) ou `mdns_heartbeat_interval_seconds: float = 0.0` (boucle infinie sans pause).
**Avant :**
```python
class Settings(BaseSettings):
    host: str = "127.0.0.1"
    port: int = 8765
    reverb_port: int = 8080
```
**Après :**
```python
from pydantic import Field

class Settings(BaseSettings):
    host: str = "127.0.0.1"
    port: int = Field(default=8765, ge=1, le=65535)
    reverb_port: int = Field(default=8080, ge=1, le=65535)
    mdns_heartbeat_interval_seconds: float = Field(default=5.0, gt=0.5)
```
Pydantic refuse au boot les valeurs hors plage. Erreur claire avant d'avoir un bug runtime.

---

### 6) `agent/app/Services/MdnsAnnouncer.php` (47 lignes)

#### 🟠 Méthode publique jamais appelée — `MdnsAnnouncer.php:15`
**Catégorie :** Code mort
**Problème :** `bridgeHealth(): array` exposée mais aucune route ni test ne l'appelle (vérifié par `grep -rn "bridgeHealth" agent/`). YAGNI : on ne sait pas encore quand on en aura besoin.
**Avant :**
```php
public function bridgeHealth(): array
{
    return $this->request()->get('/health')->throw()->json();
}
```
**Action :** soit supprimer, soit ajouter une route `/api/agent/bridge-health` qui s'en sert et un test Pest. Sinon c'est du code qui rote.

#### 🟠 Mauvais nom de classe — `MdnsAnnouncer` ne fait pas d'annonce
**Catégorie :** Lisibilité, naming
**Problème :** « Announcer » suggère que cette classe **publie** des annonces mDNS. En réalité, elle **interroge** le bridge Python (qui lui fait l'annonce). C'est un simple client HTTP. Le CDC §X dit « façade Laravel sur le bridge local ».
**Action :** renommer en `BridgeClient`, `BridgeFacade` ou `LocalBridgeProxy`. Adapter le test Pest + l'usage dans `routes/api.php` + la doc `Linkup-Tutoriel-Architecture.md`.

#### 🟡 Pas de gestion d'erreur HTTP — `MdnsAnnouncer.php:17-37`
**Catégorie :** Robustesse
**Problème :** `->throw()` lève une `RequestException` si le bridge est down (404, timeout, connexion refusée). Mais aucun controller/route ne catch ça → l'utilisateur du dashboard reçoit une stacktrace Laravel.
**Action :** soit catcher dans le service et retourner un état "degraded", soit ajouter un `try/catch` dans `routes/api.php` qui renvoie un 503 avec un message clair.

---

### 7) `agent/routes/api.php` (49 lignes)

#### 🟠 Pas de namespace ni de controller — routes en closures
**Catégorie :** Maintenabilité Laravel
**Problème :** 4 routes en closures inlines. Acceptable à S1, mais dès S3 (modèle de données + dashboard /devices), ça explosera. Le plan prévoit explicitement des controllers (`app/Http/Controllers/`).
**Action :** dès S2 (pairing), créer `AgentInfoController`, `PingController`. Garder les closures à la racine pour les health checks uniquement.

#### 🟡 Pas de validation sur `POST /api/ping` — `api.php:35`
**Catégorie :** Robustesse
**Problème :** `$request->input('message', 'pong')` accepte n'importe quoi sans taille max ni type. Un client malveillant peut envoyer un message de 10 Mo broadcast à tous les clients Reverb.
**Avant :**
```php
$message = $request->input('message', 'pong');
```
**Après :**
```php
$validated = $request->validate([
    'message' => 'sometimes|string|max:500',
]);
$message = $validated['message'] ?? 'pong';
```

---

### 8) `agent/app/Events/PingEvent.php` (43 lignes)

RAS. Standard Laravel `ShouldBroadcastNow`, naming clair, tests existent (`PingEventTest.php`).

---

### 9) `mobile/lib/models/linkup_agent.dart` (94 lignes)

#### 🟠 `copyWith` jamais utilisé — `linkup_agent.dart:59-79`
**Catégorie :** Code mort
**Problème :** Méthode présente mais aucun appel dans tout le code (`grep -rn "copyWith"` → 0 hit). YAGNI : à la première vraie nécessité, on l'ajoutera (5 min de boulot).
**Action :** supprimer.

#### 🟠 `bridgeHealthUri` jamais utilisé en prod — `linkup_agent.dart:47`
**Catégorie :** Code mort
**Problème :** L'URL est calculée par `LanSweepDiscovery._probe()` qui construit son URL à la main au lieu d'appeler `agent.bridgeHealthUri`. Le getter n'est utilisé que par les tests.
**Action :** soit faire utiliser le getter par le sweep, soit supprimer.

#### 🟠 `agentInfoUri` jamais utilisé en prod — `linkup_agent.dart:53`
**Catégorie :** Code mort (en attente de S1.J5)
**Problème :** Pareil que ci-dessus. Aucun appel hors tests. Mais celui-ci est légitime : il sera utilisé en S1.J5 (écran détail agent). À garder, à condition que S1.J5 le câble vite.

#### 🟡 Champ `host` redondant avec `hostname` — `linkup_agent.dart:8` vs `:15`
**Catégorie :** Duplication
**Problème :** `host` (mDNS brut comme `pc.local.`) et `hostname` (nettoyé comme `pc`) coexistent. Lecteur du code se demande lequel utiliser. L'UI utilise `hostname`. Le champ `host` n'est lu nulle part en lecture (vérifié).
**Action :** garder `hostname` uniquement, supprimer `host`. Adapter ctors + tests.

---

### 10) `mobile/lib/services/agent_discovery.dart` (21 lignes)

RAS. Petite interface, propre.

---

### 11) `mobile/lib/services/multicast_lock.dart` (47 lignes)

#### 🟡 Pas de gestion iOS / desktop — `multicast_lock.dart`
**Catégorie :** Portabilité
**Problème :** Le `MethodChannel` n'est implémenté que côté Android. Si l'app est lancée sur iOS (Phase 2) ou desktop, `MissingPluginException` est attrapé silencieusement et le scan continue sans lock. C'est OK aujourd'hui (Android only) mais à documenter.
**Action :** ajouter une note de commentaire en tête du fichier : « Android-only ; sur iOS/desktop les méthodes retournent silencieusement false ».

---

### 12) `mobile/lib/services/lan_sweep.dart` (118 lignes)

#### 🟠 Hardcoded `bridgePort: 8765` partout — `lan_sweep.dart:20`, `linkup_discovery.dart:172`, picker, model, ...
**Catégorie :** Magic numbers + duplication
**Problème :** `8765` apparaît 5 fois dans le code Dart. `8080` (Reverb) 3 fois. `8000` (Laravel) 1 fois. Si on change un port en config, il faut modifier N endroits.
**Avant :** valeurs littérales partout.
**Après :** créer `lib/config/linkup_ports.dart` :
```dart
abstract class LinkupPorts {
  static const int bridge = 8765;
  static const int reverb = 8080;
  static const int laravel = 8000;
}
```
Et l'utiliser partout. Trivial, gros gain de cohérence.

#### 🟠 Sweep peut survivre au dispose du widget — `lan_sweep.dart:47-55`
**Catégorie :** Robustesse
**Problème :** `for (int i = 0; i < ips.length; i += maxParallel)` ne vérifie aucun signal d'annulation. Si l'user quitte le picker pendant le sweep, 254 HTTP calls continuent en arrière-plan jusqu'à leur timeout.
**Avant :**
```dart
Future<List<LinkupAgent>> sweep({void Function(LinkupAgent)? onAgentFound}) async {
  // ...pas de cancellation
}
```
**Après :** ajouter un `cancelled: ValueListenable<bool>` ou un `CancelationToken` :
```dart
Future<List<LinkupAgent>> sweep({
  void Function(LinkupAgent)? onAgentFound,
  bool Function()? isCancelled,
}) async {
  for (int i = 0; i < ips.length; i += maxParallel) {
    if (isCancelled?.call() == true) return discovered;
    // ...
  }
}
```
Et appel côté `LinkupDiscovery.dispose()` qui flippe le flag.

#### 🟡 `source: LinkupAgentSource.mdns` mensonger — `lan_sweep.dart:80`
**Catégorie :** Naming / sémantique
**Problème :** Le sweep retourne un agent avec `source: mdns`. C'est faux : l'agent vient d'un sweep HTTP, pas de mDNS. L'UI les affiche identiquement (icône violet `Icons.computer`), ce qui dépanne, mais c'est trompeur pour la télémétrie future.
**Action :** ajouter une 3ᵉ valeur à l'enum :
```dart
enum LinkupAgentSource { mdns, manual, lanSweep }
```
Et l'UI peut toujours grouper `mdns` + `lanSweep` sous la même icône.

---

### 13) `mobile/lib/services/linkup_discovery.dart` (247 lignes)

#### 🔴 Écrasement d'agent perdant des champs — `linkup_discovery.dart:142`
**Catégorie :** Bug latent
**Problème :** Quand `_resolve` (mDNS) trouve un agent déjà présent en mémoire (mis par `_runLanSweep`), il fait `_agents[agent.uniqueKey] = agent`, écrasant l'ancien sans merger. Si le sweep avait peuplé `user="mahamane"` mais que le TXT mDNS n'a pas ce champ, l'info disparaît.
**Avant :**
```dart
_agents[agent.uniqueKey] = agent;
_emit();
```
**Après :**
```dart
final existing = _agents[agent.uniqueKey];
_agents[agent.uniqueKey] = existing == null
    ? agent
    : agent.copyWith(
        user: existing.user,
        // garde les valeurs de l'existant si le nouveau les a en null
      );
_emit();
```
**Note :** ça réutilise `copyWith` qui est dead code aujourd'hui → d'une pierre deux coups. Affiner la sémantique de fusion selon priorité mDNS > sweep.

#### 🟠 `_runMdnsScan` swallow toutes les erreurs — `linkup_discovery.dart:84-86`
**Catégorie :** Debug invisible
**Problème :** `on TimeoutException` est OK, mais si le `_client.lookup` lève une autre exception (socket fermé, OS error), elle remonte. Le `catch (_)` dans `_runLanSweep` (ligne 100) avale tout en silence. Ailleurs, rien. Diagnostic dur en prod quand un user dit "ça marche pas".
**Action :** logger avec `debugPrint` ou `dart:developer` :
```dart
} on TimeoutException {
  developer.log('mDNS scan timeout (normal end of window)', name: 'linkup.discovery');
} catch (e, stack) {
  developer.log('mDNS scan error', name: 'linkup.discovery', error: e, stackTrace: stack);
}
```

#### 🟠 `clear()` jamais utilisé — `linkup_discovery.dart:199`
**Catégorie :** Code mort
**Problème :** Méthode publique de l'interface `AgentDiscovery` jamais appelée (vérifié `grep`).
**Action :** soit l'utiliser dans le picker (ex : bouton « Tout effacer »), soit la sortir de l'interface.

#### 🟡 Param `reusePort` du callback ignoré — `linkup_discovery.dart:236-243`
**Catégorie :** Code mort partiel
**Problème :** Le param `bool reusePort = false` est reçu mais pas utilisé (on hardcode `reusePort: false` ligne 243). C'est intentionnel (workaround Android) mais on devrait au moins documenter.
**Avant :**
```dart
static Future<RawDatagramSocket> _socketFactory(
  dynamic host, int port, {
  bool reuseAddress = true,
  bool reusePort = false,  // <-- ignoré
  int ttl = 1,
}) {
  return RawDatagramSocket.bind(host, port,
    reuseAddress: reuseAddress, reusePort: false, ttl: ttl);
}
```
**Après :**
```dart
// Workaround : forçage à false sur Android (le param du package est ignoré).
// Voir https://github.com/flutter/flutter/issues/132333
static Future<RawDatagramSocket> _socketFactory(
  dynamic host, int port, {
  bool reuseAddress = true,
  bool reusePort = false,  // ignoré, voir commentaire
  int ttl = 1,
}) async {
  return RawDatagramSocket.bind(host, port,
    reuseAddress: reuseAddress, reusePort: false, ttl: ttl);
}
```

#### 🟡 Duplication `host` vs `hostname` — `linkup_discovery.dart:131-138`
Voir aussi point modèle (10).
**Problème :** On passe `host: srv.target` ET `hostname: txtProperties['host'] ?? _cleanHost(srv.target)`. Le champ `host` est mort.

---

### 14) `mobile/lib/screens/agent_picker_screen.dart` (354 lignes)

#### 🟠 Fichier trop gros — 354 lignes contenant 4 classes
**Catégorie :** Découpage / structure
**Problème :** Contient `AgentPickerScreen`, `_AgentPickerScreenState`, `_EmptyState`, `_ManualAgentDialog`, `_ManualAgentDialogState`, `_ManualAgentInput`. Au-delà de ~250 lignes, c'est cher à parcourir.
**Action :** extraire :
- `lib/screens/agent_picker/empty_state.dart`
- `lib/screens/agent_picker/manual_agent_dialog.dart`
Garder le screen principal sous 200 lignes.

#### 🟠 Validation IP trop permissive — `agent_picker_screen.dart:298-305`
**Catégorie :** Robustesse / UX
**Problème :** `RegExp(r'^[\w.\-:]+$')` accepte « foobar » comme IP valide. L'user peut soumettre une chaîne arbitraire qui marche jusqu'à l'appel HTTP qui crash.
**Avant :**
```dart
if (!RegExp(r'^[\w.\-:]+$').hasMatch(v)) {
  return 'Caractères invalides';
}
```
**Après :**
```dart
// Validation IPv4 stricte ou hostname mDNS .local
final ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
final hostname = RegExp(r'^[a-zA-Z0-9-]+(\.local)?$');
if (!ipv4.hasMatch(v) && !hostname.hasMatch(v)) {
  return 'Format invalide (ex: 192.168.1.10 ou pc.local)';
}
```

#### 🟠 `_error` jamais réinitialisé au succès — `agent_picker_screen.dart:96-109`
**Catégorie :** UX bug latent
**Problème :** Si un scan échoue (`_error` rempli) puis un suivant réussit, `_error` reste affiché en rouge. `setState(() => _error = null)` est fait au début du scan suivant — donc OK en pratique mais fragile. Surtout, si l'écran reçoit un nouvel agent du stream sans nouveau scan, l'erreur persiste.
**Action :** Quand `_agents.isNotEmpty`, masquer le bloc erreur :
```dart
if (_error != null && _agents.isEmpty)
  Padding(...)
```

#### 🟡 Magic numbers UI — `agent_picker_screen.dart:26-27`
**Catégorie :** Magic numbers
**Problème :** `_autoScanMaxAttempts = 4`, `_autoScanInterval = Duration(seconds: 2)` choisis "à l'œil". OK mais à document : « 4×2s ≃ couvre la latence Wi-Fi typique sur Android au démarrage ».
**Action :** commentaire en tête de classe expliquant ces valeurs.

#### 🟡 `agent_picker_screen.dart:181-186` — recalcul du `subtitleParts` à chaque rebuild
**Catégorie :** Perf mineure
**Problème :** Pour chaque tile rebuilt (ex: au scroll), on rebuild un `<String>[]` et un `.join`. Imperceptible à 10 agents, à voir à 100+ (peu probable mais...).
**Action :** mémoïser dans le modèle :
```dart
String get subtitleParts {
  final parts = <String>[];
  if (hostname != null && hostname != displayName) parts.add(hostname!);
  parts.add('$address:$bridgePort');
  if (version != null) parts.add('v$version');
  return parts.join('  •  ');
}
```

#### 🟡 Internationalisation hardcodée — `agent_picker_screen.dart` partout
**Catégorie :** i18n manquante
**Problème :** Tous les textes sont en français hardcodé. Le plan S24 prévoit i18n FR+EN.
**Action :** rien à faire avant S24, juste savoir que tous ces strings devront passer dans `.arb`.

---

### 15) `mobile/android/.../MainActivity.kt` (67 lignes)

#### 🟡 Lock tag non unique entre versions — `MainActivity.kt:21`
**Catégorie :** Debug
**Problème :** `LOCK_TAG = "linkup-mdns"` — si plusieurs apps Linkup tournent (rare mais possible en dev), elles partagent le tag. Pas un bug mais peu informatif dans `dumpsys wifi`.
**Action :** inclure un suffixe random : `"linkup-mdns-${packageName}"` ou au moins documenter.

---

### 16) Cross-cutting — Architecture vs `stack-roles.md`

#### 🔴 Bridge exposé en LAN au lieu de loopback only
**Source :** `stack-roles.md` ligne 83
> « Python tourne en parallèle de Laravel sur le même PC, écoute sur `127.0.0.1:8765` (**jamais exposé sur le réseau**) »

**Réalité actuelle :** le runbook et le test sur tel obligent à `uvicorn --host 0.0.0.0`. Le LAN sweep côté Flutter attaque directement le bridge. C'est une **divergence majeure de l'archi cible**.

**Tradeoff** :
- Soit on reste à l'archi cible : tel parle TOUJOURS à Laravel (port 8000), qui proxifie vers le bridge. Mais alors le LAN sweep côté tel doit chercher Laravel, pas le bridge.
- Soit on assume que le bridge expose certaines routes (`/health` publique) au LAN et on l'écrit dans le CDC.

**Action recommandée :**
1. Écrire ADR-002.bis « Bridge exposé en LAN sur `/health` uniquement »
2. Faire de `/health` la SEULE route publique du bridge (les autres restent derrière le token Bearer)
3. Documenter dans `Linkup-Tutoriel-Architecture.md`
4. Changer le `LanSweepDiscovery` pour viser **Laravel** (port 8000) au lieu du bridge (port 8765) — ainsi le bridge peut revenir en `127.0.0.1` only

C'est important parce que ça affecte la **politique de pare-feu prod** (S23) et la **sécurité** : un user mal informé peut bloquer 8765 et casser le sweep.

#### 🟠 Pas d'ADR existant pour les décisions S1
**Source :** `Linkup-Plan-Execution.md` Annexe B.2 prévoit ADR-002 « Choix mDNS Linux/Windows »

**Action :** créer `docs/adr/ADR-002-mdns-discovery.md` avant fin S1, en y intégrant :
- Choix de `multicast_dns` côté Flutter
- Choix de `zeroconf` côté Python
- Décision de doubler avec le **LAN sweep** (nouveauté de S1.J4 non prévue au plan)
- Décision sur exposition LAN du bridge (point précédent)

---

### 17) Cross-cutting — `.env.example` (agent + bridge)

#### 🟠 Reverb credentials vides — `agent/.env.example:38-40`
**Catégorie :** Configuration
**Problème :**
```env
REVERB_APP_ID=
REVERB_APP_KEY=
REVERB_APP_SECRET=
```
Au premier `php artisan reverb:install`, ces valeurs sont générées. Mais le nouvel arrivant qui copie `.env.example` → `.env` et essaye de démarrer Reverb sans `artisan reverb:install` aura un crash silencieux.
**Action :** ajouter un commentaire au-dessus :
```env
# Lancer `php artisan reverb:install` pour générer ces 3 valeurs
REVERB_APP_ID=
REVERB_APP_KEY=
REVERB_APP_SECRET=
```

#### 🟡 Pas de validation du bridge token au boot Laravel — `agent/.env.example:75`
**Catégorie :** Sécurité dev
**Problème :** Le token `change-me-to-a-random-32-bytes-base64` est juste une string. Si l'user oublie de le changer, ça marche en local mais c'est public. Côté Laravel, rien ne le valide.
**Action :** un `config/services.php` qui throw si `linkup_bridge.token` matches la valeur par défaut connue. Sécurité par construction.

---

## ✅ Plan d'action recommandé

### 🔴 P0 — Faire cette semaine (S1.J5)

- [ ] **ADR-002** sur mDNS + LAN sweep + exposition bridge (réf. points 16) — bloquant pour la cohérence projet
- [ ] **Fix écrasement `_resolve`** (`linkup_discovery.dart:142`) — bug latent, perte de données sweep
- [ ] **Forcer token bridge sans défaut** ou générer aléatoirement à l'install (`config.py:10`)
- [ ] **Centraliser les ports** dans `lib/config/linkup_ports.dart` — préreq pour ne pas dupliquer dans le futur

### 🟠 P1 — Sprint S2-S3

- [ ] Renommer `MdnsAnnouncer` → `BridgeClient` (Laravel) + adapter tests + doc
- [ ] Extraire `_EmptyState` et `_ManualAgentDialog` du picker dans des fichiers séparés
- [ ] Ajouter `LinkupAgentSource.lanSweep` distinct de `mdns`
- [ ] Ajouter logging Dart `developer.log` dans les catch silencieux
- [ ] Validation IP/hostname stricte dans le dialog manuel
- [ ] Pydantic `Field(ge=1, le=65535)` sur les ports config Python
- [ ] Annulation du sweep au `dispose()`
- [ ] Catch HTTP error dans Laravel sur les routes proxy (503 propre)
- [ ] Supprimer `copyWith`, `clear()`, `bridgeHealth()`, champ `host` redondant (ou les câbler)
- [ ] Validation `POST /api/ping` avec `validate()`
- [ ] Remplacer `except Exception` (`main.py:169`) par exceptions ciblées
- [ ] Commentaires `.env.example` Reverb credentials
- [ ] Lock tag MulticastLock plus parlant

### 🟡 P2 — Backlog

- [ ] Supprimer commentaires verbeux par-import dans `main.py`
- [ ] Documenter `MulticastLock` Android-only en commentaire
- [ ] Documenter le workaround `reusePort` en commentaire
- [ ] Memoïzer `subtitleParts` dans le modèle
- [ ] Supprimer dossier `bridge/app/os/` vide ou y mettre un stub commenté
- [ ] God class `LinkupBrowser` à splitter (post-S3)
- [ ] Magic numbers auto-scan documentés

---

## 🛠️ Outils recommandés (à wirer en CI)

### Python (`bridge/`)
- ✅ `ruff` déjà en place
- ✅ `black` déjà en place
- ➕ `mypy --strict` (typage rigide, manque actuellement)
- ➕ `vulture` (dead code detection)
- ➕ `pip-audit` (CVE deps)

### Laravel (`agent/`)
- ➕ **Larastan / PHPStan niveau 8** (typage strict)
- ➕ **Laravel Pint** (formatter officiel, gratuit)
- ➕ **Rector** (refactor automatique upgrade PHP)
- ➕ `composer audit` en CI

### Flutter (`mobile/`)
- ✅ `flutter analyze` déjà passe
- ➕ **`very_good_analysis`** ou **`flutter_lints`** strict (déjà actif, niveau 6)
- ➕ **`dart_code_metrics`** (complexité cyclomatique, lignes par fonction)
- ➕ **`knip`** ou **`ts-prune`** équivalent Dart → pas vraiment d'équivalent, mais `flutter analyze` détecte la majorité

### Général
- ➕ **`pre-commit`** hooks (déjà prévu par le plan T0.23) à finaliser
- ➕ **`semgrep`** avec règles OWASP pour les passes sécu hors `security-audit`
- ➕ **`jscpd`** pour duplication cross-langage

---

## 📌 Synthèse

Le code est **propre dans l'absolu** : pas de TODO/FIXME en attente, pas de `dd()` ou `console.log` oubliés, pas de credentials en dur (sauf default config bridge), pas de N+1, types présents quasiment partout. La grosse partie des 27 problèmes est du polish ou de la dette préventive normale d'un projet en cours de croissance.

Les **vrais points d'attention** sont :

1. **Architecture** — divergence entre `stack-roles.md` et la réalité d'implémentation (bridge LAN). À acter en ADR avant que ça crée plus de complexité.
2. **Dette de cohérence** — magic ports dupliqués, champ `host`/`hostname` confondus, classe Laravel mal nommée. Trivial à nettoyer, important pour la maintenabilité long terme.
3. **Sécurité dev** — token bridge avec défaut public, validation Laravel manquante sur les inputs. À durcir avant l'alpha publique S6.5.
4. **Robustesse** — un sweep qui survit au dispose, un `_resolve` qui écrase, des catch silencieux. Tout ça est latent aujourd'hui mais sera vu par les premiers users de l'alpha.

**Estimation totale : 6-8h** pour nettoyer toute la liste P0+P1. À planifier sur S1.J5 (P0) + sprint S2-S3 en parallèle des nouvelles features (P1).

> Audit complet et reproductible — refaire `grep -rn "copyWith\|clear()\|bridgeHealth"` dans 2 semaines pour valider que les éléments marqués "dead code" ont bien été utilisés ou supprimés.
