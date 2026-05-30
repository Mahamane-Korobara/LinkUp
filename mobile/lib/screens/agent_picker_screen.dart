import 'dart:async';

import 'package:flutter/material.dart';

import '../models/linkup_agent.dart';
import '../services/agent_discovery.dart';
import '../services/linkup_discovery.dart';

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
    final result = await showDialog<_ManualAgentInput>(
      context: context,
      builder: (context) => const _ManualAgentDialog(),
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
          if (_error != null)
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
      return _EmptyState(
        scanning: _scanning || _autoScanRunning,
        onRetry: _runScan,
      );
    }
    return ListView.separated(
      itemCount: _agents.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final agent = _agents[index];
        final subtitleParts = <String>[];
        if (agent.hostname != null && agent.hostname != agent.displayName) {
          subtitleParts.add(agent.hostname!);
        }
        subtitleParts.add('${agent.address}:${agent.bridgePort}');
        if (agent.version != null) subtitleParts.add('v${agent.version}');

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: agent.source == LinkupAgentSource.mdns
                ? Colors.deepPurple.shade100
                : Colors.orange.shade100,
            child: Icon(
              agent.source == LinkupAgentSource.mdns
                  ? Icons.computer
                  : Icons.edit_location_alt,
              color: agent.source == LinkupAgentSource.mdns
                  ? Colors.deepPurple
                  : Colors.orange,
            ),
          ),
          title: Text(
            agent.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(subtitleParts.join('  •  ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _notifySelection(agent),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool scanning;
  final VoidCallback onRetry;

  const _EmptyState({required this.scanning, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            scanning
                ? const SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(strokeWidth: 4),
                  )
                : Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              scanning ? 'Recherche en cours…' : 'Aucun agent détecté',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              scanning
                  ? 'On scanne le Wi-Fi pour trouver ton PC.\nCa peut prendre quelques secondes.'
                  : 'Vérifie que ton PC est sur le même Wi-Fi et que Linkup tourne.\n'
                      'Si le multicast est bloqué, utilise « Saisie manuelle ».',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: scanning ? null : onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Rescanner'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualAgentDialog extends StatefulWidget {
  const _ManualAgentDialog();

  @override
  State<_ManualAgentDialog> createState() => _ManualAgentDialogState();
}

class _ManualAgentDialogState extends State<_ManualAgentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _portController = TextEditingController(text: '8765');

  @override
  void dispose() {
    _addressController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Saisie manuelle'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'IP locale du PC',
                hintText: '192.168.1.42',
              ),
              keyboardType: TextInputType.url,
              autofocus: true,
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'Adresse requise';
                if (!RegExp(r'^[\w.\-:]+$').hasMatch(v)) {
                  return 'Caractères invalides';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Port du bridge',
                hintText: '8765',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                final n = int.tryParse(value?.trim() ?? '');
                if (n == null || n <= 0 || n > 65535) {
                  return 'Port entre 1 et 65535';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(
                _ManualAgentInput(
                  address: _addressController.text.trim(),
                  bridgePort: int.parse(_portController.text.trim()),
                ),
              );
            }
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

class _ManualAgentInput {
  final String address;
  final int bridgePort;

  _ManualAgentInput({required this.address, required this.bridgePort});
}
