import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

import '../crypto/key_manager.dart';
import 'host_device_store.dart';
import 'host_http.dart';
import 'host_identity.dart';

/// Appairage côté hôte : reproduit le protocole que le PC (Laravel) offrait au
/// téléphone — OTP + handshake signé Ed25519 + poll du token, plus `/api/me`.
///
/// Reproduit exactement ce que `PairingHandshakeClient` et `PairingPollClient`
/// (mobile/lib/services/pairing) envoient et attendent :
/// - handshake : body `{tel_public_key, otp, signature(otp||tel_pubkey), …}` →
///   `{status, device_id, device_fingerprint, pc_public_key, pc_fingerprint, pc_name}`.
/// - poll : body `{device_id, signature(device_id)}` → `{status, token?}`.
/// L'approbation est MANUELLE sur l'hôte (écran dédié) ; tant que non approuvé,
/// la poll renvoie `pending`.
class HostPairing {
  final HostIdentity identity;
  final KeyManager keys; // sert UNIQUEMENT à vérifier les signatures des pairs
  final HostDeviceStore devices;

  /// Durée de validité d'un OTP affiché à l'écran.
  final Duration otpTtl;

  String _otp;
  DateTime _otpIssuedAt;

  HostPairing({
    required this.identity,
    required this.devices,
    KeyManager? keys,
    this.otpTtl = const Duration(minutes: 10),
  })  : keys = keys ?? KeyManager(),
        _otp = _randomOtp(),
        _otpIssuedAt = DateTime.now();

  /// OTP courant (régénéré via [rotateOtp]).
  String get otp => _otp;

  bool get _otpExpired => DateTime.now().difference(_otpIssuedAt) > otpTtl;

  /// Régénère l'OTP (à appeler quand on (ré)affiche le QR).
  String rotateOtp() {
    _otp = _randomOtp();
    _otpIssuedAt = DateTime.now();
    return _otp;
  }

  /// Construit l'URL `linkup://…` à encoder dans le QR affiché par l'hôte.
  /// [ip] = IP LAN de l'hôte, [port] = son port unique (= bridge_port).
  Future<String> pairingUrl(String ip, int port) async {
    final pk = await identity.publicKeyBase64();
    final q = Uri(queryParameters: {'pk': pk, 'otp': _otp, 'v': '1'}).query;
    return 'linkup://$ip:$port?$q';
  }

  // ----------------------------------------------------------------- handlers

  /// POST /api/pairing/handshake
  Future<void> handleHandshake(HttpRequest req) async {
    final Map<String, dynamic> body;
    try {
      body = await readJsonBody(req);
    } on FormatException {
      return _reject(req, 'malformed', 'Corps de handshake invalide.');
    }

    final telPub = body['tel_public_key'] as String?;
    final otp = body['otp'] as String?;
    final signature = body['signature'] as String?;
    if (telPub == null || otp == null || signature == null) {
      return _reject(req, 'malformed', 'Champs de handshake manquants.');
    }

    if (_otpExpired) {
      return _reject(req, 'otp_expired', 'Le code a expiré, régénère le QR.');
    }
    if (otp != _otp) {
      return _reject(req, 'otp_invalid', 'Code d\'appairage incorrect.');
    }

    final ok = await keys.verify(
      message: utf8.encode(otp + telPub),
      signatureB64: signature,
      publicKeyB64: telPub,
    );
    if (!ok) {
      return _reject(req, 'bad_signature', 'Signature du téléphone invalide.');
    }

    final deviceId = _deviceIdFor(telPub);
    final existing = await devices.get(deviceId);
    final device = existing ??
        HostDevice(
          deviceId: deviceId,
          telPublicKey: telPub,
          name: (body['device_name'] as String?) ?? 'Téléphone',
          model: (body['device_model'] as String?) ?? '',
          platform: (body['device_platform'] as String?) ?? '',
          osVersion: (body['device_os'] as String?) ?? '',
          status: HostDeviceStatus.pending,
        );
    await devices.upsertPending(device);

    return writeJson(req, {
      'status': device.status == HostDeviceStatus.approved
          ? 'approved'
          : 'pending_approval',
      'device_id': deviceId,
      'device_fingerprint': _fingerprint(telPub),
      'pc_public_key': await identity.publicKeyBase64(),
      'pc_fingerprint': await identity.fingerprint(),
      'pc_name': identity.name(),
    });
  }

  /// POST /api/pairing/poll
  Future<void> handlePoll(HttpRequest req) async {
    final Map<String, dynamic> body;
    try {
      body = await readJsonBody(req);
    } on FormatException {
      return writeStatus(req, HttpStatus.badRequest);
    }
    final deviceId = body['device_id'] as String?;
    final signature = body['signature'] as String?;
    if (deviceId == null || signature == null) {
      return writeStatus(req, HttpStatus.badRequest);
    }

    final device = await devices.get(deviceId);
    if (device == null) return writeStatus(req, HttpStatus.notFound); // 404

    final ok = await keys.verify(
      message: utf8.encode(deviceId),
      signatureB64: signature,
      publicKeyB64: device.telPublicKey,
    );
    if (!ok) return writeStatus(req, HttpStatus.forbidden); // 403

    switch (device.status) {
      case HostDeviceStatus.approved:
        // Token livré une seule fois (comme le PC).
        if (!device.tokenDelivered) {
          await devices.markTokenDelivered(deviceId);
          return writeJson(req, {'status': 'approved', 'token': device.token});
        }
        return writeJson(req, {'status': 'approved'});
      case HostDeviceStatus.rejected:
        return writeJson(req, {'status': 'rejected'});
      case HostDeviceStatus.pending:
        return writeJson(req, {'status': 'pending'});
    }
  }

  /// GET /api/me — vérifie le token (utilisé par `pairing_verifier`).
  Future<void> handleMe(HttpRequest req) async {
    final device = await authenticate(req);
    if (device == null) return writeStatus(req, HttpStatus.unauthorized);
    return writeJson(req, {'device_id': device.deviceId, 'status': 'approved'});
  }

  /// Authentifie une requête (`X-Device-Id` + `Authorization: Bearer <token>`).
  /// Renvoie le pair approuvé, ou null si l'auth échoue. Réutilisé par le
  /// transfert (Phase 3).
  Future<HostDevice?> authenticate(HttpRequest req) async {
    final deviceId = req.headers.value('X-Device-Id');
    final auth = req.headers.value('Authorization');
    if (deviceId == null || auth == null || !auth.startsWith('Bearer ')) {
      return null;
    }
    final token = auth.substring('Bearer '.length).trim();
    if (!await devices.verifyToken(deviceId, token)) return null;
    return devices.get(deviceId);
  }

  // ----------------------------------------------------------------- helpers

  Future<void> _reject(HttpRequest req, String reasonCode, String message) =>
      writeJson(
        req,
        {'reason_code': reasonCode, 'message': message},
        status: 422,
      );

  /// device_id déterministe = SHA-256 hex de la clé publique du pair → un même
  /// téléphone re-scanné retombe sur le même enregistrement.
  static String _deviceIdFor(String telPublicKeyB64) =>
      crypto.sha256.convert(utf8.encode(telPublicKeyB64)).toString();

  /// Empreinte courte (8 hex) de la clé publique du pair, même algo que
  /// `KeyManager.fingerprint` (4 premiers octets du SHA-256 des octets de clé).
  static String _fingerprint(String telPublicKeyB64) {
    final pubBytes = base64.decode(telPublicKeyB64);
    final digest = crypto.sha256.convert(pubBytes).bytes;
    return digest
        .sublist(0, 4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static String _randomOtp() {
    final rnd = Random.secure();
    return List<int>.generate(8, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
