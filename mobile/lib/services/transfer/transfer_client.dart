import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import '../crypto/hex.dart';
import '../pairing/paired_device_store.dart';

/// Progression d'un transfert, émise au fil des chunks envoyés.
class TransferProgress {
  final int sentChunks;
  final int totalChunks;
  final int sentBytes;
  final int totalBytes;

  const TransferProgress({
    required this.sentChunks,
    required this.totalChunks,
    required this.sentBytes,
    required this.totalBytes,
  });

  double get fraction => totalBytes == 0 ? 1 : sentBytes / totalBytes;
}

/// Erreur de transfert affichable.
class TransferException implements Exception {
  final String message;
  const TransferException(this.message);
  @override
  String toString() => 'TransferException: $message';
}

/// Une entrée de l'historique des transferts (renvoyée par `/api/transfers`).
class TransferSummary {
  final String id;
  final String filename;
  final int size;
  final String direction;
  final String status;
  final DateTime? createdAt;
  final DateTime? completedAt;

  const TransferSummary({
    required this.id,
    required this.filename,
    required this.size,
    required this.direction,
    required this.status,
    this.createdAt,
    this.completedAt,
  });

  /// Envoi du tél vers le PC (le seul sens implémenté pour l'instant).
  bool get isOutgoing => direction == 'to_pc';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed' || status == 'cancelled';

  static DateTime? _parseDate(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;

  factory TransferSummary.fromJson(Map<String, dynamic> j) => TransferSummary(
        id: j['transfer_id'] as String? ?? '',
        filename: j['filename'] as String? ?? '?',
        size: (j['size'] as num?)?.toInt() ?? 0,
        direction: j['direction'] as String? ?? 'to_pc',
        status: j['status'] as String? ?? 'pending',
        createdAt: _parseDate(j['created_at']),
        completedAt: _parseDate(j['completed_at']),
      );
}

/// Données de coordination renvoyées par Laravel à l'initiate.
class _InitiateResult {
  final String transferId;
  final String uploadToken;
  final int bridgePort;
  const _InitiateResult(this.transferId, this.uploadToken, this.bridgePort);
}

/// Pilote l'upload d'un fichier du tél vers le PC (sens `to_pc`).
///
/// Flow (S4) :
/// 1. `POST {laravel}/api/transfers` (auth device : X-Device-Id + Bearer token)
///    → reçoit `transfer_id`, `upload_token` (HMAC scopé) et `bridge_port`.
/// 2. `GET {bridge}/transfer/{id}/status` → chunks déjà reçus (REPRISE).
/// 3. Pour chaque chunk manquant : `POST {bridge}/transfer/upload` avec le
///    `upload_token`, le SHA-256 du chunk, le corps brut.
/// 4. `POST {bridge}/transfer/{id}/finalize` → vérifie le SHA-256 global PC.
class TransferClient {
  final http.Client _http;
  final bool _ownsHttp;
  final int chunkSize;
  final Duration requestTimeout;

  TransferClient({
    http.Client? httpClient,
    this.chunkSize = 1024 * 1024, // 1 Mo (cf. CDC §16.1)
    this.requestTimeout = const Duration(seconds: 30),
  })  : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  /// Envoie [bytes] sous le nom [filename] vers le PC [device].
  /// Émet la progression via [onProgress]. Retourne l'`id` du transfert (pour le
  /// relier ailleurs, ex. import galerie). Throws [TransferException].
  Future<String> uploadBytes({
    required PairedDevice device,
    required String filename,
    required List<int> bytes,
    void Function(TransferProgress)? onProgress,
  }) async {
    final totalChunks = bytes.isEmpty ? 1 : (bytes.length / chunkSize).ceil();
    final globalSha = await _sha256Hex(bytes);

    final init = await _initiate(device, filename, bytes.length, globalSha, totalChunks);
    final bridge = Uri(scheme: 'http', host: device.host, port: init.bridgePort);

    final received = await _receivedChunks(bridge, init);

    var sentBytes = 0;
    for (final index in received) {
      sentBytes += _chunkLength(bytes, index);
    }
    onProgress?.call(TransferProgress(
      sentChunks: received.length,
      totalChunks: totalChunks,
      sentBytes: sentBytes,
      totalBytes: bytes.length,
    ));

    for (var index = 0; index < totalChunks; index++) {
      if (received.contains(index)) continue;
      final chunk = _chunkAt(bytes, index);
      await _uploadChunk(bridge, init, index, chunk);
      sentBytes += chunk.length;
      onProgress?.call(TransferProgress(
        sentChunks: index + 1,
        totalChunks: totalChunks,
        sentBytes: sentBytes,
        totalBytes: bytes.length,
      ));
    }

    final storedName = await _finalize(bridge, init, filename, totalChunks, globalSha);

    // Le finalize s'est fait sur le BRIDGE → Laravel ne le sait pas. On le lui
    // confirme pour que l'historique passe « terminé » (sinon il reste pending).
    await _complete(device, init.transferId, storedName ?? filename);

    return init.transferId;
  }

  /// Re-télécharge depuis le PC les octets d'un transfert terminé (pour l'ouvrir
  /// sur le tél). Throws [TransferException].
  Future<List<int>> downloadBytes(PairedDevice device, String transferId) async {
    final uri = device.baseUri.replace(path: '/api/transfers/$transferId/download');
    final http.Response res;
    try {
      res = await _http.get(uri, headers: _deviceHeaders(device)).timeout(requestTimeout);
    } on TimeoutException {
      throw const TransferException('Pas de réponse du PC.');
    } on SocketException catch (e) {
      throw TransferException('Connexion refusée : ${e.message}');
    }
    if (res.statusCode == 401) {
      throw const TransferException('Appairage expiré : re-scanne le QR.');
    }
    if (res.statusCode == 409) {
      throw const TransferException('Transfert pas encore terminé.');
    }
    if (res.statusCode != 200) {
      throw TransferException('Téléchargement refusé (${res.statusCode}).');
    }
    return res.bodyBytes;
  }

  /// Historique des transferts de ce tél (récents d'abord), depuis Laravel.
  Future<List<TransferSummary>> listTransfers(PairedDevice device) async {
    final uri = device.baseUri.replace(path: '/api/transfers');
    final http.Response res;
    try {
      res = await _http.get(uri, headers: _deviceHeaders(device)).timeout(requestTimeout);
    } on TimeoutException {
      throw const TransferException('Pas de réponse du PC.');
    } on SocketException catch (e) {
      throw TransferException('Connexion refusée : ${e.message}');
    }

    if (res.statusCode == 401) {
      throw const TransferException('Appairage expiré : re-scanne le QR.');
    }
    if (res.statusCode != 200) {
      throw TransferException('Le PC a répondu ${res.statusCode}.');
    }

    final body = _decode(res.body);
    final list = (body['transfers'] as List?) ?? const [];
    return list
        .map((e) => TransferSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fichiers que le PC a envoyés à ce tél (sens to_phone), pas encore récupérés.
  Future<List<TransferSummary>> listIncoming(PairedDevice device) async {
    final uri = device.baseUri.replace(path: '/api/transfers/incoming');
    final http.Response res;
    try {
      res = await _http.get(uri, headers: _deviceHeaders(device)).timeout(requestTimeout);
    } on TimeoutException {
      throw const TransferException('Pas de réponse du PC.');
    } on SocketException catch (e) {
      throw TransferException('Connexion refusée : ${e.message}');
    }
    if (res.statusCode == 401) {
      throw const TransferException('Appairage expiré : re-scanne le QR.');
    }
    if (res.statusCode != 200) {
      throw TransferException('Le PC a répondu ${res.statusCode}.');
    }
    final list = (_decode(res.body)['transfers'] as List?) ?? const [];
    return list.map((e) => TransferSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Confirme au PC qu'un fichier reçu a été enregistré (→ sort des entrants).
  /// Best-effort : un échec ici ne reperd pas le fichier (déjà enregistré).
  Future<void> markDelivered(PairedDevice device, String transferId) async {
    final uri = device.baseUri.replace(path: '/api/transfers/$transferId/delivered');
    try {
      await _http.post(uri, headers: _deviceHeaders(device)).timeout(requestTimeout);
    } catch (_) {
      // tant pis : le fichier est enregistré, seul le statut côté PC reste à jour.
    }
  }

  // ----------------------------------------------------------------- steps

  Future<_InitiateResult> _initiate(
    PairedDevice device,
    String filename,
    int size,
    String sha256Hex,
    int totalChunks,
  ) async {
    final uri = device.baseUri.replace(path: '/api/transfers');
    final http.Response res;
    try {
      res = await _http.post(
        uri,
        headers: {..._deviceHeaders(device), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'filename': filename,
          'size': size,
          'sha256': sha256Hex,
          'direction': 'to_pc',
          'total_chunks': totalChunks,
        }),
      ).timeout(requestTimeout);
    } on TimeoutException {
      throw const TransferException('Pas de réponse du PC (initiation).');
    } on SocketException catch (e) {
      throw TransferException('Connexion refusée : ${e.message}');
    }

    if (res.statusCode == 401) {
      throw const TransferException('Appairage expiré : re-scanne le QR.');
    }
    if (res.statusCode != 201) {
      throw TransferException('Le PC a refusé le transfert (${res.statusCode}).');
    }

    final body = _decode(res.body);
    final id = body['transfer_id'] as String?;
    final token = body['upload_token'] as String?;
    final port = body['bridge_port'] as int?;
    if (id == null || token == null || port == null) {
      throw const TransferException('Réponse d\'initiation incomplète.');
    }
    return _InitiateResult(id, token, port);
  }

  Future<Set<int>> _receivedChunks(Uri bridge, _InitiateResult init) async {
    final uri = bridge.replace(path: '/transfer/${init.transferId}/status');
    try {
      final res = await _http.get(
        uri,
        headers: {'Authorization': 'Bearer ${init.uploadToken}'},
      ).timeout(requestTimeout);
      if (res.statusCode != 200) return <int>{};
      final body = _decode(res.body);
      final list = (body['received_chunks'] as List?) ?? const [];
      return list.map((e) => e as int).toSet();
    } on TimeoutException {
      return <int>{}; // pas de reprise possible, on (re)part de zéro
    } on SocketException {
      return <int>{};
    }
  }

  Future<void> _uploadChunk(
    Uri bridge,
    _InitiateResult init,
    int index,
    List<int> chunk,
  ) async {
    final uri = bridge.replace(path: '/transfer/upload');
    final http.Response res;
    try {
      res = await _http.post(
        uri,
        headers: {
          'Authorization': 'Bearer ${init.uploadToken}',
          'X-Transfer-Id': init.transferId,
          'X-Chunk-Index': '$index',
          'X-Chunk-Sha256': await _sha256Hex(chunk),
        },
        body: chunk,
      ).timeout(requestTimeout);
    } on TimeoutException {
      throw TransferException('Timeout sur le chunk $index.');
    } on SocketException catch (e) {
      throw TransferException('Connexion perdue au chunk $index : ${e.message}');
    }
    if (res.statusCode != 200) {
      throw TransferException('Chunk $index refusé par le bridge (${res.statusCode}).');
    }
  }

  /// Recompose côté bridge et renvoie le nom final du fichier dans l'inbox.
  Future<String?> _finalize(
    Uri bridge,
    _InitiateResult init,
    String filename,
    int totalChunks,
    String sha256Hex,
  ) async {
    final uri = bridge.replace(path: '/transfer/${init.transferId}/finalize');
    final http.Response res;
    try {
      res = await _http.post(
        uri,
        headers: {
          'Authorization': 'Bearer ${init.uploadToken}',
          'X-Transfer-Filename': filename,
          'X-Transfer-Total-Chunks': '$totalChunks',
          'X-Transfer-Sha256': sha256Hex,
        },
      ).timeout(requestTimeout);
    } on TimeoutException {
      throw const TransferException('Timeout à la finalisation.');
    } on SocketException catch (e) {
      throw TransferException('Connexion perdue à la finalisation : ${e.message}');
    }
    if (res.statusCode != 200) {
      throw TransferException('Finalisation refusée par le PC (${res.statusCode}).');
    }
    try {
      return _decode(res.body)['filename'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Confirme à Laravel que le transfert est terminé (statut + nom stocké).
  /// Best-effort : un échec ici ne perd pas le fichier (déjà sur le PC).
  Future<void> _complete(PairedDevice device, String transferId, String storedName) async {
    final uri = device.baseUri.replace(path: '/api/transfers/$transferId/complete');
    try {
      await _http.post(
        uri,
        headers: {..._deviceHeaders(device), 'Content-Type': 'application/json'},
        body: jsonEncode({'stored_name': storedName}),
      ).timeout(requestTimeout);
    } catch (_) {
      // tant pis : le fichier est bien arrivé, seul le statut côté PC reste à jour.
    }
  }

  // ----------------------------------------------------------------- helpers

  Map<String, String> _deviceHeaders(PairedDevice device) => {
        'Accept': 'application/json',
        'X-Device-Id': device.deviceId,
        'Authorization': 'Bearer ${device.token}',
      };

  int _chunkLength(List<int> bytes, int index) {
    final start = index * chunkSize;
    return math.min(chunkSize, math.max(0, bytes.length - start));
  }

  List<int> _chunkAt(List<int> bytes, int index) {
    final start = index * chunkSize;
    final end = math.min(start + chunkSize, bytes.length);
    return bytes.sublist(start, end);
  }

  Future<String> _sha256Hex(List<int> data) async {
    final digest = await Sha256().hash(data);
    return hexEncode(digest.bytes);
  }

  Map<String, dynamic> _decode(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const TransferException('Réponse JSON inattendue.');
    }
    return decoded;
  }

  void close() {
    if (_ownsHttp) _http.close();
  }
}
