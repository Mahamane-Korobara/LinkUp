import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/models/linkup_agent.dart';

void main() {
  group('LinkupAgent', () {
    test('uniqueKey prefers agentId when available', () {
      const agent = LinkupAgent(
        instanceName: 'linkup-abc._linkup._tcp.local.',
        host: 'h.local.',
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
        instanceName: 'manual:10.0.0.5:8765',
        host: '10.0.0.5',
        address: '10.0.0.5',
        reverbPort: 8080,
        bridgePort: 8765,
        source: LinkupAgentSource.manual,
      );
      expect(agent.uniqueKey, '10.0.0.5:8765');
    });

    test('bridgeHealthUri points to the bridge port', () {
      const agent = LinkupAgent(
        instanceName: 'x',
        host: 'h',
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
        host: 'h',
        address: '192.168.1.7',
        reverbPort: 8080,
        bridgePort: 8765,
        source: LinkupAgentSource.mdns,
      );
      expect(
        agent.agentInfoUri().toString(),
        'http://192.168.1.7:8000/api/agent/info',
      );
      expect(
        agent.agentInfoUri(laravelPort: 9000).toString(),
        'http://192.168.1.7:9000/api/agent/info',
      );
    });

    test('two agents with the same uniqueKey are equal', () {
      const a = LinkupAgent(
        instanceName: 'a',
        host: 'h',
        address: '192.168.1.10',
        reverbPort: 8080,
        bridgePort: 8765,
        agentId: 'linkup-abc',
        source: LinkupAgentSource.mdns,
      );
      const b = LinkupAgent(
        instanceName: 'b',
        host: 'other',
        address: '10.0.0.5',
        reverbPort: 9090,
        bridgePort: 9999,
        agentId: 'linkup-abc',
        source: LinkupAgentSource.manual,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
