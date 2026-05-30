import 'package:flutter/material.dart';

import '../models/linkup_agent.dart';
import '../services/agent_info_client.dart';

/// Écran T1.19 : affiche les infos riches d'un agent sélectionné en appelant
/// `/api/agent/info` côté Laravel du PC distant.
///
/// Sert de préparation visuelle pour S2 (pairing) : c'est sur cet écran que
/// viendra le bouton « Lancer le pairing » qui scannera le QR.
class AgentDetailScreen extends StatefulWidget {
  final LinkupAgent agent;
  final AgentInfoFetcher? client;

  const AgentDetailScreen({
    super.key,
    required this.agent,
    this.client,
  });

  @override
  State<AgentDetailScreen> createState() => _AgentDetailScreenState();
}

class _AgentDetailScreenState extends State<AgentDetailScreen> {
  late final AgentInfoFetcher _client;
  late final bool _ownsClient;
  AgentInfo? _info;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? AgentInfoClient();
    _load();
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await _client.fetch(widget.agent);
      if (!mounted) return;
      setState(() => _info = info);
    } on AgentInfoUnavailable catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.agent.displayName),
        actions: [
          IconButton(
            tooltip: 'Recharger',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _info == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showPairingPlaceholder(context),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Appairer'),
            ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildError();
    }
    if (_info == null) {
      return const SizedBox.shrink();
    }
    return _buildInfo(_info!);
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          const Text(
            'Impossible de joindre l\'agent',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(
            'Cible : ${widget.agent.address}:${widget.agent.bridgePort}',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(AgentInfo info) {
    final isPending = info.fingerprint == 'pending';
    final rows = [
      _Row('Nom mDNS', info.name),
      _Row('Agent ID', info.agentId ?? '—'),
      _Row(
        'Empreinte',
        isPending ? 'Pas encore générée (pairing S2)' : info.fingerprint,
        mono: !isPending,
      ),
      _Row('Version', info.version),
      _Row('Port Reverb', info.reverbPort?.toString() ?? '—'),
      _Row('Port bridge', info.bridgePort?.toString() ?? '—'),
      _Row('Source', info.source),
      _Row('Adresse', '${widget.agent.address}:${widget.agent.bridgePort}'),
      _Row('Découvert via', widget.agent.source.name),
    ];

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => rows[i],
    );
  }

  void _showPairingPlaceholder(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pairing arrivera en S2. Pour l\'instant, agent visible.'),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _Row(this.label, this.value, {this.mono = false});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        label,
        style: const TextStyle(fontSize: 13, color: Colors.grey),
      ),
      subtitle: Text(
        value,
        style: TextStyle(
          fontSize: 16,
          fontFamily: mono ? 'monospace' : null,
          fontWeight: FontWeight.w500,
        ),
      ),
      dense: true,
    );
  }
}
