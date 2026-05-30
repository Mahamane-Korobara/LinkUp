import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../config/linkup_ports.dart';
import '../models/linkup_agent.dart';

/// Balaye en parallele les 254 IPs du sous-reseau local pour trouver des bridges
/// Linkup en frappant `http://<ip>:<bridgePort>/health`.
///
/// Sert de fallback quand le multicast mDNS est bloque (hotspot Samsung, Wi-Fi
/// public, isolation client). Invisible pour l'utilisateur final.
///
/// **Temps d'exécution :** en pratique 2-5 s sur un LAN normal (la plupart des
/// IPs retournent `connection refused` immédiatement). **Worst case ~24 s** si
/// chaque IP atteint son timeout + retry (typique d'un AP très saturé) : 8
/// batches × 1.5 s × 2 essais. L'appelant doit prévoir une fenêtre auto-scan
/// suffisamment large.
class LanSweepDiscovery {
  final http.Client _client;
  final bool _ownsClient;
  final int bridgePort;
  final Duration requestTimeout;
  final Duration retryBackoff;
  final int maxParallel;

  LanSweepDiscovery({
    http.Client? client,
    this.bridgePort = LinkupPorts.bridge,
    // 1500ms : assez large pour absorber la congestion sur un hotspot tel
    // (l'AP traite N requêtes concurrentes en série). 600ms causait des
    // timeouts faux-positifs sur les IPs « lointaines » du subnet.
    this.requestTimeout = const Duration(milliseconds: 1500),
    // 150ms de pause avant le retry : laisse à l'AP saturé le temps de
    // dépiler ses connexions plutôt que de retaper instantanément.
    this.retryBackoff = const Duration(milliseconds: 150),
    // 32 plutôt que 64 : 8 batches au lieu de 4, mais moins de pression sur
    // l'AP du hotspot tel. Net : plus rapide qu'on le pense (moins de retries
    // dus à la congestion).
    this.maxParallel = 32,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// Lance le balayage. Si [onAgentFound] est fourni, chaque agent est
  /// notifie des qu'il est detecte (UX progressive). Le Future ne se resout
  /// qu'une fois tous les tests termines (ou que [isCancelled] retourne true).
  ///
  /// [isCancelled] est interroge entre chaque batch HTTP : permet a l'appelant
  /// d'interrompre proprement le sweep quand le widget est dispose, sans
  /// attendre les 254 timeouts.
  ///
  /// Si on ne peut pas determiner l'IP locale, le balayage est sans effet.
  Future<List<LinkupAgent>> sweep({
    void Function(LinkupAgent agent)? onAgentFound,
    bool Function()? isCancelled,
  }) async {
    final localIp = await _localIPv4();
    if (localIp == null) return const [];

    final subnet = _subnet24(localIp);
    if (subnet == null) return const [];

    final discovered = <LinkupAgent>[];
    final ips = <String>[];
    for (int i = 1; i <= 254; i++) {
      final ip = '$subnet.$i';
      if (ip == localIp) continue;
      ips.add(ip);
    }

    developer.log(
      'sweep start: subnet=$subnet.0/24, ${ips.length} IPs, '
      'batchSize=$maxParallel, timeout=${requestTimeout.inMilliseconds}ms',
      name: 'linkup.sweep',
    );

    for (int i = 0; i < ips.length; i += maxParallel) {
      if (isCancelled?.call() == true) return discovered;
      final batch = ips.skip(i).take(maxParallel).toList();
      final results = await Future.wait(batch.map(probe));
      if (isCancelled?.call() == true) return discovered;

      int foundInBatch = 0;
      for (final agent in results) {
        if (agent == null) continue;
        foundInBatch++;
        discovered.add(agent);
        if (onAgentFound != null) onAgentFound(agent);
      }
      // Log de batch en niveau FINE (500) — visible si on filtre par tag,
      // mais hors view par défaut pour ne pas spammer logcat sur rescan.
      developer.log(
        'batch [${batch.first}..${batch.last}] : $foundInBatch agent(s)',
        name: 'linkup.sweep',
        level: 500,
      );
    }

    developer.log(
      'sweep done: ${discovered.length} total agent(s)',
      name: 'linkup.sweep',
    );
    return discovered;
  }

  /// Hit `/health` avec un retry sur timeout (le hotspot tel peut être lent
  /// à la première salve, mais répond à la seconde après backoff).
  ///
  /// Exposé `@visibleForTesting` car la logique de retry est critique et
  /// mérite des tests unitaires directs.
  @visibleForTesting
  Future<LinkupAgent?> probe(String ip) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        return await _probeOnce(ip);
      } on TimeoutException {
        if (attempt == 1) return null;
        // Backoff : laisse l'AP saturé respirer avant de retaper.
        await Future.delayed(retryBackoff);
        continue;
      }
    }
    return null;
  }

  Future<LinkupAgent?> _probeOnce(String ip) async {
    final uri = Uri.parse('http://$ip:$bridgePort/health');
    try {
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'}).timeout(
        requestTimeout,
      );
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) return null;
      if (payload['service'] != 'linkup-bridge') return null;
      return LinkupAgent(
        instanceName: '${payload['agent_id'] ?? ip}._linkup._tcp.local.',
        address: ip,
        reverbPort: LinkupPorts.reverb,
        bridgePort: bridgePort,
        agentId: payload['agent_id'] as String?,
        version: payload['version'] as String?,
        hostname: payload['host'] as String?,
        user: payload['user'] as String?,
        source: LinkupAgentSource.lanSweep,
      );
    } on SocketException {
      return null;
    } on http.ClientException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<String?> _localIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      // Priorise les interfaces Wi-Fi (wlan0, swlan0 sur Samsung) sur les
      // interfaces cellular (rmnet*). Sans ça, sur un tel avec data mobile +
      // Wi-Fi, on peut tomber sur l'IP 10.x.x.x du carrier et balayer 254 IPs
      // qui n'aboutissent pas.
      interfaces.sort((a, b) {
        final aWifi = isLikelyWifiInterface(a.name);
        final bWifi = isLikelyWifiInterface(b.name);
        if (aWifi == bWifi) return 0;
        return aWifi ? -1 : 1;
      });

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (_subnet24(ip) != null) return ip;
        }
      }
    } on SocketException {
      return null;
    }
    return null;
  }

  /// Vrai si le nom d'interface ressemble à du Wi-Fi.
  ///
  /// Accepte : `wlan*` (Linux/Android), `swlan*` (Samsung hotspot), `wifi`,
  /// `en0`/`en1` (macOS/iOS Wi-Fi). Refuse `enp*`/`eno*`/`ens*` (Ethernet
  /// Linux) qui partagent le préfixe `en` mais ne sont pas Wi-Fi.
  ///
  /// Public + static pour être unit-testable sans monter de socket.
  static bool isLikelyWifiInterface(String name) {
    final lower = name.toLowerCase();
    if (lower.startsWith('wlan')) return true;
    if (lower.startsWith('swlan')) return true;
    if (lower == 'wifi') return true;
    // macOS/iOS Wi-Fi : en0, en1 — pattern `en` + digit uniquement.
    if (RegExp(r'^en\d+$').hasMatch(lower)) return true;
    return false;
  }

  /// Extrait `a.b.c` d'une IPv4 `a.b.c.d`. Retourne null si invalide.
  /// Valide aussi que chaque octet est dans [0, 255].
  String? _subnet24(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return null;
    }
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  /// Libère le client HTTP interne si LanSweepDiscovery l'a créé lui-même.
  /// À appeler depuis `LinkupDiscovery.dispose()`.
  void close() {
    if (_ownsClient) _client.close();
  }
}
