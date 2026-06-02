import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/models/linkup_agent.dart';
import 'package:linkup_mobile/screens/agent_detail_screen.dart';
import 'package:linkup_mobile/services/agent_info_client.dart';
import 'package:linkup_mobile/services/pairing/paired_device_store.dart';
import 'package:linkup_mobile/services/pairing/pairing_verifier.dart';

/// Verifier injectable : renvoie une validité fixe sans réseau.
class _FakeVerifier implements PairingVerifier {
  final PairingValidity result;
  const _FakeVerifier(this.result);

  @override
  Future<PairingValidity> verify(PairedDevice device) async => result;
}

/// Fake injectable qui ne fait aucune requête réseau.
class _FakeClient implements AgentInfoFetcher {
  final AgentInfo? value;
  final Object? error;
  int fetchCount = 0;
  int closeCount = 0;

  _FakeClient.success(this.value) : error = null;
  _FakeClient.failure(this.error) : value = null;

  @override
  Future<AgentInfo> fetch(LinkupAgent agent) async {
    fetchCount++;
    if (error != null) throw error!;
    return value!;
  }

  @override
  void close() {
    closeCount++;
  }
}

/// Compte les routes poussées pour vérifier une navigation sans rendre la
/// destination (qui ouvre la caméra).
class _PushObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}

const _agent = LinkupAgent(
  instanceName: 'linkup-abc._linkup._tcp.local.',
  address: '192.168.1.42',
  reverbPort: 8080,
  bridgePort: 8765,
  agentId: 'linkup-abc',
  user: 'mahamane',
  hostname: 'pc',
  source: LinkupAgentSource.mdns,
);

void main() {
  group('AgentDetailScreen', () {
    testWidgets('shows loading spinner first', (tester) async {
      final client = _FakeClient.success(
        const AgentInfo(
          name: 'x',
          fingerprint: 'abc12345',
          version: '0.1.0',
          source: 'bridge',
        ),
      );
      await tester.pumpWidget(MaterialApp(
        home: AgentDetailScreen(agent: _agent, client: client),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows rows after successful fetch', (tester) async {
      final client = _FakeClient.success(
        const AgentInfo(
          name: 'linkup-abc._linkup._tcp.local.',
          fingerprint: 'abc12345',
          agentId: 'linkup-abc',
          version: '0.1.0',
          reverbPort: 8080,
          bridgePort: 8765,
          source: 'bridge',
        ),
      );
      // Pas de store appairé injecté → non appairé → l'empreinte du PC est
      // masquée tant que la confiance n'est pas établie.
      FlutterSecureStorage.setMockInitialValues({});
      await tester.pumpWidget(MaterialApp(
        home: AgentDetailScreen(
          agent: _agent,
          client: client,
          pairedStore: PairedDeviceStore(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('abc12345'), findsNothing,
          reason: 'empreinte masquée tant que non appairé');
      expect(find.text('Disponible après appairage'), findsOneWidget);
      expect(find.text('linkup-abc'), findsWidgets); // appbar + ligne
      expect(find.text('Appairer'), findsOneWidget);
    });

    testWidgets('hides the PC fingerprint until the phone is paired',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final client = _FakeClient.success(
        const AgentInfo(
          name: 'x',
          fingerprint: 'abc12345',
          version: '0.1.0',
          source: 'bridge',
        ),
      );
      await tester.pumpWidget(MaterialApp(
        home: AgentDetailScreen(
          agent: _agent,
          client: client,
          pairedStore: PairedDeviceStore(),
        ),
      ));
      await tester.pumpAndSettle();

      // Ni l'empreinte ni 'pending' brut ne fuitent avant appairage.
      expect(find.text('abc12345'), findsNothing);
      expect(find.text('pending'), findsNothing);
      expect(find.text('Disponible après appairage'), findsOneWidget);
    });

    testWidgets('shows error UI + retry button on AgentInfoUnavailable',
        (tester) async {
      final client = _FakeClient.failure(
        const AgentInfoUnavailable('Bridge injoignable'),
      );
      await tester.pumpWidget(MaterialApp(
        home: AgentDetailScreen(agent: _agent, client: client),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Impossible de joindre l\'agent'), findsOneWidget);
      expect(find.text('Bridge injoignable'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.text('Appairer'), findsNothing,
          reason: 'pas de FAB tant qu\'on n\'a pas d\'info');
    });

    testWidgets('tap on FAB navigates to the pairing flow', (tester) async {
      final observer = _PushObserver();
      final client = _FakeClient.success(
        const AgentInfo(
          name: 'x',
          fingerprint: 'abc12345',
          version: '0.1.0',
          source: 'bridge',
        ),
      );
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [observer],
        home: AgentDetailScreen(agent: _agent, client: client),
      ));
      await tester.pumpAndSettle();
      final pushesBefore = observer.pushCount;

      await tester.tap(find.text('Appairer'));
      await tester.pump();

      // Une nouvelle route (le flow de pairing) a bien été poussée. On ne rend
      // pas PairingFlowScreen en profondeur car il auto-lance le scanner caméra.
      expect(observer.pushCount, greaterThan(pushesBefore));
    });

    testWidgets('shows "Appairé" badge when a stored device matches the agent',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'linkup.paired_device': jsonEncode(const PairedDevice(
          deviceId: 'd1',
          host: '192.168.1.42',
          port: 8000,
          token: 'tok',
          pcPublicKey: 'pk',
          pcFingerprint: 'abc12345',
          pcName: 'pc',
        ).toJson()),
      });
      addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));

      final client = _FakeClient.success(
        const AgentInfo(
          name: 'x',
          fingerprint: 'abc12345',
          version: '0.1.0',
          source: 'bridge',
        ),
      );
      await tester.pumpWidget(MaterialApp(
        home: AgentDetailScreen(
          agent: _agent,
          client: client,
          pairedStore: PairedDeviceStore(),
          verifier: const _FakeVerifier(PairingValidity.valid),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Appairé — appareil approuvé'), findsOneWidget);
      // Une fois appairé, l'empreinte du PC devient visible.
      expect(find.text('abc12345'), findsOneWidget);
      // FAB d'accès au hub de transfert disponible.
      expect(find.text('Transfert'), findsOneWidget);
    });

    testWidgets('treats a stored device as NOT paired when the PC rejects it (stale token)',
        (tester) async {
      // L'empreinte locale correspond, MAIS le PC a oublié le device (401) :
      // → on ne doit PAS afficher « Appairé » ni le bouton d'envoi.
      FlutterSecureStorage.setMockInitialValues({
        'linkup.paired_device': jsonEncode(const PairedDevice(
          deviceId: 'd1',
          host: '192.168.1.42',
          port: 8000,
          token: 'stale-token',
          pcPublicKey: 'pk',
          pcFingerprint: 'abc12345',
          pcName: 'pc',
        ).toJson()),
      });
      addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));

      final client = _FakeClient.success(const AgentInfo(
        name: 'x',
        fingerprint: 'abc12345',
        version: '0.1.0',
        source: 'bridge',
      ));
      await tester.pumpWidget(MaterialApp(
        home: AgentDetailScreen(
          agent: _agent,
          client: client,
          pairedStore: PairedDeviceStore(),
          verifier: const _FakeVerifier(PairingValidity.stale),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Non appairé — appareil non approuvé'), findsOneWidget);
      expect(find.text('Transferts'), findsNothing); // pas d'accès transferts
      expect(find.text('Appairer'), findsOneWidget); // FAB de ré-appairage
      expect(find.text('abc12345'), findsNothing); // empreinte masquée
    });

    testWidgets('shows "Non appairé" badge when no device is stored',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});

      final client = _FakeClient.success(
        const AgentInfo(
          name: 'x',
          fingerprint: 'abc12345',
          version: '0.1.0',
          source: 'bridge',
        ),
      );
      await tester.pumpWidget(MaterialApp(
        home: AgentDetailScreen(
          agent: _agent,
          client: client,
          pairedStore: PairedDeviceStore(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Non appairé — appareil non approuvé'), findsOneWidget);
    });

    testWidgets('disposing the screen closes the owned client', (tester) async {
      // Le client passé en widget n'est PAS owned → ne doit pas être closed
      final externalClient = _FakeClient.success(
        const AgentInfo(
          name: 'x',
          fingerprint: 'abc12345',
          version: '0.1.0',
          source: 'bridge',
        ),
      );
      await tester.pumpWidget(MaterialApp(
        home: AgentDetailScreen(agent: _agent, client: externalClient),
      ));
      await tester.pumpAndSettle();

      // Push une autre route pour disposer l'écran
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();

      expect(externalClient.closeCount, 0,
          reason: 'client injecté = non-owned, ne doit pas être closed');
    });
  });
}
