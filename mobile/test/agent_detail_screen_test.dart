import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/models/linkup_agent.dart';
import 'package:linkup_mobile/screens/agent_detail_screen.dart';
import 'package:linkup_mobile/services/agent_info_client.dart';

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
      await tester.pumpWidget(MaterialApp(
        home: AgentDetailScreen(agent: _agent, client: client),
      ));
      await tester.pumpAndSettle();

      expect(find.text('abc12345'), findsOneWidget);
      expect(find.text('linkup-abc'), findsWidgets); // appbar + ligne
      expect(find.text('Appairer'), findsOneWidget);
    });

    testWidgets('displays placeholder text when fingerprint is "pending"',
        (tester) async {
      final client = _FakeClient.success(
        const AgentInfo(
          name: 'x',
          fingerprint: 'pending',
          version: '0.1.0',
          source: 'bridge',
        ),
      );
      await tester.pumpWidget(MaterialApp(
        home: AgentDetailScreen(agent: _agent, client: client),
      ));
      await tester.pumpAndSettle();

      // Fix P0 audit pass3 : on n'affiche pas 'pending' brut
      expect(find.text('pending'), findsNothing);
      expect(
        find.text('Pas encore générée (pairing S2)'),
        findsOneWidget,
      );
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

    testWidgets('tap on FAB shows S2 placeholder snackbar', (tester) async {
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
      await tester.pumpAndSettle();

      await tester.tap(find.text('Appairer'));
      await tester.pump();

      expect(
        find.textContaining('Pairing arrivera en S2'),
        findsOneWidget,
      );
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
