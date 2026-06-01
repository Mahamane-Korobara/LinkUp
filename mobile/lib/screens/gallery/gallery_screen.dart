import 'package:flutter/material.dart';

import '../../services/gallery/gallery_client.dart';
import '../../services/gallery/gallery_indexer.dart';
import '../../services/gallery/photo_manager_source.dart';
import '../../services/pairing/paired_device_store.dart';

/// Écran d'indexation de la galerie vers le PC (S6).
///
/// Consentement explicite : l'utilisateur tape « Indexer ». On envoie au PC les
/// métadonnées + une vignette par média ; les originaux restent sur le tél.
class GalleryScreen extends StatefulWidget {
  final PairedDevice device;
  final GalleryIndexer? indexer;

  const GalleryScreen({super.key, required this.device, this.indexer});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

enum _Phase { idle, running, done, error }

class _GalleryScreenState extends State<GalleryScreen> {
  late final GalleryIndexer _indexer;
  late final bool _ownsIndexer;

  _Phase _phase = _Phase.idle;
  GalleryProgress _progress = const GalleryProgress(indexed: 0, thumbsSent: 0);
  String? _error;
  bool _cancel = false;

  @override
  void initState() {
    super.initState();
    _ownsIndexer = widget.indexer == null;
    _indexer = widget.indexer ??
        GalleryIndexer(source: PhotoManagerAssetSource(), client: GalleryClient());
  }

  @override
  void dispose() {
    _cancel = true;
    if (_ownsIndexer) _indexer.client.close();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.running;
      _error = null;
      _cancel = false;
      _progress = const GalleryProgress(indexed: 0, thumbsSent: 0);
    });
    try {
      await _indexer.run(
        widget.device,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        isCancelled: () => _cancel,
      );
      if (!mounted) return;
      setState(() => _phase = _cancel ? _Phase.idle : _Phase.done);
    } on GalleryException catch (e) {
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

  void _stop() => setState(() => _cancel = true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Galerie — ${widget.device.pcName}')),
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
            Icon(Icons.photo_library, size: 96, color: Colors.deepPurple.shade300),
            const SizedBox(height: 24),
            const Text(
              'Partager ta galerie avec le PC',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Linkup envoie au PC les métadonnées et une vignette de chaque '
              'photo/vidéo. Les originaux restent sur le téléphone jusqu\'à un import.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.cloud_sync),
              label: const Text('Indexer ma galerie'),
            ),
          ],
        );

      case _Phase.running:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 64, height: 64, child: CircularProgressIndicator(strokeWidth: 4)),
            const SizedBox(height: 24),
            Text(
              'Indexation… ${_progress.indexed} médias, ${_progress.thumbsSent} vignettes envoyées',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: _stop, child: const Text('Arrêter')),
          ],
        );

      case _Phase.done:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 96, color: Colors.green.shade500),
            const SizedBox(height: 16),
            Text(
              'Galerie indexée ✓\n${_progress.indexed} médias, ${_progress.thumbsSent} vignettes',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Ouvre la page « Galerie » du dashboard sur le PC.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.refresh),
              label: const Text('Ré-indexer'),
            ),
          ],
        );

      case _Phase.error:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 96, color: Colors.red.shade400),
            const SizedBox(height: 16),
            const Text('Indexation impossible', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        );
    }
  }
}
