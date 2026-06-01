import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/services/gallery/gallery_client.dart';
import 'package:linkup_mobile/services/gallery/gallery_importer.dart';
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
  Future<List<GalleryAsset>> list({int page = 0, int size = 100}) async => const [];

  @override
  Future<GalleryOriginal?> loadOriginal(String mediaId) async => originals[mediaId];
}

/// Routeur commun galerie + transfert. `done` enregistre les imports confirmés.
MockClient _mock({required List<String> pending, required List<String> done}) {
  return MockClient((req) async {
    final path = req.url.path;

    // --- galerie ---
    if (req.method == 'GET' && path == '/api/gallery/imports') {
      return http.Response(
        jsonEncode({
          'imports': [
            for (final p in pending) {'id': 'imp-$p', 'media_id': p, 'mime': 'image/jpeg'},
          ],
        }),
        200,
      );
    }
    if (req.method == 'POST' && path.startsWith('/api/gallery/imports/')) {
      done.add(jsonDecode(req.body)['transfer_id'] as String? ?? 'null:$path');
      return http.Response('{"ok":true}', 200);
    }

    // --- transfert S4 (flux complet) ---
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
}

GalleryOriginal _orig(String name) =>
    GalleryOriginal(bytes: Uint8List.fromList([1, 2, 3, 4]), filename: name);

void main() {
  test('uploads the original then confirms the import with the transfer id', () async {
    final done = <String>[];
    final mock = _mock(pending: ['a'], done: done);
    final importer = GalleryImporter(
      source: _FakeSource({'a': _orig('a.jpg')}),
      client: GalleryClient(httpClient: mock),
      transfers: TransferClient(httpClient: mock, chunkSize: 2),
    );

    final result = await importer.run(_device);

    expect(result.imported, 1);
    expect(result.failed, 0);
    expect(done, ['tx-1']); // import confirmé en pointant le transfert
  });

  test('returns empty when the PC requested nothing', () async {
    final mock = _mock(pending: const [], done: []);
    final importer = GalleryImporter(
      source: _FakeSource(const {}),
      client: GalleryClient(httpClient: mock),
      transfers: TransferClient(httpClient: mock),
    );

    final result = await importer.run(_device);

    expect(result.isEmpty, isTrue);
  });

  test('closes a deleted media (no original) as a failure but still confirms', () async {
    final done = <String>[];
    final mock = _mock(pending: ['ghost'], done: done);
    final importer = GalleryImporter(
      source: _FakeSource(const {}), // 'ghost' introuvable
      client: GalleryClient(httpClient: mock),
      transfers: TransferClient(httpClient: mock),
    );

    final result = await importer.run(_device);

    expect(result.imported, 0);
    expect(result.failed, 1);
    expect(done, ['null:/api/gallery/imports/imp-ghost/done']); // confirmée sans transfert
  });
}
