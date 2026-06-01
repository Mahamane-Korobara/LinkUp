import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/screens/gallery/gallery_screen.dart';
import 'package:linkup_mobile/services/gallery/gallery_client.dart';
import 'package:linkup_mobile/services/gallery/gallery_indexer.dart';
import 'package:linkup_mobile/services/gallery/gallery_source.dart';
import 'package:linkup_mobile/services/pairing/paired_device_store.dart';

const _device = PairedDevice(
  deviceId: 'dev-1',
  host: '192.168.1.50',
  port: 8000,
  token: 'device-token',
  pcPublicKey: 'pk',
  pcFingerprint: 'fp',
  pcName: 'mon-pc',
);

class _FakeSource implements GalleryAssetSource {
  final bool granted;
  _FakeSource({this.granted = true});

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<List<GalleryAsset>> list({int page = 0, int size = 100}) async => page == 0
      ? [
          GalleryAsset(
            meta: const GalleryMeta(mediaId: 'a', mime: 'image/jpeg'),
            loadThumbnail: () async => Uint8List.fromList([1, 2, 3]),
          ),
        ]
      : const [];
}

GalleryIndexer _indexer({bool granted = true}) {
  final mock = MockClient((req) async {
    if (req.url.path == '/api/gallery/sync') {
      return http.Response(jsonEncode({'pending_thumbs': ['a']}), 200);
    }
    if (req.url.path == '/api/gallery/thumb') {
      return http.Response('{"ok":true}', 200);
    }
    return http.Response('nf', 404);
  });
  return GalleryIndexer(source: _FakeSource(granted: granted), client: GalleryClient(httpClient: mock));
}

void main() {
  testWidgets('indexes the gallery and shows success', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: GalleryScreen(device: _device, indexer: _indexer()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Indexer ma galerie'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Galerie indexée'), findsOneWidget);
  });

  testWidgets('shows an error when the permission is denied', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: GalleryScreen(device: _device, indexer: _indexer(granted: false)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Indexer ma galerie'));
    await tester.pumpAndSettle();

    expect(find.text('Indexation impossible'), findsOneWidget);
    expect(find.textContaining('Permission'), findsOneWidget);
  });
}
