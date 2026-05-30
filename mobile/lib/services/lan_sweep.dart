import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/linkup_ports.dart';
import '../models/linkup_agent.dart';

/// Balaye en parallele les 254 IPs du sous-reseau local pour trouver des bridges
/// Linkup en frappant `http://<ip>:<bridgePort>/health`.
///
/// Sert de fallback quand le multicast mDNS est bloque (hotspot Samsung, Wi-Fi
/// public, isolation client). Invisible pour l'utilisateur final.
class LanSweepDiscovery {
  final int bridgePort;
  final Duration requestTimeout;
  final int maxParallel;

  LanSweepDiscovery({
    this.bridgePort = LinkupPorts.bridge,
    this.requestTimeout = const Duration(milliseconds: 600),
    this.maxParallel = 64,
  });

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

    for (int i = 0; i < ips.length; i += maxParallel) {
      if (isCancelled?.call() == true) return discovered;
      final batch = ips.skip(i).take(maxParallel);
      final results = await Future.wait(batch.map(_probe));
      if (isCancelled?.call() == true) return discovered;
      for (final agent in results) {
        if (agent == null) continue;
        discovered.add(agent);
        if (onAgentFound != null) onAgentFound(agent);
      }
    }

    return discovered;
  }

  Future<LinkupAgent?> _probe(String ip) async {
    final uri = Uri.parse('http://$ip:$bridgePort/health');
    try {
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(requestTimeout);
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
    } on TimeoutException {
      return null;
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

  String? _subnet24(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

}
