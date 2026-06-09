import 'dart:async';

import 'package:flutter/material.dart';

import '../models/linkup_agent.dart';
import '../services/agent_discovery.dart';
import '../services/linkup_discovery.dart';
import '../theme/app_colors.dart';
import '../widgets/app_card.dart';
import '../widgets/app_logo.dart';
import '../widgets/section_label.dart';
import 'agent_picker/empty_state.dart';
import 'host/host_screen.dart';

/// Écran principal du flow d'appairage : liste les agents découverts sur le LAN
/// via mDNS + sweep /24 (le sweep couvre les cas où le multicast est bloqué,
/// ex. hotspot). Aucune saisie manuelle : la découverte doit juste marcher.
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

  void _notifySelection(LinkupAgent agent) {
    widget.onAgentSelected?.call(agent);
  }

  void _openHost() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HostScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // AppBar épurée : seulement le wordmark. Les actions (rescanner, héberger)
    // descendent dans le corps — un pull-to-refresh et une carte dédiée, plus
    // lisibles que des icônes muettes en barre.
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const AppLogo(size: 30, showWordmark: true),
      ),
      body: Column(
        children: [
          if (_scanning) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _runScan,
              color: AppColors.brand,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
                children: [
                  // L'erreur est masquée dès qu'au moins un agent est visible :
                  // on garde pas un bandeau rouge si la liste répond enfin.
                  if (_error != null && _agents.isEmpty) ...[
                    _ErrorBanner(message: _error!),
                    const SizedBox(height: 16),
                  ],
                  const SectionLabel('PC sur ton Wi-Fi'),
                  const SizedBox(height: 14),
                  if (_agents.isEmpty)
                    EmptyState(
                      scanning: _scanning || _autoScanRunning,
                      onRetry: _runScan,
                    )
                  else
                    for (final agent in _agents) ...[
                      _AgentCard(
                        agent: agent,
                        onTap: () => _notifySelection(agent),
                      ),
                      const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 28),
                  const SectionLabel('Sans ordinateur'),
                  const SizedBox(height: 14),
                  _HostEntryCard(onTap: _openHost),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte d'entrée du Mode Hôte (tél↔tél) : reçoit/envoie depuis un autre
/// téléphone, sans aucun PC. Accent violet pour la distinguer des PC trouvés.
class _HostEntryCard extends StatelessWidget {
  final VoidCallback onTap;

  const _HostEntryCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.wifi_tethering_rounded,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Héberger sans PC',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Échange avec un autre téléphone, sans ordinateur',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
        ],
      ),
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

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
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
                    letterSpacing: -0.2,
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
