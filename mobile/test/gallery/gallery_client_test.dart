import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/services/gallery/gallery_client.dart';
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

void main() {
  test('syncBatch posts items and returns pending thumbs', () async {
    Map<String, dynamic>? sent;
    final mock = MockClient((req) async {
      expect(req.url.path, '/api/gallery/sync');
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'pending_thumbs': ['1', '2']}), 200);
    });

    final pending = await GalleryClient(httpClient: mock).syncBatch(_device, [
      const GalleryMeta(mediaId: '1', mime: 'image/jpeg', size: 10),
      const GalleryMeta(mediaId: '2', mime: 'video/mp4'),
    ]);

    expect(pending, ['1', '2']);
    expect((sent!['items'] as List).length, 2);
  });

  test('uploadThumbnail posts the bytes with the X-Media-Id header', () async {
    String? mediaId;
    List<int>? body;
    final mock = MockClient((req) async {
      mediaId = req.headers['x-media-id'];
      body = req.bodyBytes;
      return http.Response('{"ok":true}', 200);
    });

    await GalleryClient(httpClient: mock).uploadThumbnail(_device, '42', [9, 9, 9]);

    expect(mediaId, '42');
    expect(body, [9, 9, 9]);
  });

  test('syncBatch throws on 401 (expired pairing)', () {
    final mock = MockClient((_) async => http.Response('{"m":"no"}', 401));
    expect(
      () => GalleryClient(httpClient: mock).syncBatch(_device, const []),
      throwsA(isA<GalleryException>()),
    );
  });
}
