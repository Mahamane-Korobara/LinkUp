import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Métadonnées d'aperçu d'une vidéo (réponse de `/video/resolve`).
class VideoMeta {
  final String title;
  final String uploader;
  final String extractor;
  final int? durationSeconds;
  final String? thumbnail;
  final bool hasSubtitles;
  final String subtitleSource; // manual | auto | none
  final List<String> subtitleLangs;

  const VideoMeta({
    required this.title,
    required this.uploader,
    required this.extractor,
    required this.durationSeconds,
    required this.thumbnail,
    required this.hasSubtitles,
    required this.subtitleSource,
    required this.subtitleLangs,
  });

  factory VideoMeta.fromJson(Map<String, dynamic> j) => VideoMeta(
        title: (j['title'] as String?) ?? 'Vidéo',
        uploader: (j['uploader'] as String?) ?? '',
        extractor: (j['extractor'] as String?) ?? '',
        durationSeconds: (j['duration'] as num?)?.toInt(),
        thumbnail: j['thumbnail'] as String?,
        hasSubtitles: (j['has_subtitles'] as bool?) ?? false,
        subtitleSource: (j['subtitle_source'] as String?) ?? 'none',
        subtitleLangs:
            ((j['subtitle_langs'] as List?) ?? const []).map((e) => '$e').toList(),
      );
}

/// Une section du transcript formaté (titre optionnel + paragraphes).
class TranscriptSection {
  final String? heading;
  final List<String> paragraphs;
  const TranscriptSection(this.heading, this.paragraphs);
}

/// Réponse de `/video/transcript`. Quand [available] est faux, [reason] explique
/// pourquoi (ex. « Sous-titres non présents sur cette vidéo. »).
class TranscriptDoc {
  final bool available;
  final String title;
  final String? reason;
  final String? subtitleSource; // manual | auto
  final String formattedBy; // gemini | heuristic
  final List<TranscriptSection> sections;

  const TranscriptDoc({
    required this.available,
    required this.title,
    this.reason,
    this.subtitleSource,
    this.formattedBy = 'heuristic',
    this.sections = const [],
  });

  factory TranscriptDoc.fromJson(Map<String, dynamic> j) {
    if (j['available'] != true) {
      return TranscriptDoc(
        available: false,
        title: (j['title'] as String?) ?? 'Transcript',
        reason: j['reason'] as String?,
      );
    }
    final sections = ((j['sections'] as List?) ?? const [])
        .whereType<Map>()
        .map((s) => TranscriptSection(
              s['heading'] as String?,
              ((s['paragraphs'] as List?) ?? const [])
                  .map((e) => '$e')
                  .where((e) => e.trim().isNotEmpty)
                  .toList(),
            ))
        .toList();
    return TranscriptDoc(
      available: true,
      title: (j['title'] as String?) ?? 'Transcript',
      subtitleSource: j['subtitle_source'] as String?,
      formattedBy: (j['formatted_by'] as String?) ?? 'heuristic',
      sections: sections,
    );
  }
}

/// Échec d'appel au service (réseau, lien refusé, quota…), message lisible.
class VideoHubException implements Exception {
  final String message;
  const VideoHubException(this.message);
  @override
  String toString() => message;
}

/// Client du service VideoHub (VPS). `resolve`/`transcript` passent par un
/// `http.Client` injectable (testable) ; `downloadToFile` streame via `HttpClient`
/// pour ne pas charger toute la vidéo en RAM.
class VideoHubClient {
  /// URL publique du service (Apache → uvicorn). Surchargée en test/dev.
  final String baseUrl;

  /// Token de service Bearer — DOIT correspondre à `LINKUP_VIDEOHUB_SERVICE_TOKEN`
  /// du `.env` sur le VPS (cf. infra/videohub/README.md). NOTE : extractible de
  /// l'APK, ce n'est pas un secret fort — juste un garde-fou anti-abus.
  final String serviceToken;

  final http.Client _http;

  VideoHubClient({
    this.baseUrl = 'https://linkup.sahelstack.tech/video',
    this.serviceToken = _defaultServiceToken,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  // Token de service partagé avec le VPS (= LINKUP_VIDEOHUB_SERVICE_TOKEN du .env).
  // Garde-fou anti-abus, pas un secret fort (extractible de l'APK).
  static const _defaultServiceToken = '6RKl8G9UQoZde9clf0XJywra5o2fC5V4qoCA6Dgu_hQ';

  Map<String, String> get _authHeader => {'Authorization': 'Bearer $serviceToken'};

  Future<VideoMeta> resolve(String url) async {
    final uri = Uri.parse('$baseUrl/resolve').replace(queryParameters: {'url': url});
    final resp = await _http.get(uri, headers: _authHeader);
    final body = _decode(resp);
    return VideoMeta.fromJson(body);
  }

  Future<TranscriptDoc> transcript(String url, {String lang = 'fr'}) async {
    final uri = Uri.parse('$baseUrl/transcript')
        .replace(queryParameters: {'url': url, 'lang': lang});
    final resp = await _http.get(uri, headers: _authHeader);
    final body = _decode(resp);
    return TranscriptDoc.fromJson(body);
  }

  Map<String, dynamic> _decode(http.Response resp) {
    if (resp.statusCode == 200) {
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    }
    // Le service renvoie {"detail": "..."} sur erreur (FastAPI HTTPException).
    String detail = 'Erreur ${resp.statusCode}';
    try {
      final j = jsonDecode(utf8.decode(resp.bodyBytes));
      if (j is Map && j['detail'] is String) detail = j['detail'] as String;
    } catch (_) {/* corps non-JSON : on garde le message générique */}
    throw VideoHubException(detail);
  }

  /// Télécharge la vidéo (ou l'audio) dans un fichier temporaire et le renvoie.
  /// [onProgress] reçoit un ratio 0..1 quand la taille est connue.
  Future<File> downloadToFile(
    String url, {
    String kind = 'video',
    int quality = 720,
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.parse('$baseUrl/download').replace(queryParameters: {
      'url': url,
      'kind': kind,
      'quality': '$quality',
    });
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $serviceToken');
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw VideoHubException('Téléchargement refusé (${resp.statusCode}).');
      }

      final name = _filenameFromDisposition(
        resp.headers.value('content-disposition'),
        fallbackKind: kind,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      final sink = file.openWrite();
      final total = resp.contentLength; // -1 si inconnu
      var received = 0;
      try {
        await for (final chunk in resp) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0 && onProgress != null) onProgress(received / total);
        }
      } finally {
        await sink.close();
      }
      return file;
    } finally {
      client.close();
    }
  }

  /// Extrait le nom de fichier du header `Content-Disposition`, avec repli.
  static String _filenameFromDisposition(String? header,
      {required String fallbackKind}) {
    if (header != null) {
      final m = RegExp(r'filename="?([^";]+)"?').firstMatch(header);
      if (m != null) {
        final raw = m.group(1)!.trim();
        // Anti-traversal : on ne garde que le dernier segment.
        final base = raw.split(RegExp(r'[/\\]')).last.trim();
        if (base.isNotEmpty && base != '.' && base != '..') return base;
      }
    }
    final ext = fallbackKind == 'audio' ? 'm4a' : 'mp4';
    return 'linkup-video.$ext';
  }

  void close() => _http.close();
}
