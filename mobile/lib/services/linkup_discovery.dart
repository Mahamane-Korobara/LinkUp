import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import '../config/linkup_ports.dart';
import '../models/linkup_agent.dart';
import 'agent_discovery.dart';
import 'lan_sweep.dart';
import 'multicast_lock.dart';

/// Service de découverte mDNS pour les agents Linkup sur le LAN.
///
/// Scanne `_linkup._tcp.local.` via `multicast_dns`, résout les SRV pour
/// récupérer host+port, puis les TXT pour extraire `id`, `fp`, `v` et
/// `bridge_port`. Émet la liste courante sur [stream].
class LinkupDiscovery implements AgentDiscovery {
  static const String _serviceType = '_linkup._tcp.local.';

  final MDnsClient _client;
  final LanSweepDiscovery _lanSweep;
  final Duration scanDuration;
  final _agents = <String, LinkupAgent>{};
  final _controller = StreamController<List<LinkupAgent>>.broadcast();

  bool _started = false;
  bool _scanning = false;
  bool _cancelled = false;
  // Dernier message d'erreur loggué — évite le spam quand l'user rescanne
  // plusieurs fois avec la même cause (logcat lisible).
  String? _lastLoggedErrorKey;

  LinkupDiscovery({
    MDnsClient? client,
    LanSweepDiscovery? lanSweep,
    this.scanDuration = const Duration(seconds: 5),
  })  : _client = client ?? MDnsClient(rawDatagramSocketFactory: _socketFactory),
        _lanSweep = lanSweep ?? LanSweepDiscovery();

  /// Stream de la liste courante des agents découverts.
  /// Une nouvelle valeur est émise à chaque ajout/maj.
  @override
  Stream<List<LinkupAgent>> get stream => _controller.stream;

  /// Snapshot synchrone des agents actuellement connus.
  @override
  List<LinkupAgent> get agents => List.unmodifiable(_agents.values);

  /// Acquiert le MulticastLock et démarre le client mDNS.
  @override
  Future<void> start() async {
    if (_started) return;
    await MulticastLock.acquire();
    await _client.start();
    _started = true;
  }

  /// Lance un scan unique et alimente la liste d'agents.
  ///
  /// L'appelant peut le rappeler périodiquement (pull-to-refresh) ou laisser
  /// l'agent expirer naturellement côté bridge Python.
  @override
  Future<void> scanOnce() async {
    if (!_started) await start();
    if (_scanning) return;
    _scanning = true;

    try {
      // On lance mDNS et le balayage HTTP du sous-réseau en parallèle.
      // mDNS marche sur la majorité des LAN ; le sweep prend le relais quand
      // le multicast est bloqué (hotspot Samsung, Wi-Fi public, isolation
      // client). La déduplication par uniqueKey évite les doublons.
      await Future.wait([
        _runMdnsScan(),
        _runLanSweep(),
      ]);
    } finally {
      _scanning = false;
    }
  }

  Future<void> _runMdnsScan() async {
    try {
      await for (final ptr in _client
          .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(_serviceType))
          .timeout(scanDuration, onTimeout: (sink) => sink.close())) {
        await _resolve(ptr.domainName);
      }
    } on TimeoutException {
      // Fin de fenêtre de scan mDNS, on sort proprement.
    } catch (e, stack) {
      _logErrorOnce('mDNS scan failed', e, stack);
    }
  }

  Future<void> _runLanSweep() async {
    try {
      await _lanSweep.sweep(
        isCancelled: () => _cancelled,
        onAgentFound: (agent) {
          // Émission en temps réel : chaque agent trouvé apparaît tout de suite
          // dans la liste, sans attendre la fin du balayage. La fusion préserve
          // les champs déjà connus si mDNS arrive après.
          _mergeAgent(agent);
        },
      );
    } catch (e, stack) {
      // Le sweep est best-effort, on n'interrompt pas le scan global, mais on
      // garde une trace pour debug (adb logcat avec tag `linkup.discovery`).
      _logErrorOnce('LAN sweep failed', e, stack);
    }
  }

  /// Logue l'erreur une seule fois par cause. Si le même type d'erreur revient
  /// sur 5 rescans consécutifs, logcat n'a qu'une ligne au lieu de 5.
  void _logErrorOnce(String message, Object error, StackTrace stack) {
    final key = '$message:${error.runtimeType}:$error';
    if (key == _lastLoggedErrorKey) return;
    _lastLoggedErrorKey = key;
    developer.log(message, name: 'linkup.discovery', error: error, stackTrace: stack);
  }

  Future<void> _resolve(String serviceName) async {
    SrvResourceRecord? srv;
    await for (final record in _client
        .lookup<SrvResourceRecord>(ResourceRecordQuery.service(serviceName))
        .timeout(scanDuration, onTimeout: (sink) => sink.close())) {
      srv = record;
      break;
    }
    if (srv == null) return;

    final txtProperties = await _readTxt(serviceName);

    String? ip;
    await for (final record in _client
        .lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))
        .timeout(scanDuration, onTimeout: (sink) => sink.close())) {
      ip = record.address.address;
      break;
    }
    if (ip == null) return;

    // srv.port = port Reverb annoncé (8080), PAS le port HTTP du bridge.
    // Si le TXT mDNS n'a pas explicitement `bridge_port`, on retombe sur la
    // convention Linkup (`LinkupPorts.bridge`) au lieu d'utiliser srv.port —
    // sinon bridgeHealthUri taperait sur Reverb qui ne répond pas en HTTP.
    final bridgePortRaw = txtProperties['bridge_port'];
    final bridgePort = int.tryParse(bridgePortRaw ?? '') ?? LinkupPorts.bridge;

    // Port HTTP de l'agent Laravel annoncé dans le TXT (8000 dev / 8770 bundle).
    final laravelPort =
        int.tryParse(txtProperties['laravel_port'] ?? '') ?? LinkupPorts.laravel;

    final agent = LinkupAgent(
      instanceName: serviceName,
      address: ip,
      reverbPort: srv.port,
      bridgePort: bridgePort,
      laravelPort: laravelPort,
      agentId: txtProperties['id'],
      fingerprint: txtProperties['fp'],
      version: txtProperties['v'],
      hostname: txtProperties['host'] ?? _cleanHost(srv.target),
      source: LinkupAgentSource.mdns,
    );

    _mergeAgent(agent);
  }

  /// Fusionne un agent dans la liste sans écraser les champs déjà connus.
  ///
  /// Cas typique : le LAN sweep a peuplé `user` et `hostname` via le JSON du
  /// `/health`, puis le scan mDNS revient avec un TXT plus pauvre. Sans merge,
  /// on perdrait ces infos. Règle : on garde la valeur existante quand la
  /// nouvelle est null/vide.
  void _mergeAgent(LinkupAgent next) {
    final existing = _agents[next.uniqueKey];
    if (existing == null) {
      _agents[next.uniqueKey] = next;
      _emit();
      return;
    }
    _agents[next.uniqueKey] = next.copyWith(
      agentId: next.agentId ?? existing.agentId,
      fingerprint: next.fingerprint ?? existing.fingerprint,
      version: next.version ?? existing.version,
      hostname: next.hostname ?? existing.hostname,
      user: next.user ?? existing.user,
    );
    _emit();
  }

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
      // TXT optionnel, pas bloquant.
    }
    return props;
  }

  /// Ajoute un agent saisi manuellement (T1.17).
  ///
  /// L'IP est validée superficiellement (format) et le port doit être > 0.
  @override
  LinkupAgent addManualAgent({
    required String address,
    int bridgePort = LinkupPorts.bridge,
    int reverbPort = LinkupPorts.reverb,
    String? label,
  }) {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Adresse vide');
    }
    if (bridgePort <= 0 || bridgePort > 65535) {
      throw ArgumentError('Port bridge invalide');
    }

    final agent = LinkupAgent(
      instanceName: label ?? 'manual:$trimmed:$bridgePort',
      address: trimmed,
      reverbPort: reverbPort,
      bridgePort: bridgePort,
      source: LinkupAgentSource.manual,
    );
    // Passe par _mergeAgent comme sweep et mDNS : si l'IP saisie correspond à
    // un agent déjà découvert (avec user/hostname riches), on ne perd pas ces
    // champs.
    _mergeAgent(agent);
    return agent;
  }

  /// Arrête le client mDNS, signale au sweep en cours de s'arrêter, libère le
  /// verrou multicast + le client HTTP du sweep. Idempotent.
  @override
  Future<void> dispose() async {
    _cancelled = true;
    if (_started) {
      _client.stop();
      _started = false;
    }
    _lanSweep.close();
    await MulticastLock.release();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_agents.values));
    }
  }

  /// Nettoie un hostname mDNS du type `mahamane-VivoBook.local.` en
  /// `mahamane-VivoBook`.
  String _cleanHost(String raw) {
    var cleaned = raw;
    if (cleaned.endsWith('.')) cleaned = cleaned.substring(0, cleaned.length - 1);
    if (cleaned.endsWith('.local')) {
      cleaned = cleaned.substring(0, cleaned.length - '.local'.length);
    }
    return cleaned;
  }

  /// Custom socket factory passé au [MDnsClient] — workaround Android.
  ///
  /// Le package multicast_dns par défaut appelle `RawDatagramSocket.bind` avec
  /// `reusePort: true`, ce qui plante sur Android (`SocketException: Invalid
  /// argument`). On force `reusePort: false` en ignorant délibérément le
  /// paramètre reçu.
  ///
  /// Voir https://github.com/flutter/flutter/issues/132333
  static Future<RawDatagramSocket> _socketFactory(
    dynamic host,
    int port, {
    bool reuseAddress = true,
    bool reusePort = false, // ignoré, voir docstring
    int ttl = 1,
  }) {
    return RawDatagramSocket.bind(
      host,
      port,
      reuseAddress: reuseAddress,
      reusePort: false,
      ttl: ttl,
    );
  }
}
