import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:linkup_mobile/models/linkup_agent.dart';
import 'package:linkup_mobile/screens/agent_picker_screen.dart';

import 'fakes/fake_discovery.dart';

void main() {
  testWidgets('Empty state shows scanning hint at startup', (tester) async {
    final discovery = FakeDiscovery();
    await tester.pumpWidget(
      MaterialApp(home: AgentPickerScreen(discovery: discovery)),
    );
    await tester.pump(); // initial frame + post-frame auto-scan déclenché

    // Pendant l'auto-scan, l'empty state affiche « Recherche en cours… ».
    expect(find.text('Recherche en cours…'), findsOneWidget);
  });

  testWidgets('Discovered agents render in the list', (tester) async {
    final discovery = FakeDiscovery();
    discovery.emit([
      const LinkupAgent(
        instanceName: 'linkup-abc._linkup._tcp.local.',
        address: '192.168.1.10',
        reverbPort: 8080,
        bridgePort: 8765,
        agentId: 'linkup-abc',
        fingerprint: 'fp1234abcd',
        version: '0.1.0',
        source: LinkupAgentSource.mdns,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: AgentPickerScreen(discovery: discovery)),
    );
    await tester.pump();

    expect(find.text('linkup-abc'), findsOneWidget);
    expect(find.textContaining('192.168.1.10:8765'), findsOneWidget);
  });

  testWidgets('Tapping an agent calls onAgentSelected', (tester) async {
    final discovery = FakeDiscovery();
    discovery.emit([
      const LinkupAgent(
        instanceName: 'linkup-xyz._linkup._tcp.local.',
        address: '10.0.0.5',
        reverbPort: 8080,
        bridgePort: 8765,
        agentId: 'linkup-xyz',
        source: LinkupAgentSource.mdns,
      ),
    ]);

    LinkupAgent? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: AgentPickerScreen(
          discovery: discovery,
          onAgentSelected: (a) => picked = a,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('linkup-xyz'));
    await tester.pump();

    expect(picked, isNotNull);
    expect(picked!.address, '10.0.0.5');
  });
}
