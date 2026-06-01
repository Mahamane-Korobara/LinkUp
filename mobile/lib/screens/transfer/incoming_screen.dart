import 'package:flutter/material.dart';

import '../../services/pairing/paired_device_store.dart';
import '../../services/transfer/incoming_receiver.dart';
import '../../services/transfer/media_saver.dart';
import '../../services/transfer/transfer_client.dart';

/// Écran « Fichiers reçus du PC » (S6 — sens PC → tél).
///
/// Récupère les fichiers déposés depuis le dashboard et les enregistre dans la
/// galerie du téléphone. Geste explicite (pas de fond) : Android n'autorise pas
/// l'écriture galerie en arrière-plan de façon fiable.
class IncomingScreen extends StatefulWidget {
  final PairedDevice device;
  final IncomingReceiver? receiver;

  const IncomingScreen({super.key, required this.device, this.receiver});

  @override
  State<IncomingScreen> createState() => _IncomingScreenState();
}

enum _Phase { idle, running, done, error }

class _IncomingScreenState extends State<IncomingScreen> {
  late final IncomingReceiver _receiver;
  late final bool _owns;
  TransferClient? _ownTransfers;

  _Phase _phase = _Phase.idle;
  int _done = 0;
  int _total = 0;
  IncomingResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _owns = widget.receiver == null;
    if (widget.receiver != null) {
      _receiver = widget.receiver!;
    } else {
      _ownTransfers = TransferClient();
      _receiver = IncomingReceiver(transfers: _ownTransfers!, saver: PhotoManagerMediaSaver());
    }
  }

  @override
  void dispose() {
    if (_owns) _ownTransfers?.close();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _phase = _Phase.running;
      _error = null;
      _done = 0;
      _total = 0;
    });
    try {
      final result = await _receiver.run(
        widget.device,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _done = done;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _result = result;
      });
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
      appBar: AppBar(title: Text('Reçus du PC — ${widget.device.pcName}')),
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
            Icon(Icons.move_to_inbox, size: 96, color: Colors.deepPurple.shade300),
            const SizedBox(height: 24),
            const Text(
              'Récupérer les fichiers du PC',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Les fichiers envoyés depuis le PC seront enregistrés dans ta galerie.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.download),
              label: const Text('Récupérer'),
            ),
          ],
        );

      case _Phase.running:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 64, height: 64, child: CircularProgressIndicator(strokeWidth: 4)),
            const SizedBox(height: 24),
            Text(_total == 0 ? 'Recherche…' : 'Enregistrement $_done/$_total', textAlign: TextAlign.center),
          ],
        );

      case _Phase.done:
        final r = _result!;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(r.isEmpty ? Icons.inbox : Icons.check_circle,
                size: 96, color: r.isEmpty ? Colors.grey.shade400 : Colors.green.shade500),
            const SizedBox(height: 16),
            Text(
              r.isEmpty
                  ? 'Aucun fichier en attente.'
                  : '${r.saved} fichier(s) enregistré(s) dans la galerie'
                      '${r.failed > 0 ? '\n${r.failed} échec(s)' : ''}.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh),
              label: const Text('Vérifier à nouveau'),
            ),
          ],
        );

      case _Phase.error:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 96, color: Colors.red.shade400),
            const SizedBox(height: 16),
            const Text('Récupération impossible', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        );
    }
  }
}
