import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

GalleryAsset _asset(String id) => GalleryAsset(
      meta: GalleryMeta(mediaId: id, mime: 'image/jpeg'),
      loadThumbnail: () async => Uint8List.fromList([1, 2, 3]),
    );

class _FakeSource implements GalleryAssetSource {
  final bool granted;
  final List<List<GalleryAsset>> pages;
  _FakeSource({this.granted = true, required this.pages});

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<List<GalleryAsset>> list({int page = 0, int size = 100}) async =>
      page < pages.length ? pages[page] : const [];
}

void main() {
  test('indexes metadata then uploads only the pending thumbnails', () async {
    var syncs = 0;
    final thumbs = <String>[];
    final mock = MockClient((req) async {
      if (req.url.path == '/api/gallery/sync') {
        syncs++;
        return http.Response(jsonEncode({'pending_thumbs': ['a', 'b']}), 200);
      }
      if (req.url.path == '/api/gallery/thumb') {
        thumbs.add(req.headers['x-media-id']!);
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('nf', 404);
    });

    final indexer = GalleryIndexer(
      source: _FakeSource(pages: [
        [_asset('a'), _asset('b'), _asset('c')], // 'c' a déjà sa vignette (pas pending)
      ]),
      client: GalleryClient(httpClient: mock),
    );

    await indexer.run(_device);

    expect(syncs, 1);
    expect(thumbs, ['a', 'b']); // 'c' non envoyé (pas dans pending)
  });

  test('throws GalleryException when permission is denied', () {
    final indexer = GalleryIndexer(
      source: _FakeSource(granted: false, pages: const []),
      client: GalleryClient(httpClient: MockClient((_) async => http.Response('', 200))),
    );

    expect(() => indexer.run(_device), throwsA(isA<GalleryException>()));
  });
}
