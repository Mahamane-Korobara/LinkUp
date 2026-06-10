import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/screens/tools/video_tool_screen.dart';
import 'package:linkup_mobile/services/transfer/received_saver.dart';
import 'package:linkup_mobile/services/video/video_hub_client.dart';

class _FakeSaver extends ReceivedFileSaver {
  @override
  Future<SaveResult> save(String filename, Uint8List bytes) async =>
      const SaveResult(SaveKind.document, location: 'Documents');
}

void main() {
  testWidgets('analyse un lien et affiche l\'aperçu + actions', (tester) async {
    final mock = MockClient((req) async {
      expect(req.url.path, endsWith('/resolve'));
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'title': 'Ma vidéo',
          'uploader': 'Chaîne',
          'duration': 75,
          'thumbnail': null, // pas d'Image.network en test
          'has_subtitles': false,
          'subtitle_source': 'none',
          'subtitle_langs': [],
        })),
        200,
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: VideoToolScreen(
        client: VideoHubClient(serviceToken: 't', httpClient: mock),
        saver: _FakeSaver(),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'https://x.test/v');
    await tester.tap(find.text('Analyser'));
    await tester.pumpAndSettle();

    expect(find.text('Ma vidéo'), findsOneWidget);

    // Les tuiles d'action sont en bas du ListView (lazy) — on scrolle jusqu'à la
    // dernière avant d'asserter.
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Transcription IA'),
      300,
      scrollable: scrollable,
    );
    expect(find.text('Télécharger la vidéo'), findsOneWidget);
    expect(find.text('Transcription IA'), findsOneWidget);
    // Sous-titres absents → la tuile transcript affiche le message dédié.
    expect(find.text('Sous-titres non présents sur cette vidéo'), findsOneWidget);
  });
}
