import '../../config/linkup_ports.dart';
import 'host_identity.dart';

/// Répond aux sondes de découverte du pair : `/health` et `/api/agent/info`.
///
/// Le format de `/health` reproduit EXACTEMENT celui attendu par
/// `LanSweepDiscovery._probeOnce` (mobile/lib/services/lan_sweep.dart) :
/// l'acceptation se fait sur `service == 'linkup-bridge'`, puis lecture de
/// `laravel_port`, `agent_id`, `version`, `host`, `user`.
///
/// Différence clé avec le PC : l'hôte n'a qu'**un seul port** (agent + bridge
/// fusionnés). On renvoie donc `laravel_port = listenPort` pour que le pair
/// construise ses appels `/api/*` sur ce même port.
class HostAdvertise {
  final HostIdentity identity;

  /// Port unique réellement ouvert par l'hôte (= `bridge_port` ET `laravel_port`).
  final int listenPort;

  HostAdvertise({
    required this.identity,
    this.listenPort = LinkupPorts.bridge,
  });

  Future<Map<String, dynamic>> health() async {
    final name = identity.name();
    return {
      'status': 'alive',
      'service': 'linkup-bridge',
      'agent_id': await identity.agentId(),
      'version': HostIdentity.version,
      // Port unique de l'hôte : le pair bâtit /api/agent/info ET /api/* dessus.
      'laravel_port': listenPort,
      'host': name,
      'user': name,
      'os': 'Android',
      'source': 'host',
    };
  }

  Future<Map<String, dynamic>> agentInfo() async {
    return {
      'name': identity.name(),
      'fingerprint': await identity.fingerprint(),
      'agent_id': await identity.agentId(),
      'version': HostIdentity.version,
      'reverb_port': null,
      'bridge_port': listenPort,
      'source': 'host',
    };
  }
}
