import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/host/host_controller.dart';
import '../../services/host/host_device_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/section_label.dart';
import '../transfer/app_send_screen.dart';

/// Page Transfert côté HÔTE (A) pour un pair approuvé (B) — l'équivalent de la
/// page transfert pc↔tél, mais en mode « médiateur » : A pousse vers B
/// (sendToPeer) et liste ce que B lui a envoyé. Pas de presse-papier ni de dev
/// preview (tél↔tél), avec en plus l'envoi d'« Application ».
class HostPeerTransferScreen extends StatefulWidget {
  final HostController controller;
  final HostDevice peer;

  const HostPeerTransferScreen({
    super.key,
    required this.controller,
    required this.peer,
  });

  @override
  State<HostPeerTransferScreen> createState() => _HostPeerTransferScreenState();
}

class _HostPeerTransferScreenState extends State<HostPeerTransferScreen> {
  bool _busy = false;

  Future<void> _pickAndSend({required bool mediaOnly}) async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: true,
      type: mediaOnly ? FileType.media : FileType.any,
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    var sent = 0;
    for (final f in picked.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      await widget.controller
          .sendToPeer(deviceId: widget.peer.deviceId, filename: f.name, bytes: bytes);
      sent++;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _snack('$sent fichier(s) prêt(s) pour ${widget.peer.name}. '
        'Il les récupère dans « Reçus » sur son téléphone.');
  }

  void _openAppSend() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AppSendScreen(
        targetName: widget.peer.name,
        send: (filename, bytes, onProgress) async {
          await widget.controller.sendToPeer(
              deviceId: widget.peer.deviceId, filename: filename, bytes: bytes);
          onProgress?.call(1);
        },
      ),
    ));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Transfert — ${widget.peer.name}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            if (_busy) ...[
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 16),
            ],
            const SectionLabel('Envoyer'),
            const SizedBox(height: 14),
            _SendCard(
              icon: Icons.photo_library_rounded,
              title: 'Photos & vidéos',
              subtitle: 'Depuis la galerie',
              onTap: _busy ? null : () => _pickAndSend(mediaOnly: true),
            ),
            const SizedBox(height: 12),
            _SendCard(
              icon: Icons.description_rounded,
              title: 'Fichiers',
              subtitle: 'Documents, archives, n\'importe quel fichier',
              onTap: _busy ? null : () => _pickAndSend(mediaOnly: false),
            ),
            const SizedBox(height: 12),
            _SendCard(
              icon: Icons.apps_rounded,
              title: 'Application',
              subtitle: 'Envoyer une app installée (.apk)',
              onTap: _busy ? null : _openAppSend,
            ),
            const SizedBox(height: 28),
            const SectionLabel('Reçus de ce téléphone'),
            const SizedBox(height: 14),
            // Se rafraîchit quand l'hôte sonde ses transferts (toutes les 2 s).
            ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final received = widget.controller.receivedFrom(widget.peer.deviceId);
                if (received.isEmpty) {
                  return const Text(
                    'Rien reçu pour l\'instant. Ce que ce téléphone t\'envoie '
                    'apparaît ici (et est enregistré dans ta galerie / Téléchargements).',
                    style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5),
                  );
                }
                return Column(
                  children: [
                    for (final r in received) ...[
                      _ReceivedTile(item: r),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SendCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SendCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.brand, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        letterSpacing: -0.2)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
        ],
      ),
    );
  }
}

class _ReceivedTile extends StatelessWidget {
  final HostReceived item;
  const _ReceivedTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.move_to_inbox_rounded, color: AppColors.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(_size(item.size),
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
    if (bytes >= 1024) return '${(bytes / 1024).round()} Ko';
    return '$bytes o';
  }
}
