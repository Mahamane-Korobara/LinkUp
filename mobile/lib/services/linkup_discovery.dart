import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

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
    }
  }

  Future<void> _runLanSweep() async {
    try {
      await _lanSweep.sweep(
        onAgentFound: (agent) {
          // Émission en temps réel : chaque agent trouvé apparaît tout de suite
          // dans la liste, sans attendre la fin du balayage.
          final added = !_agents.containsKey(agent.uniqueKey);
          _agents.putIfAbsent(agent.uniqueKey, () => agent);
          if (added) _emit();
        },
      );
    } catch (_) {
      // Le sweep est best-effort, on n'interrompt pas le scan global.
    }
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
      hostname: txtProperties['host'] ?? _cleanHost(srv.target),
      source: LinkupAgentSource.mdns,
    );

    _agents[agent.uniqueKey] = agent;
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
    int bridgePort = 8765,
    int reverbPort = 8080,
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
      host: trimmed,
      address: trimmed,
      reverbPort: reverbPort,
      bridgePort: bridgePort,
      source: LinkupAgentSource.manual,
    );
    _agents[agent.uniqueKey] = agent;
    _emit();
    return agent;
  }

  /// Vide la liste connue (sans arrêter le client).
  @override
  void clear() {
    _agents.clear();
    _emit();
  }

  /// Arrête le client mDNS et libère le verrou.
  @override
  Future<void> dispose() async {
    if (_started) {
      _client.stop();
      _started = false;
    }
    await MulticastLock.release();
    await _controller.close();
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

  static Future<RawDatagramSocket> _socketFactory(
    dynamic host,
    int port, {
    bool reuseAddress = true,
    bool reusePort = false,
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
