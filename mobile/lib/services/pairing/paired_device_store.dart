import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Un PC appairé, persisté dans le secure storage après approbation (S2.J5).
///
/// Contient tout ce qu'il faut pour se reconnecter automatiquement au
/// lancement suivant sans re-scanner de QR (T2.20-T2.21).
class PairedDevice {
  final String deviceId;
  final String host;
  final int port;
  final String token;
  final String pcPublicKey;
  final String pcFingerprint;
  final String pcName;

  const PairedDevice({
    required this.deviceId,
    required this.host,
    required this.port,
    required this.token,
    required this.pcPublicKey,
    required this.pcFingerprint,
    required this.pcName,
  });

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'host': host,
        'port': port,
        'token': token,
        'pc_public_key': pcPublicKey,
        'pc_fingerprint': pcFingerprint,
        'pc_name': pcName,
      };

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
        deviceId: json['device_id'] as String,
        host: json['host'] as String,
        port: json['port'] as int,
        token: json['token'] as String,
        pcPublicKey: json['pc_public_key'] as String,
        pcFingerprint: json['pc_fingerprint'] as String,
        pcName: json['pc_name'] as String,
      );

  Uri get baseUri => Uri(scheme: 'http', host: host, port: port);
}

/// Persistance du PC appairé dans le Keystore Android.
///
/// Le token est un secret : il ne doit jamais sortir du secure storage. Un
/// seul PC appairé à la fois pour l'alpha LAN (S2) ; le multi-PC viendra plus
/// tard.
class PairedDeviceStore {
  static const String _key = 'linkup.paired_device';

  final FlutterSecureStorage _storage;

  PairedDeviceStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> save(PairedDevice device) async {
    await _storage.write(key: _key, value: jsonEncode(device.toJson()));
  }

  Future<PairedDevice?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PairedDevice.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    }
  }

  Future<bool> exists() async => (await _storage.read(key: _key)) != null;

  Future<void> clear() async => _storage.delete(key: _key);
}
