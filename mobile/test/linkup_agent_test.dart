import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/models/linkup_agent.dart';

void main() {
  group('LinkupAgent', () {
    test('uniqueKey prefers agentId when available', () {
      const agent = LinkupAgent(
        instanceName: 'linkup-abc._linkup._tcp.local.',
        address: '192.168.1.10',
        reverbPort: 8080,
        bridgePort: 8765,
        agentId: 'linkup-abc',
        source: LinkupAgentSource.mdns,
      );
      expect(agent.uniqueKey, 'linkup-abc');
    });

    test('uniqueKey falls back to address:port when agentId is null', () {
      const agent = LinkupAgent(
        instanceName: 'sweep:10.0.0.5:8765',
        address: '10.0.0.5',
        reverbPort: 8080,
        bridgePort: 8765,
        source: LinkupAgentSource.lanSweep,
      );
      expect(agent.uniqueKey, '10.0.0.5:8765');
    });

    test('bridgeHealthUri points to the bridge port', () {
      const agent = LinkupAgent(
        instanceName: 'x',
        address: '127.0.0.1',
        reverbPort: 8080,
        bridgePort: 8765,
        source: LinkupAgentSource.mdns,
      );
      expect(agent.bridgeHealthUri.toString(), 'http://127.0.0.1:8765/health');
    });

    test('agentInfoUri targets Laravel /api/agent/info on configured port', () {
      const agent = LinkupAgent(
        instanceName: 'x',
        address: '192.168.1.7',
        reverbPort: 8080,
        bridgePort: 8765,
        source: LinkupAgentSource.mdns,
      );
      // Sans override → port par défaut (LinkupPorts.laravel).
      expect(
        agent.agentInfoUri().toString(),
        'http://192.168.1.7:8000/api/agent/info',
      );
      // Override positionnel.
      expect(
        agent.agentInfoUri(9000).toString(),
        'http://192.168.1.7:9000/api/agent/info',
      );
    });

    test('two agents with the same uniqueKey are equal', () {
      const a = LinkupAgent(
        instanceName: 'a',
        address: '192.168.1.10',
        reverbPort: 8080,
        bridgePort: 8765,
        agentId: 'linkup-abc',
        source: LinkupAgentSource.mdns,
      );
      const b = LinkupAgent(
        instanceName: 'b',
        address: '10.0.0.5',
        reverbPort: 9090,
        bridgePort: 9999,
        agentId: 'linkup-abc',
        source: LinkupAgentSource.lanSweep,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
