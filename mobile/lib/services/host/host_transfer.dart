import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

import '../crypto/constant_time.dart';
import '../crypto/hex.dart';
import '../transfer/received_saver.dart';
import 'host_http.dart';
import 'host_pairing.dart';

/// Un transfert connu de l'hôte. `to_pc` = pair→hôte (chunké) ; `to_phone` =
/// hôte→pair (l'hôte dépose un fichier, le pair le récupère via `incoming`).
class _Record {
  final String id;
  final String deviceId;
  final String filename;
  final int size;
  final String? sha256;
  final int totalChunks;
  final String direction;
  String status = 'pending'; // pending | completed | delivered | failed
  String? storedName;
  final DateTime createdAt;
  DateTime? completedAt;

  _Record({
    required this.id,
    required this.deviceId,
    required this.filename,
    required this.size,
    required this.sha256,
    required this.totalChunks,
    required this.createdAt,
    this.direction = 'to_pc',
  });

  Map<String, dynamic> present() => {
        'transfer_id': id,
        'filename': storedName ?? filename,
        'size': size,
        'direction': direction,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
      };
}

/// Transfert côté hôte : fusionne les rôles **agent** (`/api/transfers*`) et
/// **bridge** (`/transfer/*`) dans un seul service Dart. Le pair (client mobile
/// inchangé) initie via l'agent puis pousse les chunks au bridge — ici les deux
/// sont le même process, donc l'`upload_token` HMAC est purement interne.
///
/// Réutilise [ReceivedFileSaver] (DeviceFileSaver) pour ranger le fichier final
/// (galerie / dossier), comme la réception depuis le PC.
class HostTransfer {
  final HostPairing pairing; // pour authentifier les routes /api/* (device)
  final ReceivedFileSaver saver;
  final Directory stagingRoot;
  final int listenPort;

  /// Secret interne du signataire de token (jamais exposé). Aléatoire par
  /// instance : un token n'est valable que pour la session d'hébergement.
  final List<int> _secret;

  final Map<String, _Record> _records = {};

  HostTransfer({
    required this.pairing,
    required this.saver,
    required this.stagingRoot,
    required this.listenPort,
  }) : _secret = _randomBytes(32);

  // --------------------------------------------------------------- token HMAC

  String _signToken(String transferId) =>
      base64Url.encode(crypto.Hmac(crypto.sha256, _secret).convert(utf8.encode(transferId)).bytes);

  bool _verifyToken(HttpRequest req, String transferId) {
    final auth = req.headers.value('Authorization');
    if (auth == null || !auth.startsWith('Bearer ')) return false;
    final token = auth.substring('Bearer '.length).trim();
    return constantTimeEquals(token, _signToken(transferId));
  }

  // ------------------------------------------------------------- agent (/api)

  /// POST /api/transfers — le pair déclare un transfert et reçoit son token.
  Future<void> handleInitiate(HttpRequest req) async {
    final device = await pairing.authenticate(req);
    if (device == null) return writeStatus(req, HttpStatus.unauthorized);

    final Map<String, dynamic> body;
    try {
      body = await readJsonBody(req);
    } on FormatException {
      return writeStatus(req, HttpStatus.badRequest);
    }

    final filename = body['filename'] as String?;
    final size = (body['size'] as num?)?.toInt();
    final direction = body['direction'] as String?;
    if (filename == null || size == null || direction != 'to_pc') {
      return writeStatus(req, HttpStatus.badRequest);
    }

    final id = _randomId();
    final record = _Record(
      id: id,
      deviceId: device.deviceId,
      filename: filename,
      size: size,
      sha256: body['sha256'] as String?,
      totalChunks: (body['total_chunks'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.now(),
    );
    _records[id] = record;

    return writeJson(req, {
      ...record.present(),
      'upload_token': _signToken(id),
      'bridge_port': listenPort,
    }, status: 201);
  }

  /// GET /api/transfers — historique des transferts de ce pair.
  Future<void> handleList(HttpRequest req) async {
    final device = await pairing.authenticate(req);
    if (device == null) return writeStatus(req, HttpStatus.unauthorized);
    final mine = _records.values
        .where((r) => r.deviceId == device.deviceId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return writeJson(req, {'transfers': mine.map((r) => r.present()).toList()});
  }

  /// POST /api/transfers/{id}/complete — confirmation best-effort du pair.
  Future<void> handleComplete(HttpRequest req, String id) async {
    final device = await pairing.authenticate(req);
    if (device == null) return writeStatus(req, HttpStatus.unauthorized);
    final record = _records[id];
    if (record == null || record.deviceId != device.deviceId) {
      return writeStatus(req, HttpStatus.notFound);
    }
    Map<String, dynamic> body;
    try {
      body = await readJsonBody(req);
    } on FormatException {
      body = const {};
    }
    record.storedName = (body['stored_name'] as String?) ?? record.storedName;
    if (record.status == 'pending') record.status = 'completed';
    record.completedAt ??= DateTime.now();
    return writeJson(req, record.present());
  }

  // ------------------------------------------------------- hôte→pair (outbox)

  /// Dépose un fichier pour [deviceId] (sens to_phone). Appelé par l'UI hôte ;
  /// le pair le récupère ensuite avec son `IncomingReceiver` (incoming + download).
  /// Renvoie l'id du transfert créé.
  Future<String> enqueueOutgoing({
    required String deviceId,
    required String filename,
    required List<int> bytes,
  }) async {
    final id = _randomId();
    final dir = Directory('${stagingRoot.path}/outbox');
    await dir.create(recursive: true);
    await File('${dir.path}/$id').writeAsBytes(bytes, flush: true);
    final record = _Record(
      id: id,
      deviceId: deviceId,
      filename: filename,
      size: bytes.length,
      sha256: null,
      totalChunks: 1,
      createdAt: DateTime.now(),
      direction: 'to_phone',
    )
      ..status = 'completed'
      ..storedName = filename
      ..completedAt = DateTime.now();
    _records[id] = record;
    return id;
  }

  /// GET /api/transfers/incoming — fichiers to_phone prêts pour ce pair.
  Future<void> handleIncoming(HttpRequest req) async {
    final device = await pairing.authenticate(req);
    if (device == null) return writeStatus(req, HttpStatus.unauthorized);
    final pending = _records.values
        .where((r) =>
            r.deviceId == device.deviceId &&
            r.direction == 'to_phone' &&
            r.status == 'completed')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return writeJson(req, {'transfers': pending.map((r) => r.present()).toList()});
  }

  /// GET /api/transfers/{id}/download — sert le fichier déposé au pair.
  Future<void> handleDownload(HttpRequest req, String id) async {
    final device = await pairing.authenticate(req);
    if (device == null) return writeStatus(req, HttpStatus.unauthorized);
    final record = _records[id];
    if (record == null || record.deviceId != device.deviceId) {
      return writeStatus(req, HttpStatus.notFound);
    }
    if (record.direction != 'to_phone' ||
        (record.status != 'completed' && record.status != 'delivered')) {
      return writeStatus(req, HttpStatus.conflict); // 409
    }
    final file = File('${stagingRoot.path}/outbox/$id');
    if (!await file.exists()) return writeStatus(req, HttpStatus.notFound);
    // Streaming disque→socket : ne charge jamais tout le fichier en RAM.
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.binary
      ..contentLength = await file.length();
    await req.response.addStream(file.openRead());
    await req.response.close();
  }

  /// POST /api/transfers/{id}/delivered — le pair confirme la réception
  /// (→ sort de `incoming`).
  Future<void> handleDelivered(HttpRequest req, String id) async {
    final device = await pairing.authenticate(req);
    if (device == null) return writeStatus(req, HttpStatus.unauthorized);
    final record = _records[id];
    if (record == null || record.deviceId != device.deviceId) {
      return writeStatus(req, HttpStatus.notFound);
    }
    if (record.direction != 'to_phone') return writeStatus(req, 422);
    record.status = 'delivered';
    return writeJson(req, {'ok': true});
  }

  // ----------------------------------------------------------- bridge (/transfer)

  /// GET /transfer/{id}/status — chunks déjà reçus (reprise).
  Future<void> handleStatus(HttpRequest req, String id) async {
    if (!_verifyToken(req, id)) return writeStatus(req, HttpStatus.unauthorized);
    return writeJson(req, {'transfer_id': id, 'received_chunks': _receivedChunks(id)});
  }

  /// POST /transfer/upload — écrit un chunk après vérif de son SHA-256.
  Future<void> handleUpload(HttpRequest req) async {
    final id = req.headers.value('X-Transfer-Id');
    final indexStr = req.headers.value('X-Chunk-Index');
    final sha = req.headers.value('X-Chunk-Sha256');
    if (id == null || indexStr == null || sha == null) {
      return writeStatus(req, HttpStatus.badRequest);
    }
    if (!_verifyToken(req, id)) return writeStatus(req, HttpStatus.unauthorized);
    final index = int.tryParse(indexStr);
    if (index == null) return writeStatus(req, HttpStatus.badRequest);

    final data = await readRawBody(req);
    if (data.isEmpty) return writeStatus(req, HttpStatus.badRequest);

    final actual = crypto.sha256.convert(data).toString();
    if (actual.toLowerCase() != sha.trim().toLowerCase()) {
      return writeJson(req, {'error': 'SHA-256 du chunk invalide'}, status: 422);
    }

    final dir = Directory('${stagingRoot.path}/$id');
    await dir.create(recursive: true);
    await File('${dir.path}/chunk_$index').writeAsBytes(data, flush: true);

    return writeJson(req, {'ok': true, 'index': index, 'size': data.length});
  }

  /// POST /transfer/{id}/finalize — recompose, vérifie le SHA-256 global, range.
  Future<void> handleFinalize(HttpRequest req, String id) async {
    if (!_verifyToken(req, id)) return writeStatus(req, HttpStatus.unauthorized);
    final filename = req.headers.value('X-Transfer-Filename');
    final totalStr = req.headers.value('X-Transfer-Total-Chunks');
    final sha = req.headers.value('X-Transfer-Sha256');
    if (filename == null || totalStr == null || sha == null) {
      return writeStatus(req, HttpStatus.badRequest);
    }
    final total = int.tryParse(totalStr);
    if (total == null || total <= 0) return writeStatus(req, HttpStatus.badRequest);

    final dir = Directory('${stagingRoot.path}/$id');

    // Assemblage en STREAMING vers un fichier temporaire : on ne tient jamais
    // plus d'un buffer de lecture en RAM (un gros fichier ne fait plus OOM).
    final assembled = File('${dir.path}/.assembled.part');
    final sink = assembled.openWrite();
    try {
      for (var i = 0; i < total; i++) {
        final f = File('${dir.path}/chunk_$i');
        if (!await f.exists()) {
          await sink.close();
          await assembled.delete().catchError((_) => assembled);
          return writeJson(req, {'error': 'Chunk $i manquant'}, status: 422);
        }
        await sink.addStream(f.openRead());
      }
    } finally {
      await sink.close();
    }
    final size = await assembled.length();

    // SHA-256 global calculé en STREAMING sur le fichier assemblé.
    final digest = await crypto.sha256.bind(assembled.openRead()).first;
    if (digest.toString().toLowerCase() != sha.trim().toLowerCase()) {
      await assembled.delete().catchError((_) => assembled);
      return writeJson(req, {'error': 'SHA-256 global invalide'}, status: 422);
    }

    // Range le fichier (galerie / documents) SANS le recharger en RAM (le saver
    // neutralise aussi le nom — anti path-traversal).
    final result = await saver.saveFile(filename, assembled);
    if (result.kind == SaveKind.failed) {
      await assembled.delete().catchError((_) => assembled);
      return writeJson(req, {'error': 'Échec d\'enregistrement'}, status: 422);
    }

    final record = _records[id];
    if (record != null) {
      record.status = 'completed';
      record.storedName = filename;
      record.completedAt = DateTime.now();
    }
    await dir.delete(recursive: true).catchError((_) => dir);

    return writeJson(req, {
      'ok': true,
      'filename': filename,
      'size': size,
      'location': result.location,
    });
  }

  // ------------------------------------------------------- UI hôte (lecture)

  /// Fichiers REÇUS d'un pair (to_pc terminés), pour l'écran de transfert hôte.
  /// (Ils sont déjà rangés dans la galerie/Téléchargements via le saver.)
  List<Map<String, dynamic>> receivedFrom(String deviceId) {
    final list = _records.values
        .where((r) =>
            r.deviceId == deviceId &&
            r.direction == 'to_pc' &&
            r.status == 'completed')
        .toList()
      ..sort((a, b) => (b.completedAt ?? b.createdAt)
          .compareTo(a.completedAt ?? a.createdAt));
    return list.map((r) => r.present()).toList();
  }

  // ----------------------------------------------------------------- helpers

  List<int> _receivedChunks(String id) {
    final dir = Directory('${stagingRoot.path}/$id');
    if (!dir.existsSync()) return const [];
    final out = <int>[];
    for (final entity in dir.listSync()) {
      final name = entity.uri.pathSegments.last;
      if (name.startsWith('chunk_')) {
        final idx = int.tryParse(name.substring('chunk_'.length));
        if (idx != null) out.add(idx);
      }
    }
    out.sort();
    return out;
  }

  static String _randomId() {
    final rnd = Random.secure();
    return hexEncode(List<int>.generate(16, (_) => rnd.nextInt(256)));
  }

  static List<int> _randomBytes(int n) {
    final rnd = Random.secure();
    return List<int>.generate(n, (_) => rnd.nextInt(256));
  }
}
