import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/pairing/paired_device_store.dart';
import '../../services/transfer/transfer_client.dart';

/// Fichier choisi par l'utilisateur (nom + octets).
class PickedFile {
  final String name;
  final List<int> bytes;
  const PickedFile(this.name, this.bytes);
}

/// Signature injectable de sélection de fichier (mockée en widget test).
typedef FilePickFn = Future<PickedFile?> Function();

/// Écran d'envoi d'un fichier du tél vers le PC appairé (S4.J4).
class FileTransferScreen extends StatefulWidget {
  final PairedDevice device;
  final TransferClient? client;
  final FilePickFn? pickFile;

  const FileTransferScreen({
    super.key,
    required this.device,
    this.client,
    this.pickFile,
  });

  @override
  State<FileTransferScreen> createState() => _FileTransferScreenState();
}

enum _Phase { idle, uploading, success, error }

class _FileTransferScreenState extends State<FileTransferScreen> {
  late final TransferClient _client;
  late final bool _ownsClient;

  _Phase _phase = _Phase.idle;
  PickedFile? _current;
  double _fraction = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? TransferClient();
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    super.dispose();
  }

  Future<PickedFile?> _pick() async {
    if (widget.pickFile != null) return widget.pickFile!();
    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result?.files.firstOrNull;
    if (file?.bytes == null) return null;
    return PickedFile(file!.name, file.bytes!);
  }

  Future<void> _chooseAndSend() async {
    final picked = await _pick();
    if (picked == null || !mounted) return;
    _current = picked;
    await _send();
  }

  /// (Re)lance l'envoi du fichier courant. Sur erreur réseau, un nouvel appel
  /// reprend là où ça s'est arrêté (les chunks déjà reçus sont sautés).
  Future<void> _send() async {
    final file = _current;
    if (file == null) return;
    setState(() {
      _phase = _Phase.uploading;
      _fraction = 0;
      _error = null;
    });
    try {
      await _client.uploadBytes(
        device: widget.device,
        filename: file.name,
        bytes: file.bytes,
        onProgress: (p) {
          if (mounted) setState(() => _fraction = p.fraction);
        },
      );
      if (!mounted) return;
      setState(() => _phase = _Phase.success);
    } on TransferException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = 'Erreur inattendue : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Envoyer vers ${widget.device.pcName}')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.idle:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.upload_file, size: 96, color: Colors.deepPurple.shade300),
            const SizedBox(height: 24),
            const Text(
              'Choisis un fichier à envoyer sur le PC',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _chooseAndSend,
              icon: const Icon(Icons.attach_file),
              label: const Text('Choisir un fichier'),
            ),
          ],
        );

      case _Phase.uploading:
        final percent = (_fraction * 100).clamp(0, 100).toStringAsFixed(0);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_current?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _fraction == 0 ? null : _fraction),
            const SizedBox(height: 8),
            Text('Envoi… $percent %', style: const TextStyle(color: Colors.grey)),
          ],
        );

      case _Phase.success:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 96, color: Colors.green.shade500),
            const SizedBox(height: 16),
            Text(
              'Envoyé 🎉\n${_current?.name ?? ''}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _chooseAndSend,
              icon: const Icon(Icons.attach_file),
              label: const Text('Envoyer un autre fichier'),
            ),
          ],
        );

      case _Phase.error:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 96, color: Colors.red.shade400),
            const SizedBox(height: 16),
            const Text('Échec de l\'envoi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => setState(() => _phase = _Phase.idle),
                  child: const Text('Annuler'),
                ),
                const SizedBox(width: 12),
                // Reprend l'envoi du même fichier (les chunks reçus sont sautés).
                FilledButton.icon(
                  onPressed: _send,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ],
        );
    }
  }
}
