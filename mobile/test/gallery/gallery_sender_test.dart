import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/services/gallery/gallery_sender.dart';
import 'package:linkup_mobile/services/gallery/gallery_source.dart';
import 'package:linkup_mobile/services/pairing/paired_device_store.dart';
import 'package:linkup_mobile/services/transfer/transfer_client.dart';

const _device = PairedDevice(
  deviceId: 'dev-1',
  host: '192.168.1.50',
  port: 8000,
  token: 'device-token',
  pcPublicKey: 'pk',
  pcFingerprint: 'fp',
  pcName: 'mon-pc',
);

/// Source factice : connaît l'original des médias présents dans [originals].
class _FakeSource implements GalleryAssetSource {
  final Map<String, GalleryOriginal> originals;
  _FakeSource(this.originals);

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<List<GalleryAsset>> list({
    int page = 0,
    int size = 100,
    GalleryMediaType type = GalleryMediaType.all,
  }) async =>
      const [];

  @override
  Future<GalleryOriginal?> loadOriginal(String mediaId) async => originals[mediaId];
}

/// MockClient routant le flux transfert S4 complet (Laravel + bridge).
MockClient _transferMock() => MockClient((req) async {
      final path = req.url.path;
      if (req.method == 'POST' && path == '/api/transfers') {
        return http.Response(
          jsonEncode({'transfer_id': 'tx-1', 'upload_token': 'scoped', 'bridge_port': 8765}),
          201,
        );
      }
      if (req.method == 'GET' && path == '/transfer/tx-1/status') {
        return http.Response(jsonEncode({'received_chunks': []}), 200);
      }
      if (req.method == 'POST' && path == '/transfer/upload') {
        return http.Response('{"ok":true}', 200);
      }
      if (req.method == 'POST' && path == '/transfer/tx-1/finalize') {
        return http.Response('{"ok":true,"filename":"photo.jpg"}', 200);
      }
      if (req.method == 'POST' && path == '/api/transfers/tx-1/complete') {
        return http.Response('{"status":"completed"}', 200);
      }
      return http.Response('nf', 404);
    });

GalleryOriginal _orig(String name) =>
    GalleryOriginal(bytes: Uint8List.fromList([1, 2, 3, 4]), filename: name);

void main() {
  test('sends the originals of the selected media', () async {
    final sender = GallerySender(
      source: _FakeSource({'a': _orig('a.jpg'), 'b': _orig('b.jpg')}),
      transfers: TransferClient(httpClient: _transferMock(), chunkSize: 2),
    );

    final progresses = <int>[];
    final result = await sender.send(
      _device,
      ['a', 'b'],
      onProgress: (p) => progresses.add(p.done),
    );

    expect(result.sent, 2);
    expect(result.failed, 0);
    expect(progresses, isNotEmpty);
  });

  test('counts a missing original as a failure but keeps going', () async {
    final sender = GallerySender(
      source: _FakeSource({'a': _orig('a.jpg')}), // 'ghost' absent
      transfers: TransferClient(httpClient: _transferMock(), chunkSize: 2),
    );

    final result = await sender.send(_device, ['ghost', 'a']);

    expect(result.sent, 1);
    expect(result.failed, 1);
  });

  test('stops cleanly when cancelled', () async {
    final sender = GallerySender(
      source: _FakeSource({'a': _orig('a.jpg'), 'b': _orig('b.jpg')}),
      transfers: TransferClient(httpClient: _transferMock(), chunkSize: 2),
    );

    final result = await sender.send(_device, ['a', 'b'], isCancelled: () => true);

    expect(result.sent, 0); // annulé avant le premier envoi
  });
}
