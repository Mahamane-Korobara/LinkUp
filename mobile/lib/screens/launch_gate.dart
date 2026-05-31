import 'package:flutter/material.dart';

import '../config/linkup_ports.dart';
import '../models/linkup_agent.dart';
import '../services/agent_discovery.dart';
import '../services/agent_info_client.dart';
import '../services/pairing/paired_device_store.dart';
import 'agent_detail_screen.dart';
import 'agent_picker_screen.dart';

/// Point d'entrée de l'app (S2.J5 — reconnexion auto).
///
/// Au lancement on lit le [PairedDeviceStore] :
/// - s'il existe un PC déjà appairé → on ouvre directement son
///   [AgentDetailScreen] (qui vérifie sa présence via `/api/agent/info` et
///   affiche « Appairé »). Le picker reste accessible via le bouton retour.
/// - sinon → on affiche le [AgentPickerScreen] de découverte LAN.
class LaunchGate extends StatefulWidget {
  /// Injectables pour les widget tests (sinon implémentations réelles).
  final PairedDeviceStore? pairedStore;
  final AgentDiscovery? discovery;
  final AgentInfoFetcher? detailClient;

  const LaunchGate({
    super.key,
    this.pairedStore,
    this.discovery,
    this.detailClient,
  });

  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  late final PairedDeviceStore _store;
  bool _decided = false;

  @override
  void initState() {
    super.initState();
    _store = widget.pairedStore ?? PairedDeviceStore();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  /// Construit un [LinkupAgent] minimal à partir du PC appairé persisté.
  ///
  /// Le store ne garde que `host`/`port` (port HTTP Laravel) : on retombe sur
  /// la convention pour le port bridge, suffisant pour `/api/agent/info`.
  static LinkupAgent agentFromPaired(PairedDevice device) => LinkupAgent(
        instanceName: 'paired:${device.host}',
        address: device.host,
        reverbPort: LinkupPorts.reverb,
        bridgePort: LinkupPorts.bridge,
        fingerprint: device.pcFingerprint,
        hostname: device.pcName,
        source: LinkupAgentSource.paired,
      );

  Future<void> _decide() async {
    PairedDevice? paired;
    try {
      paired = await _store.load();
    } catch (_) {
      paired = null; // secure storage indispo (ex. widget test) → picker
    }
    if (!mounted) return;
    setState(() => _decided = true);

    if (paired != null) {
      // On empile le détail PAR-DESSUS le picker : le retour ramène à la
      // découverte LAN pour appairer un autre PC.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AgentDetailScreen(
            agent: agentFromPaired(paired!),
            client: widget.detailClient,
            pairedStore: widget.pairedStore,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_decided) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return AgentPickerScreen(
      discovery: widget.discovery,
      onAgentSelected: (agent) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AgentDetailScreen(
            agent: agent,
            client: widget.detailClient,
            pairedStore: widget.pairedStore,
          ),
        ),
      ),
    );
  }
}
