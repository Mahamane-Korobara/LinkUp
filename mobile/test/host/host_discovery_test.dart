import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:linkup_mobile/models/linkup_agent.dart';
import 'package:linkup_mobile/services/crypto/key_manager.dart';
import 'package:linkup_mobile/services/host/host_advertise.dart';
import 'package:linkup_mobile/services/host/host_identity.dart';
import 'package:linkup_mobile/services/host/host_router.dart';
import 'package:linkup_mobile/services/host/host_server.dart';
import 'package:linkup_mobile/services/lan_sweep.dart';

/// FlutterSecureStorage fake in-memory (mêmes raisons que key_manager_test).
class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String?> _data = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}

/// Réserve un port libre puis le relâche : on l'utilise pour lier l'hôte ET
/// l'annoncer (en prod le port est fixe = 8765, ici on en prend un libre).
Future<int> _freePort() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return port;
}

Future<HostServer> _startHost(int port, {String name = 'Pixel Test'}) async {
  final storage = _MemoryStorage();
  final identity = HostIdentity(
    storage: storage,
    keys: KeyManager(storage: storage),
    deviceName: name,
  );
  final server = HostServer(
    router: HostRouter(
      advertise: HostAdvertise(identity: identity, listenPort: port),
    ),
    address: InternetAddress.loopbackIPv4,
    port: port,
  );
  await server.start();
  return server;
}

void main() {
  test('le pair découvre l\'hôte via /health (contrat LanSweepDiscovery)', () async {
    final port = await _freePort();
    final server = await _startHost(port, name: 'Pixel Hôte');
    addTearDown(server.stop);

    final sweep = LanSweepDiscovery(
      bridgePort: port,
      requestTimeout: const Duration(seconds: 2),
    );
    final agent = await sweep.probe('127.0.0.1');

    expect(agent, isNotNull, reason: 'le sweep doit accepter service==linkup-bridge');
    expect(agent!.source, LinkupAgentSource.lanSweep);
    // L'hôte n'a qu'un port → laravel_port doit pointer sur ce même port.
    expect(agent.laravelPort, port);
    expect(agent.bridgePort, port);
    expect(agent.user, 'Pixel Hôte');
    expect(agent.agentId, isNotNull);
  });

  test('/api/agent/info expose nom, fingerprint, agent_id, bridge_port', () async {
    final port = await _freePort();
    final server = await _startHost(port, name: 'Galaxy Hôte');
    addTearDown(server.stop);

    final res = await http
        .get(Uri.parse('http://127.0.0.1:$port/api/agent/info'))
        .timeout(const Duration(seconds: 2));

    expect(res.statusCode, 200);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['name'], 'Galaxy Hôte');
    expect(body['bridge_port'], port);
    expect((body['fingerprint'] as String), hasLength(8));
    expect(body['agent_id'], isNotNull);
  });

  test('un chemin inconnu renvoie 404', () async {
    final port = await _freePort();
    final server = await _startHost(port);
    addTearDown(server.stop);

    final res = await http
        .get(Uri.parse('http://127.0.0.1:$port/inconnu'))
        .timeout(const Duration(seconds: 2));

    expect(res.statusCode, 404);
  });
}
