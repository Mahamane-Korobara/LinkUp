import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:linkup_mobile/screens/transfer/file_transfer_screen.dart';
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

MockClient _happyBackend() => MockClient((req) async {
      final path = req.url.path;
      if (path == '/api/transfers') {
        return http.Response(
          '{"transfer_id":"tx-1","upload_token":"scoped","bridge_port":8765}',
          201,
        );
      }
      if (path == '/transfer/tx-1/status') {
        return http.Response('{"received_chunks":[]}', 200);
      }
      if (path == '/transfer/upload') return http.Response('{"ok":true}', 200);
      if (path == '/transfer/tx-1/finalize') return http.Response('{"ok":true}', 200);
      return http.Response('nf', 404);
    });

void main() {
  testWidgets('picks a file and shows success after upload', (tester) async {
    final client = TransferClient(httpClient: _happyBackend(), chunkSize: 4);

    await tester.pumpWidget(MaterialApp(
      home: FileTransferScreen(
        device: _device,
        client: client,
        pickFile: () async => const PickedFile('doc.pdf', [1, 2, 3, 4, 5]),
      ),
    ));

    expect(find.text('Choisir un fichier'), findsOneWidget);
    await tester.tap(find.text('Choisir un fichier'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Envoyé'), findsOneWidget);
    expect(find.textContaining('doc.pdf'), findsWidgets);
  });

  testWidgets('shows an error and a retry button on upload failure',
      (tester) async {
    // Backend qui refuse l'initiation → TransferException.
    final failing = MockClient((req) async => http.Response('{"m":"no"}', 500));
    final client = TransferClient(httpClient: failing, chunkSize: 4);

    await tester.pumpWidget(MaterialApp(
      home: FileTransferScreen(
        device: _device,
        client: client,
        pickFile: () async => const PickedFile('doc.pdf', [1, 2, 3]),
      ),
    ));

    await tester.tap(find.text('Choisir un fichier'));
    await tester.pumpAndSettle();

    expect(find.text('Échec de l\'envoi'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });
}
