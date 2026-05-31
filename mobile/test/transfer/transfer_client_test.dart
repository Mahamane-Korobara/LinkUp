import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/services/pairing/paired_device_store.dart';
import 'package:linkup_mobile/services/transfer/transfer_client.dart';

const _device = PairedDevice(
  deviceId: 'dev-1',
  host: '192.168.1.50',
  port: 8000,
  token: 'device-token',
  pcPublicKey: 'pk',
  pcFingerprint: '5307611f',
  pcName: 'mon-pc',
);

/// Routeur MockClient configurable. Enregistre les chunks uploadés + le finalize.
class _Backend {
  final Set<int> alreadyReceived;
  final List<int> uploaded = [];
  bool finalized = false;
  bool completed = false;
  String? completedStoredName;
  Map<String, dynamic>? finalizeHeaders;
  int initiateStatus;

  _Backend({this.alreadyReceived = const {}, this.initiateStatus = 201});

  MockClient client() => MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'POST' && path == '/api/transfers') {
          if (initiateStatus != 201) {
            return http.Response('{"message":"nope"}', initiateStatus);
          }
          return http.Response(
            jsonEncode({
              'transfer_id': 'tx-1',
              'upload_token': 'scoped-token',
              'bridge_port': 8765,
            }),
            201,
          );
        }
        if (req.method == 'GET' && path == '/transfer/tx-1/status') {
          return http.Response(
            jsonEncode({'received_chunks': alreadyReceived.toList()}),
            200,
          );
        }
        if (req.method == 'POST' && path == '/transfer/upload') {
          // Auth scopée présente ?
          expect(req.headers['authorization'], 'Bearer scoped-token');
          uploaded.add(int.parse(req.headers['x-chunk-index']!));
          return http.Response('{"ok":true}', 200);
        }
        if (req.method == 'POST' && path == '/transfer/tx-1/finalize') {
          finalized = true;
          finalizeHeaders = {
            'filename': req.headers['x-transfer-filename'],
            'total': req.headers['x-transfer-total-chunks'],
          };
          return http.Response('{"ok":true,"filename":"a.bin"}', 200);
        }
        if (req.method == 'POST' && path == '/api/transfers/tx-1/complete') {
          completed = true;
          completedStoredName =
              (jsonDecode(req.body) as Map<String, dynamic>)['stored_name'] as String?;
          return http.Response('{"status":"completed"}', 200);
        }
        return http.Response('not found', 404);
      });
}

void main() {
  group('TransferClient', () {
    test('uploads all chunks then finalizes', () async {
      final backend = _Backend();
      final client = TransferClient(httpClient: backend.client(), chunkSize: 4);

      final progresses = <double>[];
      await client.uploadBytes(
        device: _device,
        filename: 'a.bin',
        bytes: List<int>.generate(10, (i) => i), // 10 octets → 3 chunks (4,4,2)
        onProgress: (p) => progresses.add(p.fraction),
      );

      expect(backend.uploaded, [0, 1, 2]);
      expect(backend.finalized, isTrue);
      expect(backend.finalizeHeaders!['filename'], 'a.bin');
      expect(backend.finalizeHeaders!['total'], '3');
      // La progression atteint 100%.
      expect(progresses.last, 1.0);
      // Laravel est notifié de la fin (fix du statut « en attente »).
      expect(backend.completed, isTrue);
      expect(backend.completedStoredName, 'a.bin');
    });

    test('resumes by skipping already-received chunks', () async {
      final backend = _Backend(alreadyReceived: {0, 1});
      final client = TransferClient(httpClient: backend.client(), chunkSize: 4);

      await client.uploadBytes(
        device: _device,
        filename: 'a.bin',
        bytes: List<int>.generate(10, (i) => i),
      );

      // Seul le chunk manquant (2) est ré-uploadé.
      expect(backend.uploaded, [2]);
      expect(backend.finalized, isTrue);
    });

    test('throws on 401 at initiate (expired pairing)', () async {
      final backend = _Backend(initiateStatus: 401);
      final client = TransferClient(httpClient: backend.client(), chunkSize: 4);

      expect(
        () => client.uploadBytes(
          device: _device,
          filename: 'a.bin',
          bytes: [1, 2, 3],
        ),
        throwsA(isA<TransferException>()),
      );
    });
  });
}
