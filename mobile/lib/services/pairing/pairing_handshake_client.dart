import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../crypto/key_manager.dart';
import 'device_metadata.dart';
import 'pairing_url.dart';

/// Résultat d'un handshake de pairing réussi (statut `pending_approval`
/// ou `approved` quand reconnexion d'un device déjà existant).
class HandshakeResult {
  final String status;
  final String deviceId;

  /// Empreinte SHA-256 du tel (la même que celle affichée par le dashboard).
  final String deviceFingerprint;
  final String pcPublicKey;
  final String pcFingerprint;
  final String pcName;

  const HandshakeResult({
    required this.status,
    required this.deviceId,
    required this.deviceFingerprint,
    required this.pcPublicKey,
    required this.pcFingerprint,
    required this.pcName,
  });

  bool get isPending => status == 'pending_approval';
  bool get isApproved => status == 'approved';
}

/// Erreur métier renvoyée par le PC (422 avec `reason_code`).
class HandshakeRejected implements Exception {
  final String reasonCode;
  final String message;
  const HandshakeRejected(this.reasonCode, this.message);
  @override
  String toString() => 'HandshakeRejected($reasonCode): $message';
}

/// Erreur réseau / transport (PC injoignable, timeout, etc.).
class HandshakeNetworkException implements Exception {
  final String message;
  const HandshakeNetworkException(this.message);
  @override
  String toString() => 'HandshakeNetworkException: $message';
}

/// Client qui pilote le handshake de pairing après scan du QR.
///
/// - Récupère la paire Ed25519 du tel via [KeyManager]
/// - Signe (otp || tel_pubkey) avec la clé secrète
/// - POST le tout à `/api/pairing/handshake`
/// - Vérifie que la clé pub PC reçue correspond à celle du QR (anti-MITM)
class PairingHandshakeClient {
  final KeyManager _keyManager;
  final http.Client _http;
  final Duration timeout;
  final bool _ownsHttp;

  PairingHandshakeClient({
    required KeyManager keyManager,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 5),
  })  : _keyManager = keyManager,
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  /// Lance le handshake en utilisant les données du QR.
  /// Throws [HandshakeRejected] (422 métier) ou [HandshakeNetworkException].
  Future<HandshakeResult> handshake(
    PairingUrl pairing, {
    DeviceMetadata? metadata,
  }) async {
    // Charge ou génère la paire tel.
    final telPubB64 = await _keyManager.publicKeyBase64();

    // Signe (otp || tel_pubkey).
    final messageBytes = utf8.encode(pairing.otp + telPubB64);
    final signature = await _keyManager.sign(messageBytes);

    final http.Response response;
    try {
      response = await _http
          .post(
            pairing.handshakeUri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'tel_public_key': telPubB64,
              'otp': pairing.otp,
              'signature': signature,
              if (metadata != null) ...metadata.toHandshakeFields(),
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const HandshakeNetworkException('Pas de réponse du PC dans le délai imparti.');
    } on SocketException catch (e) {
      throw HandshakeNetworkException('Connexion refusée : ${e.message}');
    } on http.ClientException catch (e) {
      throw HandshakeNetworkException('Erreur HTTP : ${e.message}');
    }

    // 422 = refus métier : on a besoin du JSON pour le reason_code.
    if (response.statusCode == 422) {
      final body = _tryDecode(response.body);
      throw HandshakeRejected(
        (body?['reason_code'] as String?) ?? 'unknown',
        (body?['message'] as String?) ?? 'Handshake refusé',
      );
    }
    // Tout autre code != 200 est une erreur transport, sans garantie de corps JSON.
    if (response.statusCode != 200) {
      throw HandshakeNetworkException('PC a répondu ${response.statusCode}.');
    }

    // 200 attendu : le corps DOIT être un JSON exploitable.
    final payload = _tryDecode(response.body);
    if (payload == null) {
      throw const HandshakeNetworkException('Réponse JSON invalide du PC.');
    }

    final pcPubReceived = payload['pc_public_key'] as String?;
    if (pcPubReceived == null) {
      throw const HandshakeNetworkException('Réponse PC sans pc_public_key.');
    }

    // Garde-fou anti-MITM : la clé pub annoncée par le PC dans le QR doit
    // matcher celle qu'il renvoie. Sinon quelqu'un s'est interposé.
    if (pcPubReceived != pairing.pcPublicKey) {
      throw HandshakeRejected(
        'pc_pubkey_mismatch',
        'La clé publique du PC ne correspond pas au QR scanné.',
      );
    }

    return HandshakeResult(
      status: payload['status'] as String? ?? 'unknown',
      deviceId: payload['device_id'] as String? ?? '',
      deviceFingerprint: payload['device_fingerprint'] as String? ?? '',
      pcPublicKey: pcPubReceived,
      pcFingerprint: payload['pc_fingerprint'] as String? ?? '',
      pcName: payload['pc_name'] as String? ?? 'PC',
    );
  }

  /// Décode un corps JSON en map, ou null si le corps n'est pas un objet JSON.
  Map<String, dynamic>? _tryDecode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  void close() {
    if (_ownsHttp) _http.close();
  }
}
