import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/screens/transfer/incoming_screen.dart';
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

class _NoopSaver implements MediaSaver {
  @override
  Future<bool> save(String filename, Uint8List bytes, {required bool isVideo}) async => true;
}

/// Récepteur factice : renvoie un bilan déterministe sans réseau.
class _FakeReceiver extends IncomingReceiver {
  final IncomingResult result;
  _FakeReceiver(this.result) : super(transfers: TransferClient(), saver: _NoopSaver());

  @override
  Future<IncomingResult> run(
    PairedDevice device, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async =>
      result;
}

void main() {
  testWidgets('fetches and shows how many files were saved', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: IncomingScreen(device: _device, receiver: _FakeReceiver(const IncomingResult(saved: 2, failed: 0))),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Récupérer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 fichier(s) enregistré(s)'), findsOneWidget);
  });

  testWidgets('shows an empty state when nothing is waiting', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: IncomingScreen(device: _device, receiver: _FakeReceiver(const IncomingResult(saved: 0, failed: 0))),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Récupérer'));
    await tester.pumpAndSettle();

    expect(find.text('Aucun fichier en attente.'), findsOneWidget);
  });
}
