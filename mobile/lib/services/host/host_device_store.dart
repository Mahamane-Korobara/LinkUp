import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// État d'un pair côté hôte.
enum HostDeviceStatus { pending, approved, rejected }

HostDeviceStatus _statusFromString(String? s) => switch (s) {
      'approved' => HostDeviceStatus.approved,
      'rejected' => HostDeviceStatus.rejected,
      _ => HostDeviceStatus.pending,
    };

/// Un téléphone pair connu de l'hôte (en attente, approuvé ou refusé).
class HostDevice {
  final String deviceId;
  final String telPublicKey; // base64
  final String name;
  final String model;
  final String platform;
  final String osVersion;
  final HostDeviceStatus status;

  /// Token persistant délivré à l'approbation (secret). Null tant que pending.
  final String? token;

  /// Vrai tant que le pair n'a pas encore récupéré son token via `/poll`
  /// (le token n'est livré qu'une fois, comme sur le PC).
  final bool tokenDelivered;

  const HostDevice({
    required this.deviceId,
    required this.telPublicKey,
    required this.name,
    required this.model,
    required this.platform,
    required this.osVersion,
    required this.status,
    this.token,
    this.tokenDelivered = false,
  });

  HostDevice copyWith({
    HostDeviceStatus? status,
    String? token,
    bool? tokenDelivered,
  }) =>
      HostDevice(
        deviceId: deviceId,
        telPublicKey: telPublicKey,
        name: name,
        model: model,
        platform: platform,
        osVersion: osVersion,
        status: status ?? this.status,
        token: token ?? this.token,
        tokenDelivered: tokenDelivered ?? this.tokenDelivered,
      );

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'tel_public_key': telPublicKey,
        'name': name,
        'model': model,
        'platform': platform,
        'os': osVersion,
        'status': status.name,
        'token': token,
        'token_delivered': tokenDelivered,
      };

  factory HostDevice.fromJson(Map<String, dynamic> j) => HostDevice(
        deviceId: j['device_id'] as String,
        telPublicKey: j['tel_public_key'] as String,
        name: j['name'] as String? ?? 'Téléphone',
        model: j['model'] as String? ?? '',
        platform: j['platform'] as String? ?? '',
        osVersion: j['os'] as String? ?? '',
        status: _statusFromString(j['status'] as String?),
        token: j['token'] as String?,
        tokenDelivered: j['token_delivered'] as bool? ?? false,
      );
}

/// Registre persistant des pairs côté hôte (secure storage).
///
/// Stocké sous une seule clé JSON `{deviceId: {...}}`. Le token est un secret →
/// il ne quitte jamais ce stockage (Keystore Android). Mono-isolate (le serveur
/// hôte tourne dans un seul isolate) → pas de verrou nécessaire.
class HostDeviceStore {
  static const String _key = 'linkup.host.devices';

  final FlutterSecureStorage _storage;

  HostDeviceStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<Map<String, HostDevice>> _readAll() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (k, v) => MapEntry(k, HostDevice.fromJson(v as Map<String, dynamic>)),
      );
    } on FormatException {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, HostDevice> devices) async {
    final map = devices.map((k, v) => MapEntry(k, v.toJson()));
    await _storage.write(key: _key, value: jsonEncode(map));
  }

  Future<HostDevice?> get(String deviceId) async => (await _readAll())[deviceId];

  Future<List<HostDevice>> list() async => (await _readAll()).values.toList();

  Future<List<HostDevice>> listPending() async =>
      (await list()).where((d) => d.status == HostDeviceStatus.pending).toList();

  Future<List<HostDevice>> listApproved() async =>
      (await list()).where((d) => d.status == HostDeviceStatus.approved).toList();

  /// Enregistre/rafraîchit un pair en attente après un handshake valide. Si le
  /// device existe déjà (re-scan), on conserve son statut/token existants.
  Future<HostDevice> upsertPending(HostDevice device) async {
    final all = await _readAll();
    final existing = all[device.deviceId];
    final merged = existing == null
        ? device
        : existing.copyWith(); // déjà connu → on ne régresse pas le statut
    all[device.deviceId] = merged;
    await _writeAll(all);
    return merged;
  }

  /// Approuve un pair : génère et stocke son token persistant.
  Future<HostDevice?> approve(String deviceId) async {
    final all = await _readAll();
    final d = all[deviceId];
    if (d == null) return null;
    final updated = d.copyWith(
      status: HostDeviceStatus.approved,
      token: d.token ?? _randomToken(),
      tokenDelivered: false,
    );
    all[deviceId] = updated;
    await _writeAll(all);
    return updated;
  }

  Future<void> reject(String deviceId) async {
    final all = await _readAll();
    final d = all[deviceId];
    if (d == null) return;
    all[deviceId] = d.copyWith(status: HostDeviceStatus.rejected, token: null);
    await _writeAll(all);
  }

  /// Marque le token comme livré (après une poll `approved` qui l'a renvoyé).
  Future<void> markTokenDelivered(String deviceId) async {
    final all = await _readAll();
    final d = all[deviceId];
    if (d == null || d.tokenDelivered) return;
    all[deviceId] = d.copyWith(tokenDelivered: true);
    await _writeAll(all);
  }

  /// Vérifie qu'un couple (deviceId, token) correspond à un pair approuvé.
  Future<bool> verifyToken(String deviceId, String token) async {
    final d = await get(deviceId);
    return d != null &&
        d.status == HostDeviceStatus.approved &&
        d.token != null &&
        d.token == token;
  }

  Future<void> remove(String deviceId) async {
    final all = await _readAll();
    all.remove(deviceId);
    await _writeAll(all);
  }

  Future<void> clear() async => _storage.delete(key: _key);

  static String _randomToken() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes);
  }
}
