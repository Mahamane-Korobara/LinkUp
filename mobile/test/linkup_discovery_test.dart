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

    test('scanOnce with empty sweep leaves agents list empty', () async {
      final fakeSweep = _FakeLanSweep(const []);
      final discovery = LinkupDiscovery(lanSweep: fakeSweep);

      await discovery.scanOnce();

      expect(discovery.agents, isEmpty,
          reason: 'aucun agent trouvé = liste vide, pas de crash');
      expect(fakeSweep.sweepCalls, 1,
          reason: 'le sweep a quand même été tenté');

      await discovery.dispose();
    });
  });
}
