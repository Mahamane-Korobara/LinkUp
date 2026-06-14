import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/apps/installed_apps.dart';
import '../../theme/app_colors.dart';
import '../host/app_picker_screen.dart';

/// Callback d'envoi d'un fichier (APK) : abstrait le transport pour réutiliser
/// cet écran des DEUX côtés du tél↔tél —
///   - côté client (B) : upload via TransferClient vers le serveur de A ;
///   - côté hôte (A)   : push via HostController.sendToPeer vers B.
typedef SendBytes = Future<void> Function(
  String filename,
  List<int> bytes,
  void Function(double progress)? onProgress,
);

/// Envoi d'applications installées (façon Xender) vers l'autre téléphone.
/// Choisit des apps (AppPickerScreen) puis envoie leurs .apk via [send].
class AppSendScreen extends StatefulWidget {
  final String targetName;
  final SendBytes send;

  const AppSendScreen({super.key, required this.targetName, required this.send});

  @override
  State<AppSendScreen> createState() => _AppSendScreenState();
}

class _AppSendScreenState extends State<AppSendScreen> {
  bool _busy = false;
  String? _current; // app en cours d'envoi
  double _progress = 0;
  int _done = 0;
  int _failed = 0;
  int _total = 0;

  Future<void> _pickAndSend() async {
    final apps = await Navigator.of(context).push<List<InstalledApp>>(
      MaterialPageRoute(builder: (_) => const AppPickerScreen()),
    );
    if (apps == null || apps.isEmpty || !mounted) return;

    setState(() {
      _busy = true;
      _total = apps.length;
      _done = 0;
      _failed = 0;
    });

    for (final app in apps) {
      if (!mounted) return;
      setState(() {
        _current = app.name;
        _progress = 0;
      });
      try {
        final bytes = await File(app.apkPath).readAsBytes();
        await widget.send(app.suggestedFilename, bytes, (p) {
          if (mounted) setState(() => _progress = p);
        });
        _done++;
      } catch (_) {
        _failed++;
      }
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _current = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_failed == 0
          ? '$_done application(s) envoyée(s) à ${widget.targetName}.'
          : '$_done envoyée(s), $_failed échec(s).'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Envoyer des applications')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Icon(Icons.apps_rounded, size: 56, color: AppColors.brand),
              const SizedBox(height: 16),
              Text(
                'Envoie une application installée vers ${widget.targetName}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'L\'app est transférée sous forme de fichier .apk. Le destinataire '
                'la récupère dans « Reçus » puis l\'installe.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: 28),
              if (_busy) ...[
                Text(
                  'Envoi ${_done + 1}/$_total — ${_current ?? ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.body),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress > 0 && _progress < 1 ? _progress : null,
                    minHeight: 8,
                    backgroundColor: AppColors.brandSoft,
                    color: AppColors.brand,
                  ),
                ),
              ] else
                FilledButton.icon(
                  onPressed: _pickAndSend,
                  icon: const Icon(Icons.checklist_rounded),
                  label: const Text('Choisir des applications'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
