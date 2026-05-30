import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/models/linkup_agent.dart';
import 'package:linkup_mobile/services/agent_info_client.dart';

LinkupAgent _agent() => const LinkupAgent(
      instanceName: 'linkup-abc._linkup._tcp.local.',
      address: '192.168.1.42',
      reverbPort: 8080,
      bridgePort: 8765,
      agentId: 'linkup-abc',
      source: LinkupAgentSource.mdns,
    );

void main() {
  group('AgentInfoClient', () {
    test('parses a 200 JSON response', () async {
      final mock = MockClient((req) async {
        expect(req.url.toString(), 'http://192.168.1.42:8000/api/agent/info');
        return http.Response(
          '{"name":"linkup-abc._linkup._tcp.local.","fingerprint":"abc12345",'
          '"agent_id":"linkup-abc","version":"0.1.0","reverb_port":8080,'
          '"bridge_port":8765,"source":"bridge"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = AgentInfoClient(client: mock);
      final info = await client.fetch(_agent());

      expect(info.agentId, 'linkup-abc');
      expect(info.fingerprint, 'abc12345');
      expect(info.version, '0.1.0');
      expect(info.bridgePort, 8765);
    });

    test('throws AgentInfoUnavailable on 503', () async {
      final mock = MockClient((req) async {
        return http.Response('{"error":"bridge down"}', 503);
      });

      final client = AgentInfoClient(client: mock);
      expect(
        () => client.fetch(_agent()),
        throwsA(
          isA<AgentInfoUnavailable>().having(
            (e) => e.message,
            'message',
            contains('503'),
          ),
        ),
      );
    });

    test('throws on non-JSON response', () async {
      final mock = MockClient((req) async {
        return http.Response('<html>nope</html>', 200);
      });

      final client = AgentInfoClient(client: mock);
      expect(
        () => client.fetch(_agent()),
        throwsA(isA<AgentInfoUnavailable>()),
      );
    });

    test('uses custom laravelPort', () async {
      bool called = false;
      final mock = MockClient((req) async {
        called = true;
        expect(req.url.port, 9000);
        return http.Response('{"name":"x"}', 200);
      });

      final client = AgentInfoClient(client: mock, laravelPort: 9000);
      await client.fetch(_agent());
      expect(called, isTrue);
    });
  });
}
