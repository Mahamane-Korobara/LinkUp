import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/screens/transfer/transfers_screen.dart';
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

TransferClient _clientReturning(List<Map<String, dynamic>> transfers) {
  final mock = MockClient((req) async {
    if (req.url.path == '/api/transfers' && req.method == 'GET') {
      return http.Response(jsonEncode({'transfers': transfers}), 200);
    }
    return http.Response('nf', 404);
  });
  return TransferClient(httpClient: mock);
}

void main() {
  testWidgets('lists sent files from the history', (tester) async {
    final client = _clientReturning([
      {
        'transfer_id': 't1',
        'filename': 'photo.jpg',
        'size': 2048,
        'direction': 'to_pc',
        'status': 'completed',
        'created_at': '2026-05-31T10:00:00+00:00',
        'completed_at': '2026-05-31T10:00:05+00:00',
      },
      {
        'transfer_id': 't2',
        'filename': 'rapport.pdf',
        'size': 1048576,
        'direction': 'to_pc',
        'status': 'failed',
        'created_at': '2026-05-31T09:00:00+00:00',
      },
    ]);

    await tester.pumpWidget(MaterialApp(
      home: TransfersScreen(device: _device, client: client),
    ));
    await tester.pumpAndSettle();

    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('rapport.pdf'), findsOneWidget);
    expect(find.text('Envoyé'), findsOneWidget); // statut completed
    expect(find.text('Échec'), findsOneWidget); // statut failed
    expect(find.text('Envoyer un fichier'), findsOneWidget); // FAB d'envoi
    expect(find.text('Ouvrir ›'), findsOneWidget); // affordance sur le completed
  });

  MockClient completedListWith({List<int>? downloadBytes}) => MockClient((req) async {
        if (req.url.path == '/api/transfers' && req.method == 'GET') {
          return http.Response(
            jsonEncode({
              'transfers': [
                {
                  'transfer_id': 't1',
                  'filename': 'photo.jpg',
                  'size': 2048,
                  'direction': 'to_pc',
                  'status': 'completed',
                },
              ],
            }),
            200,
          );
        }
        if (req.method == 'GET' && req.url.path == '/api/transfers/t1/download') {
          return http.Response.bytes(downloadBytes ?? [1, 2, 3], 200);
        }
        return http.Response('nf', 404);
      });

  testWidgets('tap sur un fichier terminé → télécharge et ouvre sur le téléphone',
      (tester) async {
    String? openedName;
    List<int>? openedBytes;
    final client = TransferClient(httpClient: completedListWith(downloadBytes: [9, 8, 7]));

    await tester.pumpWidget(MaterialApp(
      home: TransfersScreen(
        device: _device,
        client: client,
        openLocalFile: (name, bytes) async {
          openedName = name;
          openedBytes = bytes;
        },
      ),
    ));
    await tester.pumpAndSettle();

    // Plus de menu : un tap ouvre directement sur le téléphone.
    await tester.tap(find.text('photo.jpg'));
    await tester.pumpAndSettle();

    expect(openedName, 'photo.jpg');
    expect(openedBytes, [9, 8, 7]);
  });

  testWidgets('shows an empty state when no transfer yet', (tester) async {
    final client = _clientReturning([]);

    await tester.pumpWidget(MaterialApp(
      home: TransfersScreen(device: _device, client: client),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Aucun fichier envoyé'), findsOneWidget);
  });

  testWidgets('shows an error with retry on 401', (tester) async {
    final mock = MockClient((req) async => http.Response('{"m":"no"}', 401));
    final client = TransferClient(httpClient: mock);

    await tester.pumpWidget(MaterialApp(
      home: TransfersScreen(device: _device, client: client),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Appairage expiré'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });
}
