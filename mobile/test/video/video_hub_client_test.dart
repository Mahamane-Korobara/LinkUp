import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/services/video/video_hub_client.dart';

VideoHubClient _client(MockClient mock) =>
    VideoHubClient(serviceToken: 'tok', httpClient: mock);

// Le serveur renvoie de l'utf-8 brut → on encode les octets en utf-8 (le
// constructeur String de http.Response retombe sur latin1 en l'absence de charset).
http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

void main() {
  test('resolve parse les métadonnées', () async {
    final mock = MockClient((req) async {
      expect(req.url.path, endsWith('/resolve'));
      expect(req.headers['Authorization'], 'Bearer tok');
      return _json({
          'title': 'Ma vidéo',
          'uploader': 'Chaîne',
          'duration': 95,
          'thumbnail': 'https://x/t.jpg',
          'has_subtitles': true,
          'subtitle_source': 'manual',
          'subtitle_langs': ['fr', 'en'],
      });
    });
    final meta = await _client(mock).resolve('https://x.test/v');
    expect(meta.title, 'Ma vidéo');
    expect(meta.durationSeconds, 95);
    expect(meta.hasSubtitles, isTrue);
    expect(meta.subtitleLangs, ['fr', 'en']);
  });

  test('transcript indisponible renvoie la raison', () async {
    final mock = MockClient((req) async => _json({
          'available': false,
          'title': 'Sans ST',
          'reason': 'Sous-titres non présents sur cette vidéo.',
        }));
    final doc = await _client(mock).transcript('https://x.test/v');
    expect(doc.available, isFalse);
    expect(doc.reason, contains('non présents'));
  });

  test('transcript disponible parse les sections', () async {
    final mock = MockClient((req) async => _json({
          'available': true,
          'title': 'Doc',
          'subtitle_source': 'auto',
          'formatted_by': 'gemini',
          'sections': [
            {
              'heading': 'Intro',
              'paragraphs': ['Bonjour.', '  ', 'Suite.'],
            },
          ],
        }));
    final doc = await _client(mock).transcript('https://x.test/v');
    expect(doc.available, isTrue);
    expect(doc.formattedBy, 'gemini');
    expect(doc.sections.single.heading, 'Intro');
    // Le paragraphe vide est filtré.
    expect(doc.sections.single.paragraphs, ['Bonjour.', 'Suite.']);
  });

  test('erreur HTTP remonte le détail FastAPI', () async {
    final mock = MockClient((req) async => _json({'detail': 'Lien invalide.'}, 400));
    expect(
      () => _client(mock).resolve('bad'),
      throwsA(isA<VideoHubException>()
          .having((e) => e.message, 'message', 'Lien invalide.')),
    );
  });
}
