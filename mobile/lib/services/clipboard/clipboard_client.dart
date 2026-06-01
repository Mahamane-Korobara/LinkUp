import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../pairing/paired_device_store.dart';

/// Erreur de presse-papier affichable.
class ClipboardException implements Exception {
  final String message;
  const ClipboardException(this.message);
  @override
  String toString() => 'ClipboardException: $message';
}

/// Une entrée de l'historique presse-papier (renvoyée par `GET /api/clipboard`).
class ClipboardItem {
  final String id;
  final String content;
  final String origin; // 'phone' | 'pc'
  final DateTime? createdAt;

  const ClipboardItem({
    required this.id,
    required this.content,
    required this.origin,
    this.createdAt,
  });

  /// Provient du PC (vs copié sur le tél).
  bool get isFromPc => origin == 'pc';

  static final _urlRegex = RegExp(r'^https?://', caseSensitive: false);

  /// Le contenu ressemble à un lien http(s) ouvrable sur le PC.
  bool get looksLikeUrl => _urlRegex.hasMatch(content.trim());

  factory ClipboardItem.fromJson(Map<String, dynamic> j) => ClipboardItem(
        id: j['id'] as String? ?? '',
        content: j['content'] as String? ?? '',
        origin: j['origin'] as String? ?? 'phone',
        createdAt:
            j['created_at'] is String ? DateTime.tryParse(j['created_at'] as String) : null,
      );
}

/// Client presse-papier + lien rapide : parle au Laravel du PC appairé (S5).
class ClipboardClient {
  final http.Client _http;
  final bool _ownsHttp;
  final Duration requestTimeout;

  ClipboardClient({
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 10),
  })  : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  /// Pousse [content] vers le presse-papier du PC. Throws [ClipboardException].
  Future<void> push(PairedDevice device, String content) async {
    final res = await _post(device, '/api/clipboard', {'content': content});
    if (res.statusCode == 401) {
      throw const ClipboardException('Appairage expiré : re-scanne le QR.');
    }
    if (res.statusCode != 200) {
      throw ClipboardException('Le PC a refusé l\'envoi (${res.statusCode}).');
    }
  }

  /// Récupère le presse-papier ACTUEL du PC. Throws [ClipboardException].
  Future<String> pullFromPc(PairedDevice device) async {
    final res = await _get(device, '/api/clipboard/pc');
    if (res.statusCode == 401) {
      throw const ClipboardException('Appairage expiré : re-scanne le QR.');
    }
    if (res.statusCode != 200) {
      throw ClipboardException('Lecture du presse-papier PC refusée (${res.statusCode}).');
    }
    return _decode(res.body)['text'] as String? ?? '';
  }

  /// Historique récent du presse-papier (récents d'abord).
  Future<List<ClipboardItem>> history(PairedDevice device) async {
    final res = await _get(device, '/api/clipboard');
    if (res.statusCode == 401) {
      throw const ClipboardException('Appairage expiré : re-scanne le QR.');
    }
    if (res.statusCode != 200) {
      throw ClipboardException('Le PC a répondu ${res.statusCode}.');
    }
    final list = (_decode(res.body)['items'] as List?) ?? const [];
    return list
        .map((e) => ClipboardItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Demande au PC d'ouvrir [url] dans son navigateur. Throws [ClipboardException].
  Future<void> openLink(PairedDevice device, String url) async {
    final res = await _post(device, '/api/link/open', {'url': url});
    if (res.statusCode == 422) {
      throw const ClipboardException('Lien refusé (seuls http/https sont autorisés).');
    }
    if (res.statusCode != 200) {
      throw ClipboardException('Ouverture du lien refusée (${res.statusCode}).');
    }
  }

  // ----------------------------------------------------------------- helpers

  Future<http.Response> _get(PairedDevice device, String path) async {
    try {
      return await _http
          .get(device.baseUri.replace(path: path), headers: _headers(device))
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const ClipboardException('Pas de réponse du PC.');
    } on SocketException catch (e) {
      throw ClipboardException('Connexion refusée : ${e.message}');
    }
  }

  Future<http.Response> _post(
    PairedDevice device,
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      return await _http
          .post(
            device.baseUri.replace(path: path),
            headers: {..._headers(device), 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const ClipboardException('Pas de réponse du PC.');
    } on SocketException catch (e) {
      throw ClipboardException('Connexion refusée : ${e.message}');
    }
  }

  Map<String, String> _headers(PairedDevice device) => {
        'Accept': 'application/json',
        'X-Device-Id': device.deviceId,
        'Authorization': 'Bearer ${device.token}',
      };

  Map<String, dynamic> _decode(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const ClipboardException('Réponse JSON inattendue.');
    }
    return decoded;
  }

  void close() {
    if (_ownsHttp) _http.close();
  }
}
