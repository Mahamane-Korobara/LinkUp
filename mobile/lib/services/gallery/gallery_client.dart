import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../pairing/paired_device_store.dart';
import 'gallery_source.dart';

/// Erreur galerie affichable.
class GalleryException implements Exception {
  final String message;
  const GalleryException(this.message);
  @override
  String toString() => 'GalleryException: $message';
}

/// Client galerie : pousse l'index + les vignettes vers le Laravel du PC (S6).
class GalleryClient {
  final http.Client _http;
  final bool _ownsHttp;
  final Duration requestTimeout;

  GalleryClient({
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 20),
  })  : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  /// Upsert un lot de métadonnées. Retourne les `media_id` dont le PC n'a pas
  /// encore la vignette. Throws [GalleryException].
  Future<List<String>> syncBatch(PairedDevice device, List<GalleryMeta> metas) async {
    final uri = device.baseUri.replace(path: '/api/gallery/sync');
    final http.Response res;
    try {
      res = await _http
          .post(
            uri,
            headers: {..._headers(device), 'Content-Type': 'application/json'},
            body: jsonEncode({'items': metas.map((m) => m.toSyncJson()).toList()}),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const GalleryException('Pas de réponse du PC.');
    } on SocketException catch (e) {
      throw GalleryException('Connexion refusée : ${e.message}');
    }

    if (res.statusCode == 401) {
      throw const GalleryException('Appairage expiré : re-scanne le QR.');
    }
    if (res.statusCode != 200) {
      throw GalleryException('Sync galerie refusée (${res.statusCode}).');
    }

    final decoded = jsonDecode(res.body);
    final pending = (decoded is Map<String, dynamic> ? decoded['pending_thumbs'] as List? : null) ?? const [];
    return pending.map((e) => e.toString()).toList();
  }

  /// Envoie la vignette JPEG d'un média. Throws [GalleryException].
  Future<void> uploadThumbnail(PairedDevice device, String mediaId, List<int> jpeg) async {
    final uri = device.baseUri.replace(path: '/api/gallery/thumb');
    final http.Response res;
    try {
      res = await _http
          .post(
            uri,
            headers: {..._headers(device), 'X-Media-Id': mediaId, 'Content-Type': 'image/jpeg'},
            body: jpeg,
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const GalleryException('Pas de réponse du PC.');
    } on SocketException catch (e) {
      throw GalleryException('Connexion refusée : ${e.message}');
    }

    if (res.statusCode != 200) {
      throw GalleryException('Envoi de la vignette refusé (${res.statusCode}).');
    }
  }

  Map<String, String> _headers(PairedDevice device) => {
        'Accept': 'application/json',
        'X-Device-Id': device.deviceId,
        'Authorization': 'Bearer ${device.token}',
      };

  void close() {
    if (_ownsHttp) _http.close();
  }
}
