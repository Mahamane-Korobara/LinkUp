import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/models/linkup_agent.dart';
import 'package:linkup_mobile/screens/launch_gate.dart';
import 'package:linkup_mobile/services/agent_info_client.dart';
import 'package:linkup_mobile/services/pairing/paired_device_store.dart';
import 'package:linkup_mobile/services/pairing/pairing_verifier.dart';

import 'fakes/fake_discovery.dart';

class _FakeVerifier implements PairingVerifier {
  final PairingValidity result;
  const _FakeVerifier(this.result);
  @override
  Future<PairingValidity> verify(PairedDevice device) async => result;
}

/// Fetcher d'info agent qui ne touche pas au réseau.
class _FakeInfoClient implements AgentInfoFetcher {
  final AgentInfo value;
  _FakeInfoClient(this.value);

  @override
  Future<AgentInfo> fetch(LinkupAgent agent) async => value;

  @override
  void close() {}
}

void main() {
  group('LaunchGate', () {
    testWidgets('shows the agent picker when no PC is paired', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));

      await tester.pumpWidget(MaterialApp(
        home: LaunchGate(
          pairedStore: PairedDeviceStore(),
          discovery: FakeDiscovery(),
        ),
      ));
      await tester.pumpAndSettle();

      // Le picker est identifié par son FAB de saisie manuelle (le titre est
      // désormais le logo Linkup).
      expect(find.text('Saisie manuelle'), findsOneWidget);
      // Pas de saut vers le détail.
      expect(find.text('Appairé — appareil approuvé'), findsNothing);
    });

    testWidgets('auto-opens the paired PC detail on launch', (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'linkup.paired_device': jsonEncode(const PairedDevice(
          deviceId: 'd1',
          host: '192.168.1.50',
          port: 8000,
          token: 'tok',
          pcPublicKey: 'pk',
          pcFingerprint: '5307611f',
          pcName: 'mon-pc',
        ).toJson()),
      });
      addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));

      await tester.pumpWidget(MaterialApp(
        home: LaunchGate(
          pairedStore: PairedDeviceStore(),
          discovery: FakeDiscovery(),
          verifier: const _FakeVerifier(PairingValidity.valid),
          detailClient: _FakeInfoClient(const AgentInfo(
            name: 'mon-pc',
            fingerprint: '5307611f',
            version: '0.1.0',
            source: 'bridge',
          )),
        ),
      ));
      await tester.pumpAndSettle();

      // On a navigué automatiquement vers le détail du PC appairé.
      expect(find.text('mon-pc'), findsWidgets); // appbar + ligne nom
      expect(find.text('Appairé — appareil approuvé'), findsOneWidget);
      expect(find.text('5307611f'), findsOneWidget);
    });
  });
}
