import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'video_hub_client.dart';

/// Une transcription mise en cache (clé = lien + langue).
class CachedTranscript {
  final String url;
  final String lang;
  final String? thumbnail;
  final TranscriptDoc doc;
  final int dateMs;

  const CachedTranscript({
    required this.url,
    required this.lang,
    required this.doc,
    required this.dateMs,
    this.thumbnail,
  });

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(dateMs);

  Map<String, dynamic> toJson() => {
        'url': url,
        'lang': lang,
        'thumbnail': thumbnail,
        'doc': doc.toJson(),
        'dateMs': dateMs,
      };

  static CachedTranscript? tryFromJson(Map<String, dynamic> j) {
    final url = j['url'] as String?;
    final docJson = j['doc'];
    if (url == null || docJson is! Map) return null;
    return CachedTranscript(
      url: url,
      lang: (j['lang'] as String?) ?? 'fr',
      thumbnail: j['thumbnail'] as String?,
      doc: TranscriptDoc.fromJson(docJson.cast<String, dynamic>()),
      dateMs: (j['dateMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Cache local des transcriptions IA : évite de **refaire l'appel** (donc
/// d'économiser les requêtes Gemini) quand la même vidéo a déjà été transcrite.
///
/// **Expiration : 2 jours.** Les entrées plus vieilles sont purgées à chaque
/// lecture. Stocké en JSON dans le dossier de l'app ; tout échec d'E/S est
/// best-effort (on retombe sur un appel réseau normal).
class TranscriptCache {
  TranscriptCache._();

  static const ttl = Duration(days: 2);
  static const _fileName = 'transcript_cache.json';
  static const _maxEntries = 100;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Charge le cache en purgeant les entrées expirées (et réécrit si purge).
  static Future<List<CachedTranscript>> list() async {
    List<CachedTranscript> all;
    try {
      final f = await _file();
      if (!await f.exists()) return const [];
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return const [];
      all = raw
          .whereType<Map>()
          .map((e) => CachedTranscript.tryFromJson(e.cast<String, dynamic>()))
          .whereType<CachedTranscript>()
          .toList();
    } catch (_) {
      return const [];
    }
    final cutoff = DateTime.now().subtract(ttl).millisecondsSinceEpoch;
    final fresh = all.where((e) => e.dateMs >= cutoff).toList();
    if (fresh.length != all.length) await _save(fresh); // purge persistée
    return fresh;
  }

  /// Transcription en cache pour ce lien si elle existe et n'a pas expiré.
  static Future<TranscriptDoc?> get(String url, {String lang = 'fr'}) async {
    final key = url.trim();
    for (final e in await list()) {
      if (e.url == key && e.lang == lang) return e.doc;
    }
    return null;
  }

  /// Met en cache une transcription disponible (no-op si indisponible).
  static Future<void> put(
    String url,
    TranscriptDoc doc, {
    String lang = 'fr',
    String? thumbnail,
  }) async {
    if (!doc.available) return;
    final key = url.trim();
    final list0 = (await list()).toList()
      ..removeWhere((e) => e.url == key && e.lang == lang);
    list0.insert(
      0,
      CachedTranscript(
        url: key,
        lang: lang,
        thumbnail: thumbnail,
        doc: doc,
        dateMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (list0.length > _maxEntries) list0.removeRange(_maxEntries, list0.length);
    await _save(list0);
  }

  static Future<void> remove(CachedTranscript entry) async {
    final list0 = (await list()).toList()
      ..removeWhere((e) => e.url == entry.url && e.lang == entry.lang);
    await _save(list0);
  }

  static Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {
      // best-effort
    }
  }

  static Future<void> _save(List<CachedTranscript> list) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {
      // best-effort
    }
  }
}
