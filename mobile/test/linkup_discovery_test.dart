import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/models/linkup_agent.dart';
import 'package:linkup_mobile/services/lan_sweep.dart';
import 'package:linkup_mobile/services/linkup_discovery.dart';

/// Lan sweep fake : injectable dans LinkupDiscovery pour piloter ce que sweep
/// remonte sans toucher au réseau réel.
class _FakeLanSweep extends LanSweepDiscovery {
  final List<LinkupAgent> toEmit;
  int sweepCalls = 0;

  _FakeLanSweep(this.toEmit);

  @override
  Future<List<LinkupAgent>> sweep({
    void Function(LinkupAgent agent)? onAgentFound,
    bool Function()? isCancelled,
  }) async {
    sweepCalls++;
    for (final agent in toEmit) {
      if (isCancelled?.call() == true) return [];
      onAgentFound?.call(agent);
    }
    return toEmit;
  }
}

void main() {
  // Indispensable : sans ça, MulticastLock.release() (Platform channel) plante
  // au dispose() du LinkupDiscovery dans un environnement de test pur Dart.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LinkupDiscovery merge sweep/mDNS', () {
    test('cancelled flag stops the sweep early', () async {
      final discovery = LinkupDiscovery(
        lanSweep: _FakeLanSweep(const [
          LinkupAgent(
            instanceName: 'a',
            address: '1.2.3.4',
            reverbPort: 8080,
            bridgePort: 8765,
            agentId: 'linkup-a',
            user: 'mahamane',
            source: LinkupAgentSource.mdns,
          ),
        ]),
      );

      // dispose avant scan → cancelled=true → aucun agent ne doit être emis
      await discovery.dispose();

      // Le stream a été fermé proprement, pas d'erreur attendue.
      expect(discovery.agents, isEmpty);
    });

    test('addManualAgent merges with existing sweep agent (preserves user)',
        () async {
      // Le sweep a déjà trouvé l'agent avec user=mahamane et hostname riches
      final sweepAgent = LinkupAgent(
        instanceName: 'linkup-abc._linkup._tcp.local.',
        address: '192.168.1.10',
        reverbPort: 8080,
        bridgePort: 8765,
        agentId: 'linkup-abc',
        user: 'mahamane',
        hostname: 'mahamane-VivoBook',
        version: '0.1.0',
        source: LinkupAgentSource.lanSweep,
      );
      final discovery = LinkupDiscovery(lanSweep: _FakeLanSweep([sweepAgent]));
      await discovery.scanOnce();

      // Une saisie manuelle sur la même IP/port ne doit PAS écraser les champs
      // riches venus du sweep.
      discovery.addManualAgent(
        address: '192.168.1.10',
        bridgePort: 8765,
      );

      // L'agent existe encore avec ses champs user/hostname
      final merged = discovery.agents.firstWhere(
        (a) => a.address == '192.168.1.10',
      );
      expect(merged.user, 'mahamane',
          reason: 'le user du sweep doit être préservé après saisie manuelle');
      expect(merged.hostname, 'mahamane-VivoBook',
          reason: 'le hostname du sweep doit être préservé');
      expect(merged.version, '0.1.0',
          reason: 'la version du sweep doit être préservée');

      await discovery.dispose();
    });

    test('addManualAgent creates new entry when nothing exists', () async {
      final discovery = LinkupDiscovery(lanSweep: _FakeLanSweep(const []));

      final added = discovery.addManualAgent(
        address: '10.0.0.5',
        bridgePort: 8765,
      );

      expect(added.source, LinkupAgentSource.manual);
      expect(added.user, isNull);
      expect(discovery.agents, hasLength(1));

      await discovery.dispose();
    });

    test('addManualAgent rejects empty address', () async {
      final discovery = LinkupDiscovery(lanSweep: _FakeLanSweep(const []));
      expect(
        () => discovery.addManualAgent(address: '  '),
        throwsArgumentError,
      );
      await discovery.dispose();
    });

    test('addManualAgent rejects invalid port', () async {
      final discovery = LinkupDiscovery(lanSweep: _FakeLanSweep(const []));
      expect(
        () => discovery.addManualAgent(address: '1.2.3.4', bridgePort: 0),
        throwsArgumentError,
      );
      expect(
        () => discovery.addManualAgent(address: '1.2.3.4', bridgePort: 99999),
        throwsArgumentError,
      );
      await discovery.dispose();
    });
  });
}
