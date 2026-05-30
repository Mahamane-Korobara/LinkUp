import 'dart:async';

import 'package:flutter/material.dart';

import '../models/linkup_agent.dart';
import '../services/agent_discovery.dart';
import '../services/linkup_discovery.dart';
import 'agent_picker/empty_state.dart';
import 'agent_picker/manual_agent_dialog.dart';

/// Écran principal du flow d'appairage : liste les agents découverts sur le LAN
/// via mDNS (T1.15) avec un bouton de saisie manuelle d'IP en fallback (T1.17).
class AgentPickerScreen extends StatefulWidget {
  final AgentDiscovery? discovery;
  final ValueChanged<LinkupAgent>? onAgentSelected;

  const AgentPickerScreen({
    super.key,
    this.discovery,
    this.onAgentSelected,
  });

  @override
  State<AgentPickerScreen> createState() => _AgentPickerScreenState();
}

class _AgentPickerScreenState extends State<AgentPickerScreen> {
  /// Nombre de relances automatiques au démarrage tant qu'aucun agent n'est
  /// trouvé. 4 × 2s = ~8s, valeur empirique qui couvre les démarrages Android
  /// où la pile Wi-Fi met quelques secondes à être prête après l'ouverture.
  static const int _autoScanMaxAttempts = 4;
  static const Duration _autoScanInterval = Duration(seconds: 2);

  late final AgentDiscovery _discovery;
  late final bool _ownsDiscovery;
  StreamSubscription<List<LinkupAgent>>? _subscription;
  Timer? _autoScanTimer;

  List<LinkupAgent> _agents = const [];
  bool _scanning = false;
  bool _autoScanRunning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownsDiscovery = widget.discovery == null;
    _discovery = widget.discovery ?? LinkupDiscovery();
    _subscription = _discovery.stream.listen((agents) {
      if (!mounted) return;
      setState(() => _agents = agents);
    });
    _agents = _discovery.agents;
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoScan());
  }

  @override
  void dispose() {
    _autoScanTimer?.cancel();
    _autoScanTimer = null;
    _subscription?.cancel();
    if (_ownsDiscovery) {
      _discovery.dispose();
    }
    super.dispose();
  }

  /// Boucle de découverte au démarrage : tente jusqu'à 4 scans espacés de 2s
  /// tant qu'aucun agent n'a été trouvé. Couvre les cas où la pile Wi-Fi du
  /// tel n'est pas encore prête au premier frame.
  Future<void> _startAutoScan() async {
    if (_autoScanRunning) return;
    _autoScanRunning = true;
    try {
      for (int attempt = 0; attempt < _autoScanMaxAttempts; attempt++) {
        if (!mounted) return;
        await _runScan();
        if (_agents.isNotEmpty || !mounted) break;
        if (attempt < _autoScanMaxAttempts - 1) {
          await _waitBeforeRetry();
          if (!mounted) return;
        }
      }
    } finally {
      if (mounted) {
        setState(() => _autoScanRunning = false);
      } else {
        _autoScanRunning = false;
      }
    }
  }

  Future<void> _waitBeforeRetry() {
    final completer = Completer<void>();
    _autoScanTimer = Timer(_autoScanInterval, () {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  Future<void> _runScan() async {
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      await _discovery.scanOnce();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Erreur de scan : $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _addManual() async {
    final result = await showDialog<ManualAgentInput>(
      context: context,
      builder: (context) => const ManualAgentDialog(),
    );
    if (result == null || !mounted) return;
    try {
      final agent = _discovery.addManualAgent(
        address: result.address,
        bridgePort: result.bridgePort,
      );
      _notifySelection(agent);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saisie invalide : $e')),
      );
    }
  }

  void _notifySelection(LinkupAgent agent) {
    widget.onAgentSelected?.call(agent);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sélectionner un agent Linkup'),
        actions: [
          IconButton(
            tooltip: 'Rescanner le LAN',
            onPressed: _scanning ? null : _runScan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_scanning) const LinearProgressIndicator(),
          // L'erreur est masquée dès qu'au moins un agent est visible : on
          // veut pas garder un bandeau rouge si la liste répond enfin.
          if (_error != null && _agents.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(child: _buildAgentList()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addManual,
        icon: const Icon(Icons.edit),
        label: const Text('Saisie manuelle'),
      ),
    );
  }

  Widget _buildAgentList() {
    if (_agents.isEmpty) {
      return EmptyState(
        scanning: _scanning || _autoScanRunning,
        onRetry: _runScan,
      );
    }
    return ListView.separated(
      itemCount: _agents.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final agent = _agents[index];
        final isAuto = agent.source == LinkupAgentSource.mdns ||
            agent.source == LinkupAgentSource.lanSweep;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: isAuto
                ? Colors.deepPurple.shade100
                : Colors.orange.shade100,
            child: Icon(
              isAuto ? Icons.computer : Icons.edit_location_alt,
              color: isAuto ? Colors.deepPurple : Colors.orange,
            ),
          ),
          title: Text(
            agent.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(agent.subtitleLine),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _notifySelection(agent),
        );
      },
    );
  }
}
