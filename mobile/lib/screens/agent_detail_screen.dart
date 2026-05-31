import 'package:flutter/material.dart';

import '../config/linkup_ports.dart';
import '../models/linkup_agent.dart';
import '../services/agent_info_client.dart';
import '../services/pairing/paired_device_store.dart';
import 'pairing/pairing_flow_screen.dart';

/// Écran T1.19 : affiche les infos riches d'un agent sélectionné en appelant
/// `/api/agent/info` côté Laravel du PC distant.
///
/// Sert de préparation visuelle pour S2 (pairing) : c'est sur cet écran que
/// viendra le bouton « Lancer le pairing » qui scannera le QR.
class AgentDetailScreen extends StatefulWidget {
  final LinkupAgent agent;
  final AgentInfoFetcher? client;

  /// Store du PC appairé, injectable pour les widget tests. En prod on lit le
  /// secure storage pour savoir si CE téléphone est déjà appairé à ce PC.
  final PairedDeviceStore? pairedStore;

  const AgentDetailScreen({
    super.key,
    required this.agent,
    this.client,
    this.pairedStore,
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

  /// PC appairé persisté localement (null = aucun appairage stocké).
  PairedDevice? _paired;

  /// `false` tant que la lecture du secure storage n'a pas abouti.
  bool _pairedChecked = false;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? AgentInfoClient();
    _load();
    _loadPaired();
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

  /// Lit le PC appairé depuis le secure storage. Toute erreur plateforme (ex.
  /// en widget test sans plugin) est avalée : on retombe sur « non appairé ».
  Future<void> _loadPaired() async {
    try {
      final store = widget.pairedStore ?? PairedDeviceStore();
      final paired = await store.load();
      if (!mounted) return;
      setState(() {
        _paired = paired;
        _pairedChecked = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _pairedChecked = true);
    }
  }

  /// Statut d'appairage de CE téléphone avec l'agent affiché.
  ///
  /// `null` = vérification en cours ; `true` = un PC appairé est stocké et son
  /// empreinte correspond à celle renvoyée par l'agent ; `false` sinon.
  bool? get _isPaired {
    if (!_pairedChecked) return null;
    final info = _info;
    final paired = _paired;
    if (paired == null) return false;
    if (info != null && info.fingerprint != 'pending') {
      return paired.pcFingerprint == info.fingerprint;
    }
    // Pas d'empreinte fraîche à comparer : on s'appuie sur l'adresse du PC.
    return paired.host == widget.agent.address;
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
              onPressed: () => _openPairingFlow(context),
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
            // La requête /api/agent/info part sur le port Laravel, pas le bridge.
            'Cible : ${widget.agent.address}:${LinkupPorts.laravel}',
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
    final rows = <Widget>[
      _PairingBadge(paired: _isPaired),
      _FingerprintRow(
        fingerprint: info.fingerprint,
        isPending: isPending,
        paired: _isPaired,
      ),
      _Row('Nom mDNS', info.name),
      _Row('Agent ID', info.agentId ?? '—'),
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

  Future<void> _openPairingFlow(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PairingFlowScreen()),
    );
    // Au retour du flow, l'appairage a pu aboutir : on recharge le statut pour
    // que le badge passe de « Non appairé » à « Appairé » sans rouvrir l'écran.
    if (!mounted) return;
    await _loadPaired();
  }
}

/// En-tête de statut : ce téléphone est-il appairé (approuvé) avec ce PC ?
/// `paired == null` → vérification en cours.
class _PairingBadge extends StatelessWidget {
  final bool? paired;

  const _PairingBadge({required this.paired});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String label) = switch (paired) {
      null => (Icons.hourglass_empty, Colors.grey, 'Vérification de l\'appairage…'),
      true => (Icons.verified_user, Colors.green, 'Appairé — appareil approuvé'),
      false => (Icons.gpp_maybe, Colors.orange, 'Non appairé — appareil non approuvé'),
    };

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w600, color: color),
      ),
      subtitle: const Text("Statut d'appairage de ce téléphone avec le PC"),
      dense: true,
    );
  }
}

/// Ligne dédiée à l'empreinte Ed25519 du PC.
///
/// Tant que ce téléphone n'est pas appairé/approuvé ([paired] != true), on
/// n'expose PAS l'empreinte : elle n'a de sens qu'une fois la confiance établie.
/// Une fois appairé, on l'affiche avec une pastille verte de confirmation.
class _FingerprintRow extends StatelessWidget {
  final String fingerprint;
  final bool isPending;
  final bool? paired;

  const _FingerprintRow({
    required this.fingerprint,
    required this.isPending,
    required this.paired,
  });

  @override
  Widget build(BuildContext context) {
    final isApproved = paired == true;

    final String value;
    final bool mono;
    if (!isApproved) {
      value = 'Disponible après appairage';
      mono = false;
    } else if (isPending) {
      value = 'Pas encore générée';
      mono = false;
    } else {
      value = fingerprint;
      mono = true;
    }

    return ListTile(
      title: const Text(
        'Empreinte du PC',
        style: TextStyle(fontSize: 13, color: Colors.grey),
      ),
      subtitle: Text(
        value,
        style: TextStyle(
          fontSize: 16,
          fontFamily: mono ? 'monospace' : null,
          fontWeight: FontWeight.w500,
          color: isApproved ? null : Colors.grey,
        ),
      ),
      trailing: (isApproved && !isPending)
          ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
          : null,
      dense: true,
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        label,
        style: const TextStyle(fontSize: 13, color: Colors.grey),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      dense: true,
    );
  }
}
