import 'package:flutter/material.dart';

import '../../services/gallery/gallery_client.dart';
import '../../services/gallery/gallery_importer.dart';
import '../../services/gallery/gallery_indexer.dart';
import '../../services/gallery/photo_manager_source.dart';
import '../../services/transfer/transfer_client.dart';
import '../../services/pairing/paired_device_store.dart';

/// Écran d'indexation de la galerie vers le PC (S6).
///
/// Consentement explicite : l'utilisateur tape « Indexer ». On envoie au PC les
/// métadonnées + une vignette par média ; les originaux restent sur le tél.
/// Un second geste (« Importer les médias demandés ») honore les demandes
/// d'originaux émises depuis le dashboard (S6.J4).
class GalleryScreen extends StatefulWidget {
  final PairedDevice device;
  final GalleryIndexer? indexer;
  final GalleryImporter? importer;

  const GalleryScreen({super.key, required this.device, this.indexer, this.importer});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

enum _Phase { idle, running, done, error }

class _GalleryScreenState extends State<GalleryScreen> {
  late final GalleryIndexer _indexer;
  late final GalleryImporter _importer;
  late final bool _ownsIndexer;
  late final bool _ownsImporter;
  TransferClient? _ownTransfers;

  _Phase _phase = _Phase.idle;
  GalleryProgress _progress = const GalleryProgress(indexed: 0, thumbsSent: 0);
  String? _error;
  bool _cancel = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _ownsIndexer = widget.indexer == null;
    _indexer = widget.indexer ??
        GalleryIndexer(source: PhotoManagerAssetSource(), client: GalleryClient());

    _ownsImporter = widget.importer == null;
    if (widget.importer != null) {
      _importer = widget.importer!;
    } else {
      _ownTransfers = TransferClient();
      _importer = GalleryImporter(
        source: PhotoManagerAssetSource(),
        client: GalleryClient(),
        transfers: _ownTransfers!,
      );
    }
  }

  @override
  void dispose() {
    _cancel = true;
    if (_ownsIndexer) _indexer.client.close();
    if (_ownsImporter) {
      _importer.client.close();
      _ownTransfers?.close();
    }
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

  /// Honore les demandes d'import émises depuis le dashboard. Affiche le bilan
  /// dans un SnackBar (best-effort : ne casse pas l'écran en cas d'échec).
  Future<void> _runImports() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await _importer.run(widget.device);
      if (!mounted) return;
      final msg = result.isEmpty
          ? 'Aucun import demandé par le PC.'
          : '${result.imported} original(aux) envoyé(s)'
              '${result.failed > 0 ? ', ${result.failed} échec(s)' : ''}.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } on GalleryException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur import : $e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Bouton « importer les médias demandés », partagé entre les phases idle/done.
  Widget _importButton() => OutlinedButton.icon(
        onPressed: _importing ? null : _runImports,
        icon: _importing
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.download),
        label: Text(_importing ? 'Import en cours…' : 'Importer les médias demandés par le PC'),
      );

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
            const SizedBox(height: 12),
            _importButton(),
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
            const SizedBox(height: 12),
            _importButton(),
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
