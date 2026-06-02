import 'package:flutter/material.dart';

import '../../services/gallery/gallery_sender.dart';
import '../../services/gallery/gallery_source.dart';
import '../../services/gallery/photo_manager_source.dart';
import '../../services/pairing/paired_device_store.dart';
import '../../services/transfer/transfer_client.dart';

/// Picker d'envoi de photos vers le PC (S6 — modèle « je choisis sur le tél »).
///
/// L'utilisateur parcourt SA galerie, coche les médias voulus, puis les envoie :
/// chacun part comme un transfert S4 et atterrit dans « Fichiers » côté PC. Rien
/// n'est indexé/mirroré — seul ce qu'il choisit quitte le téléphone.
class GallerySendScreen extends StatefulWidget {
  final PairedDevice device;

  /// Embarqué dans un onglet (TransferHub) → pas de Scaffold/AppBar propre.
  final bool embedded;

  /// Injectables pour les tests (sinon plugin + réseau réels).
  final GalleryAssetSource? source;
  final GallerySender? sender;

  const GallerySendScreen({
    super.key,
    required this.device,
    this.embedded = false,
    this.source,
    this.sender,
  });

  @override
  State<GallerySendScreen> createState() => _GallerySendScreenState();
}

enum _Phase { loading, picking, sending, done, error }

/// Filtre d'affichage de la grille galerie.
enum _MediaFilter { all, photos, videos }

class _GallerySendScreenState extends State<GallerySendScreen> {
  static const _pageSize = 60;

  late final GalleryAssetSource _source;
  late final GallerySender _sender;
  TransferClient? _ownTransfers;
  bool _ownsSender = false;

  final _scroll = ScrollController();
  final List<GalleryAsset> _assets = [];
  final Set<String> _selected = {};
  _MediaFilter _filter = _MediaFilter.all;

  _Phase _phase = _Phase.loading;
  String? _error;
  int _page = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  GallerySendProgress? _progress;
  GallerySendResult? _result;
  bool _cancel = false;

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? PhotoManagerAssetSource();
    if (widget.sender != null) {
      _sender = widget.sender!;
    } else {
      _ownsSender = true;
      _ownTransfers = TransferClient();
      _sender = GallerySender(source: _source, transfers: _ownTransfers!);
    }
    _scroll.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _cancel = true;
    _scroll.dispose();
    if (_ownsSender) _ownTransfers?.close();
    super.dispose();
  }

  Future<void> _loadFirst() async {
    try {
      if (!await _source.requestPermission()) {
        setState(() {
          _phase = _Phase.error;
          _error = 'Permission galerie refusée. Autorise l\'accès aux photos pour les envoyer.';
        });
        return;
      }
      await _loadPage();
      if (mounted) setState(() => _phase = _Phase.picking);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = 'Lecture de la galerie impossible : $e';
        });
      }
    }
  }

  Future<void> _loadPage() async {
    final page = await _source.list(page: _page, size: _pageSize);
    if (!mounted) return;
    setState(() {
      _assets.addAll(page);
      _hasMore = page.length == _pageSize;
      _page++;
    });
  }

  void _onScroll() {
    if (_phase != _Phase.picking || _loadingMore || !_hasMore) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      await _loadPage();
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _toggle(String mediaId) {
    setState(() {
      if (_selected.contains(mediaId)) {
        _selected.remove(mediaId);
      } else {
        _selected.add(mediaId);
      }
    });
  }

  Future<void> _send() async {
    if (_selected.isEmpty) return;
    final ids = _selected.toList();
    setState(() {
      _phase = _Phase.sending;
      _cancel = false;
      _progress = GallerySendProgress(done: 0, total: ids.length, currentName: '', fileFraction: 0);
    });
    try {
      final result = await _sender.send(
        widget.device,
        ids,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        isCancelled: () => _cancel,
      );
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _result = result;
        _selected.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = 'Envoi interrompu : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sendBar = _phase == _Phase.picking ? _buildSendBar() : null;

    if (widget.embedded) {
      return Column(
        children: [
          Expanded(child: _buildBody()),
          ?sendBar,
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Envoyer au PC — ${widget.device.pcName}')),
      body: _buildBody(),
      bottomNavigationBar: sendBar,
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());

      case _Phase.error:
        return _centered(
          Icons.error_outline,
          Colors.red.shade400,
          'Impossible',
          _error ?? '',
          action: FilledButton.icon(
            onPressed: () {
              setState(() {
                _phase = _Phase.loading;
                _error = null;
                _assets.clear();
                _page = 0;
                _hasMore = true;
              });
              _loadFirst();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        );

      case _Phase.sending:
        final p = _progress!;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 64, height: 64, child: CircularProgressIndicator(strokeWidth: 4)),
              const SizedBox(height: 24),
              Text(
                'Envoi ${p.done + 1}/${p.total}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(p.currentName, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: p.fileFraction == 0 ? null : p.fileFraction),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Garde l\'app ouverte pendant l\'envoi — ça peut prendre un moment '
                        'selon le nombre et la taille des photos.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _cancel = true),
                child: const Text('Arrêter après ce fichier'),
              ),
            ],
          ),
        );

      case _Phase.done:
        final r = _result!;
        return _centered(
          Icons.check_circle,
          Colors.green.shade500,
          'Envoi terminé',
          '${r.sent} photo(s) envoyée(s) au PC'
              '${r.failed > 0 ? '\n${r.failed} échec(s)' : ''}.\nRetrouve-les dans « Fichiers » sur le PC.',
          action: FilledButton.icon(
            onPressed: () => setState(() => _phase = _Phase.picking),
            icon: const Icon(Icons.photo_library),
            label: const Text('Envoyer d\'autres photos'),
          ),
        );

      case _Phase.picking:
        return _buildGrid();
    }
  }

  /// Assets visibles selon le filtre Tout / Photos / Vidéos.
  List<GalleryAsset> get _visible {
    switch (_filter) {
      case _MediaFilter.all:
        return _assets;
      case _MediaFilter.photos:
        return _assets.where((a) => !a.meta.isVideo).toList();
      case _MediaFilter.videos:
        return _assets.where((a) => a.meta.isVideo).toList();
    }
  }

  Widget _buildGrid() {
    final visible = _visible;
    return Column(
      children: [
        _filterBar(),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(_assets.isEmpty
                      ? 'Aucune photo dans la galerie.'
                      : 'Rien à afficher pour ce filtre.'),
                )
              : GridView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(4),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: visible.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= visible.length) {
                      return const Center(
                          child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                    }
                    final asset = visible[i];
                    final selected = _selected.contains(asset.meta.mediaId);
                    return _Tile(asset: asset, selected: selected, onTap: () => _toggle(asset.meta.mediaId));
                  },
                ),
        ),
      ],
    );
  }

  /// Sélecteur Tout / Photos / Vidéos (pour distinguer photos et vidéos).
  Widget _filterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: SegmentedButton<_MediaFilter>(
        segments: const [
          ButtonSegment(value: _MediaFilter.all, label: Text('Tout')),
          ButtonSegment(value: _MediaFilter.photos, label: Text('Photos'), icon: Icon(Icons.photo)),
          ButtonSegment(value: _MediaFilter.videos, label: Text('Vidéos'), icon: Icon(Icons.videocam)),
        ],
        selected: {_filter},
        onSelectionChanged: (s) => setState(() => _filter = s.first),
      ),
    );
  }

  Widget _buildSendBar() {
    final n = _selected.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: n == 0 ? null : _send,
          icon: const Icon(Icons.send),
          label: Text(n == 0 ? 'Sélectionne des médias' : 'Envoyer $n élément(s) au PC'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ),
    );
  }

  Widget _centered(IconData icon, Color color, String title, String body, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 96, color: color),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 24), action],
        ],
      ),
    );
  }
}

/// Une vignette sélectionnable de la grille.
class _Tile extends StatelessWidget {
  final GalleryAsset asset;
  final bool selected;
  final VoidCallback onTap;

  const _Tile({required this.asset, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder(
            future: asset.loadThumbnail(),
            builder: (context, snap) {
              final bytes = snap.data;
              if (bytes == null) {
                return Container(color: Colors.grey.shade200);
              }
              return Image.memory(bytes, fit: BoxFit.cover);
            },
          ),
          if (asset.meta.isVideo)
            const Positioned(
              bottom: 4,
              right: 4,
              child: Icon(Icons.play_circle_fill, color: Colors.white, size: 18),
            ),
          if (selected)
            Container(
              color: Colors.indigo.withValues(alpha: 0.35),
              child: const Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: CircleAvatar(
                    radius: 11,
                    backgroundColor: Colors.indigo,
                    child: Icon(Icons.check, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
