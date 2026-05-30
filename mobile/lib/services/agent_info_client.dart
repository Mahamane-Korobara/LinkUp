import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/linkup_ports.dart';
import '../models/linkup_agent.dart';

/// Réponse `/api/agent/info` de Laravel.
class AgentInfo {
  final String name;
  final String fingerprint;
  final String? agentId;
  final String version;
  final int? reverbPort;
  final int? bridgePort;
  final String source;

  const AgentInfo({
    required this.name,
    required this.fingerprint,
    required this.version,
    required this.source,
    this.agentId,
    this.reverbPort,
    this.bridgePort,
  });

  factory AgentInfo.fromJson(Map<String, dynamic> json) => AgentInfo(
        name: json['name'] as String? ?? 'unknown',
        fingerprint: json['fingerprint'] as String? ?? 'pending',
        agentId: json['agent_id'] as String?,
        version: json['version'] as String? ?? '?',
        reverbPort: json['reverb_port'] as int?,
        bridgePort: json['bridge_port'] as int?,
        source: json['source'] as String? ?? 'unknown',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentInfo &&
          other.name == name &&
          other.fingerprint == fingerprint &&
          other.agentId == agentId &&
          other.version == version &&
          other.reverbPort == reverbPort &&
          other.bridgePort == bridgePort &&
          other.source == source;

  @override
  int get hashCode => Object.hash(
        name,
        fingerprint,
        agentId,
        version,
        reverbPort,
        bridgePort,
        source,
      );
}

/// Surface minimale d'un fetcher d'info agent. Permet d'injecter un fake
/// dans les widget tests de `AgentDetailScreen` sans toucher au réseau.
abstract class AgentInfoFetcher {
  Future<AgentInfo> fetch(LinkupAgent agent);
  void close();
}

/// Récupère les infos riches d'un agent via son Laravel `/api/agent/info`.
class AgentInfoClient implements AgentInfoFetcher {
  final http.Client _client;
  final Duration timeout;
  final int laravelPort;

  AgentInfoClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 3),
    this.laravelPort = LinkupPorts.laravel,
  }) : _client = client ?? http.Client();

  /// Appelle Laravel sur le PC du [agent].
  ///
  /// Throws [AgentInfoUnavailable] si Laravel ne répond pas (PC éteint,
  /// firewall, port 8000 pas ouvert, bridge down).
  @override
  Future<AgentInfo> fetch(LinkupAgent agent) async {
    final uri = agent.agentInfoUri(laravelPort: laravelPort);
    try {
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'}).timeout(timeout);
      if (response.statusCode == 503) {
        throw AgentInfoUnavailable(
          'Le bridge Python du PC distant ne répond pas (Laravel renvoie 503).',
        );
      }
      if (response.statusCode != 200) {
        throw AgentInfoUnavailable(
          'Laravel a répondu ${response.statusCode}.',
        );
      }
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        throw AgentInfoUnavailable('Réponse JSON inattendue.');
      }
      return AgentInfo.fromJson(payload);
    } on TimeoutException {
      throw AgentInfoUnavailable('Pas de réponse en ${timeout.inSeconds}s.');
    } on SocketException catch (e) {
      throw AgentInfoUnavailable('Connexion refusée : ${e.message}');
    } on http.ClientException catch (e) {
      throw AgentInfoUnavailable('Erreur HTTP : ${e.message}');
    } on FormatException {
      throw AgentInfoUnavailable('JSON invalide.');
    }
  }

  @override
  void close() => _client.close();
}

/// Levée quand l'info ne peut pas être récupérée, avec un message affichable.
class AgentInfoUnavailable implements Exception {
  final String message;
  const AgentInfoUnavailable(this.message);
  @override
  String toString() => 'AgentInfoUnavailable: $message';
}
