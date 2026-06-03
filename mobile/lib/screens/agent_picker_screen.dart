import 'dart:async';

import 'package:flutter/material.dart';

import '../models/linkup_agent.dart';
import '../services/agent_discovery.dart';
import '../services/linkup_discovery.dart';
import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';
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
        titleSpacing: 16,
        title: const AppLogo(size: 30, showWordmark: true),
        actions: [
          IconButton(
            tooltip: 'Rescanner le LAN',
            onPressed: _scanning ? null : _runScan,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_scanning) const LinearProgressIndicator(minHeight: 2),
          // L'erreur est masquée dès qu'au moins un agent est visible : on
          // veut pas garder un bandeau rouge si la liste répond enfin.
          if (_error != null && _agents.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _ErrorBanner(message: _error!),
            ),
          Expanded(child: _buildAgentList()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addManual,
        icon: const Icon(Icons.keyboard_rounded),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      children: [
        Row(
          children: [
            const Text(
              'PC trouvés sur ton Wi-Fi',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppColors.faint,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: AppColors.line)),
          ],
        ),
        const SizedBox(height: 12),
        for (final agent in _agents) ...[
          _AgentCard(agent: agent, onTap: () => _notifySelection(agent)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Carte d'un PC découvert : icône colorée selon la source, nom + adresse,
/// chevron. Tap → sélection (conserve le comportement d'origine).
class _AgentCard extends StatelessWidget {
  final LinkupAgent agent;
  final VoidCallback onTap;

  const _AgentCard({required this.agent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isAuto = agent.source == LinkupAgentSource.mdns ||
        agent.source == LinkupAgentSource.lanSweep;
    final iconBg = isAuto ? AppColors.brandSoft : AppColors.warnSoft;
    final iconFg = isAuto ? AppColors.brand : AppColors.warn;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isAuto
                      ? Icons.desktop_windows_rounded
                      : Icons.edit_location_alt_rounded,
                  color: iconFg,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      agent.subtitleLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bandeau d'erreur discret (scan en échec) — au lieu d'un texte rouge brut.
class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
