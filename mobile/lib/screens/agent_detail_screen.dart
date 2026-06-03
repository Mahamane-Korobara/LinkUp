import 'package:flutter/material.dart';

import '../config/linkup_ports.dart';
import '../models/linkup_agent.dart';
import '../services/agent_info_client.dart';
import '../services/pairing/paired_device_store.dart';
import '../services/pairing/pairing_verifier.dart';
import '../theme/app_colors.dart';
import 'clipboard/clipboard_screen.dart';
import 'pairing/pairing_flow_screen.dart';
import 'transfer/transfer_hub_screen.dart';

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

  /// Vérifie côté serveur que l'appairage tient encore. Injectable (tests).
  final PairingVerifier? verifier;

  const AgentDetailScreen({
    super.key,
    required this.agent,
    this.client,
    this.pairedStore,
    this.verifier,
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

  late final PairingVerifier _verifier;
  late final bool _ownsVerifier;

  /// Validité de l'appairage confirmée par le PC (null = pas encore vérifié).
  PairingValidity? _pairingValid;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? AgentInfoClient();
    _ownsVerifier = widget.verifier == null;
    _verifier = widget.verifier ?? HttpPairingVerifier();
    _load();
    _loadPaired();
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    final verifier = _verifier;
    if (_ownsVerifier && verifier is HttpPairingVerifier) {
      verifier.close();
    }
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
    PairedDevice? paired;
    try {
      final store = widget.pairedStore ?? PairedDeviceStore();
      paired = await store.load();
    } catch (_) {
      paired = null; // secure storage indispo (ex. widget test)
    }
    if (!mounted) return;
    setState(() {
      _paired = paired;
      _pairedChecked = true;
      _pairingValid = null;
    });
    if (paired == null) return;

    // Vérifie auprès du PC que l'appairage tient encore (token valide). Si le PC
    // a oublié ce tél (migrate:fresh / révocation), on bascule en « non appairé »
    // → le FAB redevient « Appairer ».
    final validity = await _verifier.verify(paired);
    if (!mounted) return;
    setState(() => _pairingValid = validity);
  }

  /// Statut d'appairage de CE téléphone avec l'agent affiché.
  ///
  /// `null` = vérification en cours ; `true` = un PC appairé est stocké et son
  /// empreinte correspond à celle renvoyée par l'agent ; `false` sinon.
  bool? get _isPaired {
    if (!_pairedChecked) return null;
    final paired = _paired;
    if (paired == null) return false;

    // Le serveur fait autorité dès qu'il a répondu.
    if (_pairingValid == PairingValidity.stale) return false; // PC a oublié le tél
    if (_pairingValid == PairingValidity.valid) return true;
    if (_pairingValid == null) return null; // vérification en cours

    // unknown (PC injoignable pour /api/me) → repli sur l'empreinte locale.
    final info = _info;
    if (info != null && info.fingerprint != 'pending') {
      return paired.pcFingerprint == info.fingerprint;
    }
    return paired.host == widget.agent.address;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.agent.displayName),
        actions: [
          // Presse-papier partagé : seulement quand l'appairage est confirmé
          // (l'écran appelle l'API authentifiée par le token device).
          if (_isPaired == true && _paired != null)
            IconButton(
              tooltip: 'Presse-papier',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ClipboardScreen(device: _paired!),
                ),
              ),
              icon: const Icon(Icons.content_paste),
            ),
          // Toujours dispo (même « appairé ») : si le PC a oublié ce tél (ex.
          // migrate:fresh, révocation), le token local est invalide et il faut
          // re-scanner un QR pour repartir avec un device + token frais.
          if (_info != null)
            IconButton(
              tooltip: 'Ré-appairer',
              onPressed: () => _openPairingFlow(context),
              icon: const Icon(Icons.qr_code),
            ),
          IconButton(
            tooltip: 'Recharger',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _buildFab(context),
    );
  }

  /// Appairé → hub de transfert (galerie/fichier/reçus) ; sinon → appairage.
  Widget? _buildFab(BuildContext context) {
    if (_info == null) return null;
    if (_isPaired == true && _paired != null) {
      return FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TransferHubScreen(device: _paired!),
          ),
        ),
        icon: const Icon(Icons.swap_vert),
        label: const Text('Transfert'),
      );
    }
    return FloatingActionButton.extended(
      onPressed: () => _openPairingFlow(context),
      icon: const Icon(Icons.qr_code_scanner),
      label: const Text('Appairer'),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.dangerSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off_rounded,
                  size: 44, color: AppColors.danger),
            ),
            const SizedBox(height: 24),
            const Text(
              'Impossible de joindre l\'agent',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              // La requête /api/agent/info part sur le port Laravel, pas le bridge.
              'Cible : ${widget.agent.address}:${LinkupPorts.laravel}',
              style: const TextStyle(
                  color: AppColors.faint, fontSize: 13, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(AgentInfo info) {
    final isPending = info.fingerprint == 'pending';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
      children: [
        _HeroCard(
          name: widget.agent.displayName,
          address: widget.agent.address,
          paired: _isPaired,
        ),
        const SizedBox(height: 14),
        _FingerprintRow(
          fingerprint: info.fingerprint,
          isPending: isPending,
          paired: _isPaired,
        ),
        const SizedBox(height: 14),
        _TechnicalDetails(info: info, agent: widget.agent),
      ],
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

/// Hero de l'écran : nom du PC, adresse, et statut d'appairage de CE téléphone.
/// `paired == null` → vérification en cours. Les libellés de statut sont
/// stables (couverts par les widget tests).
class _HeroCard extends StatelessWidget {
  final String name;
  final String address;
  final bool? paired;

  const _HeroCard({
    required this.name,
    required this.address,
    required this.paired,
  });

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color dot, String label) = switch (paired) {
      null => (Icons.hourglass_empty_rounded, AppColors.faint,
          'Vérification de l\'appairage…'),
      true => (Icons.verified_user_rounded, const Color(0xFF34D399),
          'Appairé — appareil approuvé'),
      false => (Icons.gpp_maybe_rounded, const Color(0xFFFBBF24),
          'Non appairé — appareil non approuvé'),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandDark, Color(0xFF4C1D95)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.30),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.desktop_windows_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(icon, color: dot, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte dédiée à l'empreinte Ed25519 du PC.
///
/// Tant que ce téléphone n'est pas appairé/approuvé ([paired] != true), on
/// n'expose PAS l'empreinte : elle n'a de sens qu'une fois la confiance établie.
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.fingerprint_rounded,
                  color: AppColors.brand, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Empreinte du PC',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontFamily: mono ? 'monospace' : null,
                      fontWeight: FontWeight.w700,
                      letterSpacing: mono ? 1.5 : null,
                      color: isApproved ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (isApproved && !isPending)
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Détails techniques de l'agent, repliés par défaut (n'encombre pas l'écran
/// principal mais reste accessible).
class _TechnicalDetails extends StatelessWidget {
  final AgentInfo info;
  final LinkupAgent agent;

  const _TechnicalDetails({required this.info, required this.agent});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.tune_rounded, color: AppColors.muted),
          title: const Text(
            'Détails techniques',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 4),
          children: [
            _Row('Nom mDNS', info.name),
            _Row('Agent ID', info.agentId ?? '—'),
            _Row('Version', info.version),
            _Row('Port Reverb', info.reverbPort?.toString() ?? '—'),
            _Row('Port bridge', info.bridgePort?.toString() ?? '—'),
            _Row('Source', info.source),
            _Row('Adresse', '${agent.address}:${agent.bridgePort}'),
            _Row('Découvert via', agent.source.name),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
