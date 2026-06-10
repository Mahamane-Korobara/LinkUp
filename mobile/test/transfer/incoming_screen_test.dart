import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/screens/transfer/incoming_screen.dart';
import 'package:linkup_mobile/services/pairing/paired_device_store.dart';
import 'package:linkup_mobile/services/transfer/incoming_receiver.dart';
import 'package:linkup_mobile/services/transfer/received_saver.dart';
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

class _NoopSaver extends ReceivedFileSaver {
  @override
  Future<SaveResult> save(String filename, Uint8List bytes) async => const SaveResult(SaveKind.gallery);
}

/// MockClient qui sert la liste des entrants donnée.
MockClient _mock(List<String> names) => MockClient((req) async {
      if (req.url.path == '/api/transfers/incoming') {
        return http.Response(
          jsonEncode({
            'transfers': [
              for (final n in names) {'transfer_id': 'tx-$n', 'filename': n, 'direction': 'to_phone', 'status': 'completed'},
            ],
          }),
          200,
        );
      }
      return http.Response('{"ok":true}', 200);
    });

/// Récepteur factice : transfers branché sur un MockClient (pour la LISTE),
/// run() renvoie un bilan déterministe sans réseau réel.
class _FakeReceiver extends IncomingReceiver {
  final IncomingResult result;
  _FakeReceiver(List<String> names, this.result)
      : super(transfers: TransferClient(httpClient: _mock(names)), saver: _NoopSaver());

  @override
  Future<IncomingResult> run(
    PairedDevice device, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async =>
      result;
}

void main() {
  testWidgets('lists pending files and fetches them', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: IncomingScreen(
        device: _device,
        pollInterval: null, // pas de timer périodique en test
        receiver: _FakeReceiver(['photo.jpg', 'rapport.pdf'], const IncomingResult(gallery: 1, documents: 1)),
      ),
    ));
    await tester.pumpAndSettle();

    // La liste montre les deux fichiers + le bouton compte 2.
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('rapport.pdf'), findsOneWidget);
    expect(find.text('Récupérer 2 fichier(s)'), findsOneWidget);

    await tester.tap(find.text('Récupérer 2 fichier(s)'));
    await tester.pump();
    await tester.pump();

    // Bilan affiché en SnackBar.
    expect(find.textContaining('1 dans la galerie'), findsOneWidget);
    expect(find.textContaining('1 dans « LinkupReçus »'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5)); // purge le timer du SnackBar
  });

  testWidgets('shows an empty state when nothing is waiting', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: IncomingScreen(
          device: _device, pollInterval: null, receiver: _FakeReceiver(const [], const IncomingResult())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Aucun fichier en attente'), findsOneWidget);
    expect(find.textContaining('Aucun fichier envoyé par le PC'), findsOneWidget);
  });
}
