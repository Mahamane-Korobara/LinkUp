import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/host/host_controller.dart';
import '../../services/host/host_device_store.dart';

/// Écran « Mode Hôte » : ce téléphone joue le serveur pour qu'un autre
/// téléphone (sans PC) puisse lui envoyer/recevoir des fichiers.
class HostScreen extends StatefulWidget {
  const HostScreen({super.key});

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  final HostController _c = HostController();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
    // Sonde régulièrement le store tant qu'on héberge (un pair qui scanne
    // apparaît en « en attente »).
    if (_c.isHosting && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _c.refresh());
    } else if (!_c.isHosting && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _c.removeListener(_onChange);
    _c.dispose();
    super.dispose();
  }

  Future<void> _sendTo(HostDevice peer) async {
    final picked = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
    if (picked == null) return;
    var sent = 0;
    for (final f in picked.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      await _c.sendToPeer(deviceId: peer.deviceId, filename: f.name, bytes: bytes);
      sent++;
    }
    if (mounted && sent > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$sent fichier(s) prêt(s) pour ${peer.name}. '
            'Il les récupère depuis « Fichiers reçus » sur son téléphone.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Héberger (sans PC)')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _c.isHosting ? _hosting(context) : _idle(context),
        ),
      ),
    );
  }

  Widget _idle(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Icon(Icons.wifi_tethering_rounded,
            size: 72, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text('Partage de téléphone à téléphone',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Ce téléphone devient le « point de partage ». Un autre téléphone '
          'LinkUp pourra s\'y connecter (en scannant le QR) et échanger des '
          'fichiers, photos et vidéos — sans aucun PC.\n\n'
          'Astuce : active le partage de connexion sur ce téléphone pour que '
          'l\'autre s\'y connecte directement.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (_c.error != null) _errorBanner(_c.error!),
        FilledButton.icon(
          onPressed: _c.isStarting ? null : _c.startHosting,
          icon: _c.isStarting
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.play_arrow_rounded),
          label: Text(_c.isStarting ? 'Démarrage…' : 'Démarrer l\'hébergement'),
        ),
      ],
    );
  }

  Widget _hosting(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_c.error != null) _errorBanner(_c.error!),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text('Scanne ce QR depuis l\'autre téléphone',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                if (_c.pairingUrl != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.white,
                    child: QrImageView(
                      data: _c.pairingUrl!,
                      version: QrVersions.auto,
                      size: 230,
                    ),
                  ),
                const SizedBox(height: 12),
                Text('${_c.ip}:${_c.port}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _section('En attente d\'approbation', Icons.hourglass_top_rounded),
        if (_c.pending.isEmpty)
          const _Hint('Personne pour l\'instant. Quand un téléphone scanne le QR, '
              'il apparaît ici pour que tu l\'approuves.')
        else
          ..._c.pending.map(_pendingTile),
        const SizedBox(height: 16),
        _section('Téléphones appairés', Icons.devices_rounded),
        if (_c.approved.isEmpty)
          const _Hint('Aucun téléphone appairé pour le moment.')
        else
          ..._c.approved.map(_approvedTile),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _c.stopHosting,
          icon: const Icon(Icons.stop_rounded),
          label: const Text('Arrêter l\'hébergement'),
        ),
      ],
    );
  }

  Widget _pendingTile(HostDevice d) => Card(
        child: ListTile(
          leading: const Icon(Icons.smartphone_rounded),
          title: Text(d.name),
          subtitle: Text('${d.platform} ${d.osVersion}'.trim()),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Refuser',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => _c.reject(d.deviceId),
              ),
              FilledButton(
                onPressed: () => _c.approve(d.deviceId),
                child: const Text('Approuver'),
              ),
            ],
          ),
        ),
      );

  Widget _approvedTile(HostDevice d) => Card(
        child: ListTile(
          leading: const Icon(Icons.smartphone_rounded),
          title: Text(d.name),
          subtitle: Text('${d.platform} ${d.osVersion}'.trim()),
          trailing: FilledButton.tonalIcon(
            onPressed: () => _sendTo(d),
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Envoyer'),
          ),
        ),
      );

  Widget _section(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _errorBanner(String message) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      );
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}
