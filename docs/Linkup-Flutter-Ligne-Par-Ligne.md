# Linkup — Cote Flutter (S1.J4) ligne par ligne

Ce document explique **tout ce qui a ete ajoute cote mobile/** pour la semaine S1 jour 4 :

- ajout de la decouverte mDNS LAN cote Android (`multicast_dns`)
- pont natif Kotlin pour le `WifiManager.MulticastLock`
- ecran « Selectionner un agent Linkup » avec liste + saisie manuelle de l'IP en fallback

Le but : qu'un autre dev (ou toi dans 3 mois) puisse relire le code sans rien deviner.

---

## 1. Ce que livre S1.J4 dans le plan

Extrait de `Linkup-Plan-Execution.md` :

| Tache | Livrable |
|---|---|
| T1.14 | Lib `multicast_dns` Flutter, scan des `_linkup._tcp` |
| T1.15 | Ecran « Selectionner un agent » liste les resultats |
| T1.16 | Permission Android `CHANGE_WIFI_MULTICAST_STATE` + acquisition `WifiManager.MulticastLock` |
| T1.17 | Saisie manuelle IP en fallback |

Resultat concret : sur un telephone Android sur le meme Wi-Fi qu'un PC qui fait tourner `bridge/`, l'app Linkup voit l'agent apparaitre dans la liste avec son `agent_id`, `fingerprint`, `version`, son IP et son port bridge.

---

## 2. Structure des fichiers ajoutes / modifies

```
mobile/
├── pubspec.yaml                                       (modifie)
├── android/app/src/main/
│   ├── AndroidManifest.xml                            (modifie)
│   └── kotlin/tech/sahelstack/linkup/linkup_mobile/
│       └── MainActivity.kt                            (reecrit)
├── lib/
│   ├── main.dart                                      (reecrit)
│   ├── models/
│   │   └── linkup_agent.dart                          (nouveau)
│   ├── services/
│   │   ├── agent_discovery.dart                       (nouveau)
│   │   ├── multicast_lock.dart                        (nouveau)
│   │   └── linkup_discovery.dart                      (nouveau)
│   └── screens/
│       └── agent_picker_screen.dart                   (nouveau)
└── test/
    ├── widget_test.dart                               (reecrit)
    ├── linkup_agent_test.dart                         (nouveau)
    └── fakes/
        └── fake_discovery.dart                        (nouveau)
```

---

## 3. `pubspec.yaml` — dependances ajoutees

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8

  # Linkup S1.J4 — decouverte mDNS LAN + appel HTTP /api/agent/info
  multicast_dns: ^0.3.2
  http: ^1.2.2
```

### Pourquoi `multicast_dns`

- C'est la lib officielle du team Dart pour faire du mDNS pur Dart.
- Elle ouvre un socket UDP 5353 et envoie des requetes PTR / SRV / TXT / A.
- Pas de plugin natif a maintenir.

### Pourquoi `http`

- Pour appeler plus tard `/api/agent/info` de Laravel ou `/health` du bridge.
- Necessaire pour T1.19 et la suite.

---

## 4. `android/app/src/main/AndroidManifest.xml` — permissions

Ajout en haut du fichier :

```xml
<!-- Linkup S1.J4 — mDNS discovery on LAN -->
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
```

### A quoi sert chacune

| Permission | Role |
|---|---|
| `INTERNET` | Indispensable pour ouvrir n'importe quel socket TCP/UDP |
| `ACCESS_NETWORK_STATE` | Detecter si on est en Wi-Fi ou data (utile plus tard pour basculer en tunnel VPS) |
| `ACCESS_WIFI_STATE` | Lire l'etat Wi-Fi (necessaire pour acceder a `WifiManager`) |
| `CHANGE_WIFI_MULTICAST_STATE` | **Cle**, sans elle on ne peut pas creer un MulticastLock et Android filtre tous les paquets mDNS recus |

---

## 5. `MainActivity.kt` — MulticastLock natif

Sans `MulticastLock`, Android economise la batterie en jetant tous les paquets UDP multicast (dont mDNS sur 224.0.0.251:5353) qui ne sont pas adresses a la machine. Resultat : `multicast_dns` envoie ses requetes, le PC repond, mais le tel ne recoit rien.

Le `MulticastLock` debloque ce filtre.

### Fichier complet

```kotlin
package tech.sahelstack.linkup.linkup_mobile

import android.content.Context
import android.net.wifi.WifiManager
import android.net.wifi.WifiManager.MulticastLock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "linkup/multicast"
        private const val LOCK_TAG = "linkup-mdns"
    }

    private var multicastLock: MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    acquire()
                    result.success(multicastLock?.isHeld == true)
                }
                "release" -> {
                    release()
                    result.success(true)
                }
                "isHeld" -> {
                    result.success(multicastLock?.isHeld == true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun acquire() {
        if (multicastLock?.isHeld == true) return
        val wifiManager = applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lock = wifiManager.createMulticastLock(LOCK_TAG)
        lock.setReferenceCounted(false)
        lock.acquire()
        multicastLock = lock
    }

    private fun release() {
        multicastLock?.takeIf { it.isHeld }?.release()
        multicastLock = null
    }

    override fun onDestroy() {
        release()
        super.onDestroy()
    }
}
```

### Decoupage bloc par bloc

#### `companion object`

- `CHANNEL = "linkup/multicast"` : nom unique du canal natif. Cote Dart on utilise exactement le meme.
- `LOCK_TAG = "linkup-mdns"` : etiquette du lock visible dans les outils de debug Android (`adb shell dumpsys wifi`).

#### `configureFlutterEngine(...)`

- Appele une fois quand l'engine Flutter demarre dans cette Activity.
- Cree un `MethodChannel` branche sur le `binaryMessenger` (le bus de messages Flutter natif <-> Dart).
- Le `setMethodCallHandler` reagit aux 3 methodes qu'on a expose : `acquire`, `release`, `isHeld`.

#### `acquire()`

- Idempotent : si on tient deja le lock, on sort tout de suite.
- Recupere `WifiManager` via `getSystemService(...)`.
- `createMulticastLock(LOCK_TAG)` cree un lock pas encore acquis.
- `setReferenceCounted(false)` : Android n'incremente pas un compteur interne, donc un seul `release()` suffit a tout liberer. Plus simple a raisonner.
- `acquire()` reel.
- On garde la reference dans `multicastLock` pour pouvoir la liberer.

#### `release()`

- Si on tient encore le lock, on le libere.
- On remet `multicastLock = null` pour permettre une future reacquisition propre.

#### `onDestroy()`

- Filet de securite : meme si Dart oublie d'appeler `release`, on libere quand l'Activity est detruite.

---

## 6. `lib/services/multicast_lock.dart` — pont Dart vers Kotlin

```dart
import 'package:flutter/services.dart';

class MulticastLock {
  static const MethodChannel _channel = MethodChannel('linkup/multicast');

  static Future<bool> acquire() async {
    try {
      final result = await _channel.invokeMethod<bool>('acquire');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> release() async {
    try {
      await _channel.invokeMethod<bool>('release');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<bool> isHeld() async {
    try {
      final result = await _channel.invokeMethod<bool>('isHeld');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
```

### Points cles

- `MethodChannel('linkup/multicast')` : doit matcher EXACTEMENT le `CHANNEL` du Kotlin. Une faute de frappe et ca renvoie `MissingPluginException`.
- On rattrape `MissingPluginException` et `PlatformException` :
  - en widget tests il n'y a pas de plateforme native -> on retourne `false` sans crasher
  - sur iOS ou desktop il n'y a pas non plus d'implementation -> meme comportement
- Toutes les methodes sont `static` parce qu'il n'y a qu'UN seul lock par process : pas besoin d'instance.

---

## 7. `lib/models/linkup_agent.dart` — modele de donnees

Un `LinkupAgent` represente UN agent Linkup vu sur le LAN, qu'il vienne du scan mDNS ou de la saisie manuelle.

### Champs

```dart
final String instanceName;   // nom mDNS complet, ex "linkup-abc._linkup._tcp.local."
final String host;           // nom resolu, ex "laptop.local."
final String address;        // IP, ex "192.168.1.42"
final int reverbPort;        // port annonce dans le SRV (Reverb, par convention 8080)
final int bridgePort;        // port HTTP du bridge Python (TXT bridge_port, 8765)
final String? agentId;       // TXT id, ex "linkup-abc12345"
final String? fingerprint;   // TXT fp, hash SHA-256 court de la cle publique
final String? version;       // TXT v, ex "0.1.0"
final LinkupAgentSource source; // mdns ou manual
```

### Methodes utiles

#### `bridgeHealthUri`

```dart
Uri get bridgeHealthUri => Uri.parse('http://$address:$bridgePort/health');
```

URL a appeler pour faire un heartbeat sur le bridge Python. Utile pour valider que l'agent repond avant d'aller plus loin.

#### `agentInfoUri({int laravelPort = 8000})`

```dart
Uri agentInfoUri({int laravelPort = 8000}) =>
    Uri.parse('http://$address:$laravelPort/api/agent/info');
```

URL a appeler pour interroger Laravel. **Pourquoi un parametre `laravelPort` ?**

Parce que mDNS annonce le port Reverb (8080), pas le port HTTP de Laravel (8000). Le bridge ne connait pas la facade Laravel — donc on garde la valeur en dur cote app pour l'instant. Plus tard, on l'ajoutera dans le TXT.

#### `uniqueKey`

```dart
String get uniqueKey => agentId ?? '$address:$bridgePort';
```

Cle stable pour deduper. Si on connait l'agent_id (mDNS) on l'utilise, sinon on retombe sur IP+port.

#### `operator ==` + `hashCode`

Deux agents avec le meme `uniqueKey` sont consideres egaux. Permet d'utiliser un `Set<LinkupAgent>` ou de comparer dans une `List`.

### Enum `LinkupAgentSource`

```dart
enum LinkupAgentSource { mdns, manual }
```

- `mdns` : decouvert via zeroconf (icone wifi dans la liste)
- `manual` : ajoute via le dialog (icone crayon)

---

## 8. `lib/services/agent_discovery.dart` — l'interface

```dart
abstract class AgentDiscovery {
  Stream<List<LinkupAgent>> get stream;
  List<LinkupAgent> get agents;

  Future<void> start();
  Future<void> scanOnce();
  LinkupAgent addManualAgent({
    required String address,
    int bridgePort,
    int reverbPort,
    String? label,
  });
  void clear();
  Future<void> dispose();
}
```

### Pourquoi une interface ?

- L'ecran `AgentPickerScreen` ne doit pas dependre directement de `LinkupDiscovery` (qui ouvre un vrai socket UDP).
- En widget tests on injecte une `FakeDiscovery` qui implemente la meme interface.
- C'est un DIP (Dependency Inversion Principle) tres leger qui change tout pour la testabilite.

---

## 9. `lib/services/linkup_discovery.dart` — le scan mDNS

C'est le plus gros fichier de S1.J4. Decoupe en plusieurs morceaux.

### En-tete

```dart
class LinkupDiscovery implements AgentDiscovery {
  static const String _serviceType = '_linkup._tcp.local.';

  final MDnsClient _client;
  final Duration scanDuration;
  final _agents = <String, LinkupAgent>{};
  final _controller = StreamController<List<LinkupAgent>>.broadcast();

  bool _started = false;
  bool _scanning = false;
```

- `_serviceType` : exactement le meme nom que celui annonce par le bridge Python (`SERVICE_TYPE` dans `bridge/app/services/mdns.py`). Sinon on cherche dans le vide.
- `_client` : l'instance `MDnsClient` du package multicast_dns. On la rend injectable via le constructeur.
- `scanDuration` : duree max d'un scan unique (5 secondes par defaut). Apres ce delai on coupe pour rendre la main a l'UI.
- `_agents` : dictionnaire keyed by `uniqueKey`. Permet d'eviter les doublons et d'updater au lieu d'ajouter.
- `_controller` : stream broadcast qui emet la liste a chaque fois qu'un agent est ajoute ou modifie.

### Constructeur

```dart
LinkupDiscovery({
  MDnsClient? client,
  this.scanDuration = const Duration(seconds: 5),
}) : _client = client ?? MDnsClient(rawDatagramSocketFactory: _socketFactory);
```

Le `rawDatagramSocketFactory` custom force `reusePort: false` sur Android, sinon `RawDatagramSocket.bind` plante avec `Invalid argument`. C'est un workaround connu du package.

### `start()`

```dart
@override
Future<void> start() async {
  if (_started) return;
  await MulticastLock.acquire();
  await _client.start();
  _started = true;
}
```

- Acquiert d'abord le `MulticastLock` natif (sinon scan vide silencieux).
- Demarre le client mDNS (ouvre le socket UDP 5353).
- `_started` garantit qu'on ne demarre qu'une fois.

### `scanOnce()`

```dart
@override
Future<void> scanOnce() async {
  if (!_started) await start();
  if (_scanning) return;
  _scanning = true;

  try {
    await for (final ptr in _client
        .lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(_serviceType))
        .timeout(scanDuration, onTimeout: (sink) => sink.close())) {
      await _resolve(ptr.domainName);
    }
  } on TimeoutException {
    // fin de fenetre de scan, OK
  } finally {
    _scanning = false;
  }
}
```

- **PTR** : pose la question « quels services `_linkup._tcp.local.` existent ? »
- Chaque reponse PTR donne un `domainName` du genre `linkup-abc._linkup._tcp.local.` qu'on resout ensuite.
- Le `.timeout(...)` ferme le stream apres `scanDuration` au lieu d'attendre indefiniment.
- Le flag `_scanning` empeche deux scans en parallele si l'utilisateur tapote « Rescanner ».

### `_resolve(...)`

C'est la phase de resolution SRV + TXT + A.

```dart
SrvResourceRecord? srv;
await for (final record in _client
    .lookup<SrvResourceRecord>(ResourceRecordQuery.service(serviceName))
    .timeout(scanDuration, onTimeout: (sink) => sink.close())) {
  srv = record;
  break;
}
if (srv == null) return;
```

**SRV** donne le nom du host + le port annonce. On prend la premiere reponse et on coupe.

```dart
final txtProperties = await _readTxt(serviceName);
```

**TXT** donne les paires `cle=valeur` (`id`, `fp`, `v`, `bridge_port`). Implementation detaillee plus bas.

```dart
String? ip;
await for (final record in _client
    .lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))
    .timeout(scanDuration, onTimeout: (sink) => sink.close())) {
  ip = record.address.address;
  break;
}
if (ip == null) return;
```

**A** (`addressIPv4`) transforme le hostname (`laptop.local.`) en IP utilisable. Sans ca, on aurait juste le nom, pas l'IP.

```dart
final bridgePortRaw = txtProperties['bridge_port'];
final bridgePort = int.tryParse(bridgePortRaw ?? '') ?? srv.port;

final agent = LinkupAgent(
  instanceName: serviceName,
  host: srv.target,
  address: ip,
  reverbPort: srv.port,
  bridgePort: bridgePort,
  agentId: txtProperties['id'],
  fingerprint: txtProperties['fp'],
  version: txtProperties['v'],
  source: LinkupAgentSource.mdns,
);

_agents[agent.uniqueKey] = agent;
_emit();
```

- Si le TXT contient `bridge_port`, on l'utilise. Sinon on retombe sur le port SRV (compat retro).
- On stocke dans le dict (deduplication via `uniqueKey`).
- On notifie les listeners via `_emit()`.

### `_readTxt(...)`

```dart
Future<Map<String, String>> _readTxt(String serviceName) async {
  final props = <String, String>{};
  try {
    await for (final txt in _client
        .lookup<TxtResourceRecord>(ResourceRecordQuery.text(serviceName))
        .timeout(scanDuration, onTimeout: (sink) => sink.close())) {
      for (final line in txt.text.split('\n')) {
        final separatorIndex = line.indexOf('=');
        if (separatorIndex <= 0) continue;
        final key = line.substring(0, separatorIndex);
        final value = line.substring(separatorIndex + 1);
        props[key] = value;
      }
    }
  } on TimeoutException {
    // TXT optionnel
  }
  return props;
}
```

Le record TXT est une suite de strings `key=value`. On parse au plus simple :
- on cherche le premier `=`
- avant = cle
- apres = valeur

Si l'agent n'envoie pas de TXT, on retourne juste un dict vide — l'agent reste utilisable (juste sans `id`, `fp`, `v`).

### `addManualAgent(...)` — T1.17

```dart
@override
LinkupAgent addManualAgent({
  required String address,
  int bridgePort = 8765,
  int reverbPort = 8080,
  String? label,
}) {
  final trimmed = address.trim();
  if (trimmed.isEmpty) throw ArgumentError('Adresse vide');
  if (bridgePort <= 0 || bridgePort > 65535) {
    throw ArgumentError('Port bridge invalide');
  }
  // ...
}
```

Permet a l'utilisateur d'entrer une IP manuellement quand le multicast est bloque (reseau hotel, Wi-Fi avec isolation client, container). Validation minimale : adresse non vide, port valide.

### `dispose()`

```dart
@override
Future<void> dispose() async {
  if (_started) {
    _client.stop();
    _started = false;
  }
  await MulticastLock.release();
  await _controller.close();
}
```

Important : libere le MulticastLock natif. Sinon Android peut afficher un avertissement « Wi-Fi multicast lock held » dans les outils de debug et drainer la batterie.

### `_socketFactory(...)` — workaround Android

```dart
static Future<RawDatagramSocket> _socketFactory(
  dynamic host,
  int port, {
  bool reuseAddress = true,
  bool reusePort = false,
  int ttl = 1,
}) {
  return RawDatagramSocket.bind(
    host, port,
    reuseAddress: reuseAddress,
    reusePort: false,
    ttl: ttl,
  );
}
```

On force `reusePort: false`. C'est requis sur Android (sinon `SocketException: Invalid argument`). Connu du package, pas une nouveaute Linkup.

---

## 10. `lib/screens/agent_picker_screen.dart` — l'UI

Ecran principal (T1.15). Compose de :

1. Un `AppBar` avec le titre et un bouton « refresh »
2. Une `LinearProgressIndicator` en haut quand un scan est en cours
3. Une liste d'agents (ou un empty state)
4. Un FAB « Saisie manuelle » qui ouvre un dialog (T1.17)

### Cycle de vie

```dart
@override
void initState() {
  super.initState();
  _ownsDiscovery = widget.discovery == null;
  _discovery = widget.discovery ?? LinkupDiscovery();
  _subscription = _discovery.stream.listen((agents) {
    if (!mounted) return;
    setState(() => _agents = agents);
  });
  _agents = _discovery.agents;
  WidgetsBinding.instance.addPostFrameCallback((_) => _runScan());
}
```

- Si l'appelant passe sa propre `discovery` (par exemple un test), on ne la « possede » pas et on ne la disposera pas.
- Sinon on cree une `LinkupDiscovery` reelle.
- On s'abonne au stream pour rafraichir l'UI a chaque nouvel agent.
- On lance un scan apres le premier frame (`postFrameCallback`) pour eviter de bloquer le build.

### `_runScan()`

```dart
Future<void> _runScan() async {
  setState(() {
    _scanning = true;
    _error = null;
  });
  try {
    await _discovery.scanOnce();
  } catch (e) {
    if (!mounted) return;
    setState(() => _error = 'Erreur de scan : $e');
  } finally {
    if (mounted) setState(() => _scanning = false);
  }
}
```

Standard : flag de progression, gestion d'erreur, nettoyage en `finally`.

### Empty state

Affiche une icone, un titre, un texte explicatif :

> Aucun agent detecte
> Verifie que ton PC est sur le meme Wi-Fi et que Linkup tourne.
> Si le multicast est bloque, utilise « Saisie manuelle ».

Et un bouton « Rescanner ». Centre sur l'ecran.

### Liste des agents

```dart
ListView.separated(
  itemCount: _agents.length,
  separatorBuilder: (_, _) => const Divider(height: 1),
  itemBuilder: (context, index) {
    final agent = _agents[index];
    return ListTile(
      leading: Icon(
        agent.source == LinkupAgentSource.mdns
            ? Icons.wifi_tethering
            : Icons.edit_location_alt,
      ),
      title: Text(agent.agentId ?? agent.instanceName),
      subtitle: Text(
        '${agent.address}:${agent.bridgePort}'
        '${agent.fingerprint != null ? '  •  fp:${agent.fingerprint!.substring(0, agent.fingerprint!.length.clamp(0, 8))}' : ''}'
        '${agent.version != null ? '  •  v${agent.version}' : ''}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _notifySelection(agent),
    );
  },
);
```

- Icone differente selon la source (`mdns` vs `manual`)
- Titre = `agent_id` quand on l'a, sinon le nom mDNS complet
- Sous-titre = `ip:port  •  fp:xxxxxxxx  •  v0.1.0`
- Tap = remonte la selection au parent via `onAgentSelected`

### Dialog de saisie manuelle

`_ManualAgentDialog` est un `StatefulWidget` interne avec deux `TextFormField` :

- IP locale du PC (validation : non vide, caracteres autorises `[\w.\-:]`)
- Port du bridge (validation : entier entre 1 et 65535)

Le formulaire est valide avant de fermer le dialog. Le resultat est un petit DTO `_ManualAgentInput` que l'ecran transforme en agent via `addManualAgent`.

---

## 11. `lib/main.dart` — le point d'entree

```dart
void main() {
  runApp(const LinkupApp());
}

class LinkupApp extends StatelessWidget {
  const LinkupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Linkup',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: AgentPickerScreen(
        onAgentSelected: (agent) => _showAgentSelected(context, agent),
      ),
    );
  }

  void _showAgentSelected(BuildContext context, LinkupAgent agent) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Agent selectionne : ${agent.agentId ?? agent.address} '
          '(${agent.address}:${agent.bridgePort})',
        ),
      ),
    );
  }
}
```

- On a vire tout le code « compteur » du scaffolding de base.
- L'app demarre directement sur l'ecran picker.
- Quand l'utilisateur tape un agent, on snackbar pour confirmer.
- T1.19 (ecran detail qui appelle `/api/agent/info`) remplacera ce snackbar.

---

## 12. Tests

### `test/linkup_agent_test.dart` — 5 tests modele

| Test | Verifie |
|---|---|
| `uniqueKey prefers agentId when available` | agentId est utilise en priorite |
| `uniqueKey falls back to address:port` | fallback quand agentId est null |
| `bridgeHealthUri points to the bridge port` | URL construite correctement |
| `agentInfoUri targets Laravel /api/agent/info` | URL Laravel + parametre `laravelPort` |
| `two agents with the same uniqueKey are equal` | egalite + hashCode |

### `test/widget_test.dart` — 3 tests UI

| Test | Verifie |
|---|---|
| `Empty state shows hint and rescan button` | Quand pas d'agent, l'empty state s'affiche |
| `Discovered agents render in the list` | Une fois `emit()` appele, le tile apparait |
| `Tapping an agent calls onAgentSelected` | Le tap remonte bien au parent |

### `test/fakes/fake_discovery.dart`

Implementation manuelle de `AgentDiscovery` qui :
- Stocke une liste mutable
- Expose `emit(List<LinkupAgent>)` pour pousser des donnees depuis les tests
- Compte les appels (`scanCount`, `startCount`, etc.) pour les assertions
- Ne touche jamais au socket UDP ni au MethodChannel natif

C'est la « doublure de test » qui rend `AgentPickerScreen` testable hors device.

---

## 13. Resultats des tests

```bash
cd mobile
flutter pub get
flutter analyze    # 0 issue
flutter test       # 8/8 verts en ~1s
```

Cote bridge Python : 13/13 tests pytest verts (inchanges, on n'a pas touche au Python).

---

## 14. Flux complet bout-en-bout (ASCII)

```text
                 PC qui fait tourner bridge/
                          |
                          | annonce _linkup._tcp.local. via mDNS
                          | TXT: id=linkup-xxxx fp=... v=0.1.0 bridge_port=8765
                          | port SRV: 8080 (Reverb)
                          |
                          v
                  Wi-Fi local (multicast UDP 5353)
                          |
                          v
        +----------------------------------------+
        |   Telephone Android (app Linkup)       |
        |                                        |
        |  MainActivity.kt                       |
        |  +--- MulticastLock natif (acquis)     |
        |                                        |
        |  Dart side                             |
        |  +--- LinkupDiscovery.scanOnce()       |
        |       +--- PTR _linkup._tcp.local.     |
        |       +--- SRV <name>                   |
        |       +--- TXT <name>                   |
        |       +--- A <hostname>                 |
        |                                        |
        |  AgentPickerScreen                     |
        |  +--- liste avec icone, id, ip:port    |
        |  +--- FAB "Saisie manuelle" en fallback|
        +----------------------------------------+
```

---

## 15. Pannes les plus courantes

### 15.1 Aucun agent ne s'affiche

Verifier dans l'ordre :

1. Le bridge tourne sur le PC (`curl http://127.0.0.1:8765/health`)
2. Le PC et le tel sont sur le MEME Wi-Fi
3. Le Wi-Fi n'isole pas les clients (frequent dans les hotels, lieux publics)
4. Sur Android, le `MulticastLock` a bien ete acquis (chercher « linkup-mdns » dans `adb shell dumpsys wifi`)
5. Le pare-feu PC autorise UDP 5353 entrant et sortant

Si rien ne marche, utiliser la saisie manuelle :
- IP du PC (visible avec `ip addr` ou `ipconfig`)
- Port 8765

### 15.2 « MissingPluginException » dans les tests

Normal en widget test (pas de plateforme native). C'est attrape silencieusement par `MulticastLock.acquire()` qui retourne `false`.

### 15.3 `flutter pub get` qui foire

Verifier la version de Flutter (`flutter --version`). Linkup cible Flutter 3.11+ / Dart 3.11+.

### 15.4 `Invalid argument` au demarrage du scan

C'est le bug `reusePort` du package multicast_dns. Le `_socketFactory` custom dans `LinkupDiscovery` le contourne en forcant `reusePort: false`. Si tu instancies un autre `MDnsClient` quelque part, n'oublie pas la meme bidouille.

---

## 16. Ce qui reste a faire (S1.J5)

| Tache | Description |
|---|---|
| T1.18 | `/api/agent/info` retourne nom+empreinte — **deja fait** dans `agent/routes/api.php` |
| T1.19 | Ecran detail Flutter qui appelle `/api/agent/info` apres selection |
| T1.20 | Test manuel : 2 PC sur le meme Wi-Fi, Flutter decouvre les deux |
| T1.21 | ADR-002 « Choix mDNS Linux/Windows » dans `docs/adr/` |

Pour T1.19, prevoir un `AgentDetailScreen` qui :
- recoit un `LinkupAgent`
- appelle `agent.agentInfoUri()` via `package:http`
- affiche un loader, puis le JSON formate (nom, fingerprint, version, ports)
- offre un bouton « Sauvegarder cet agent » (preparation pour S2 pairing)

---

## 17. Resume en une phrase

```text
S1.J4 = telephone Android voit les agents Linkup sur le LAN via mDNS reel,
avec MulticastLock natif, ecran liste propre, fallback saisie manuelle,
et tout est teste sans avoir besoin d'un vrai device.
```
