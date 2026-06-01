import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/services/pairing/paired_device_store.dart';
import 'package:linkup_mobile/services/transfer/incoming_receiver.dart';
import 'package:linkup_mobile/services/transfer/media_saver.dart';
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

/// Saver factice : note ce qui a été enregistré ; échoue pour les noms de [fail].
class _FakeSaver implements MediaSaver {
  final List<String> saved = [];
  final Set<String> fail;
  _FakeSaver({this.fail = const {}});

  @override
  Future<bool> save(String filename, Uint8List bytes, {required bool isVideo}) async {
    if (fail.contains(filename)) return false;
    saved.add(filename);
    return true;
  }
}

MockClient _mock({required List<Map<String, String>> incoming, required List<String> delivered}) {
  return MockClient((req) async {
    final path = req.url.path;
    if (req.method == 'GET' && path == '/api/transfers/incoming') {
      return http.Response(
        jsonEncode({
          'transfers': [
            for (final t in incoming)
              {'transfer_id': t['id'], 'filename': t['name'], 'direction': 'to_phone', 'status': 'completed'},
          ],
        }),
        200,
      );
    }
    if (req.method == 'GET' && path.endsWith('/download')) {
      return http.Response.bytes([1, 2, 3], 200);
    }
    if (req.method == 'POST' && path.endsWith('/delivered')) {
      delivered.add(path);
      return http.Response('{"ok":true}', 200);
    }
    return http.Response('nf', 404);
  });
}

void main() {
  test('downloads, saves to gallery and confirms each incoming file', () async {
    final delivered = <String>[];
    final saver = _FakeSaver();
    final receiver = IncomingReceiver(
      transfers: TransferClient(httpClient: _mock(
        incoming: [
          {'id': 'tx-1', 'name': 'a.jpg'},
          {'id': 'tx-2', 'name': 'b.mp4'},
        ],
        delivered: delivered,
      )),
      saver: saver,
    );

    final result = await receiver.run(_device);

    expect(result.saved, 2);
    expect(result.failed, 0);
    expect(saver.saved, ['a.jpg', 'b.mp4']);
    expect(delivered, ['/api/transfers/tx-1/delivered', '/api/transfers/tx-2/delivered']);
  });

  test('a failed save is not confirmed (stays pending)', () async {
    final delivered = <String>[];
    final receiver = IncomingReceiver(
      transfers: TransferClient(httpClient: _mock(
        incoming: [{'id': 'tx-1', 'name': 'broken.jpg'}],
        delivered: delivered,
      )),
      saver: _FakeSaver(fail: {'broken.jpg'}),
    );

    final result = await receiver.run(_device);

    expect(result.saved, 0);
    expect(result.failed, 1);
    expect(delivered, isEmpty); // pas confirmé → réessayable
  });

  test('returns empty when nothing is waiting', () async {
    final receiver = IncomingReceiver(
      transfers: TransferClient(httpClient: _mock(incoming: const [], delivered: [])),
      saver: _FakeSaver(),
    );

    expect((await receiver.run(_device)).isEmpty, isTrue);
  });
}
