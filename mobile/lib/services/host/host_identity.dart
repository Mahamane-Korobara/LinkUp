import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/hex.dart';
import '../crypto/key_manager.dart';

/// Identité du téléphone quand il joue le rôle serveur (Mode Hôte).
///
/// Fournit ce que le PC exposait via le bridge + Laravel : un `agent_id` stable
/// (persisté), un nom d'affichage, une version, et l'empreinte / clé publique
/// Ed25519 (réutilise [KeyManager], la même paire que pour le pairing client).
class HostIdentity {
  static const String _agentIdKey = 'linkup.host.agent_id';

  /// Version annoncée dans `/health` et `/api/agent/info`.
  static const String version = '0.1.0';

  final FlutterSecureStorage _storage;
  final KeyManager keys;

  /// Nom lisible de l'appareil hôte (ex. « Pixel 7 »). Si null, on retombe sur
  /// le hostname système. Fourni par l'UI via `DeviceMetadata` sur l'appareil.
  final String? deviceName;

  HostIdentity({
    FlutterSecureStorage? storage,
    KeyManager? keys,
    this.deviceName,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        keys = keys ?? KeyManager();

  /// `agent_id` stable : généré une fois puis persisté (identifie l'hôte dans la
  /// découverte du pair, comme l'agent_id du bridge PC).
  Future<String> agentId() async {
    final existing = await _storage.read(key: _agentIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _randomHex(8);
    await _storage.write(key: _agentIdKey, value: id);
    return id;
  }

  /// Empreinte SHA-256 courte de la clé publique (affichée à l'appairage).
  Future<String> fingerprint() => keys.fingerprint();

  /// Clé publique base64 (renvoyée au pair pendant le handshake → `pc_public_key`).
  Future<String> publicKeyBase64() => keys.publicKeyBase64();

  /// Nom d'affichage : nom de l'appareil fourni, sinon le hostname système.
  String name() {
    final n = deviceName?.trim();
    if (n != null && n.isNotEmpty) return n;
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'LinkUp';
    }
  }

  static String _randomHex(int bytes) {
    final rnd = Random.secure();
    return hexEncode(List<int>.generate(bytes, (_) => rnd.nextInt(256)));
  }
}
