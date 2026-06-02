import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/pairing/paired_device_store.dart';
import '../../services/transfer/incoming_receiver.dart';
import '../../services/transfer/received_saver.dart';
import '../../services/transfer/transfer_client.dart';

/// Type d'un fichier reçu (pour le filtre + l'icône).
enum _Kind { image, video, document }

/// Filtre d'affichage des reçus.
enum _Filter { all, images, videos, documents }

const _imageExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'};
const _videoExt = {'mp4', 'mov', 'mkv', 'webm', '3gp', 'avi', 'm4v'};

_Kind _kindOf(String filename) {
  final dot = filename.lastIndexOf('.');
  final ext = dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
  if (_imageExt.contains(ext)) return _Kind.image;
  if (_videoExt.contains(ext)) return _Kind.video;
  return _Kind.document;
}

/// Écran « Reçus du PC » (S6 — sens PC → tél).
///
/// Liste les fichiers déposés depuis le dashboard (filtrables par type), et un
/// bouton « Récupérer » les télécharge et les enregistre (galerie pour les
/// médias, dossier « LinkupReçus » pour les documents). Geste explicite : Android
/// n'autorise pas l'écriture en arrière-plan de façon fiable.
class IncomingScreen extends StatefulWidget {
  final PairedDevice device;

  /// Embarqué dans un onglet (TransferHub) → pas de Scaffold/AppBar propre.
  final bool embedded;
  final IncomingReceiver? receiver;

  /// Intervalle de rafraîchissement « temps réel ». `null` = pas de polling
  /// (utile en test pour éviter un timer périodique).
  final Duration? pollInterval;

  const IncomingScreen({
    super.key,
    required this.device,
    this.embedded = false,
    this.receiver,
    this.pollInterval = const Duration(seconds: 4),
  });

  @override
  State<IncomingScreen> createState() => _IncomingScreenState();
}

enum _Phase { loading, list, running, error }

class _IncomingScreenState extends State<IncomingScreen> {
  late final IncomingReceiver _receiver;
  late final bool _owns;
  TransferClient? _ownTransfers;

  _Phase _phase = _Phase.loading;
  _Filter _filter = _Filter.all;
  List<TransferSummary> _pending = const [];
  int _done = 0;
  int _total = 0;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _owns = widget.receiver == null;
    if (widget.receiver != null) {
      _receiver = widget.receiver!;
    } else {
      _ownTransfers = TransferClient();
      _receiver = IncomingReceiver(transfers: _ownTransfers!, saver: DeviceFileSaver());
    }
    _loadList();
    // Temps réel : rafraîchit la liste régulièrement (le PC peut déposer un
    // fichier à tout moment). Silencieux : pas de spinner à chaque tick.
    if (widget.pollInterval != null) {
      _poll = Timer.periodic(widget.pollInterval!, (_) => _silentReload());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (_owns) _ownTransfers?.close();
    super.dispose();
  }

  /// Rafraîchissement discret (polling) : ne touche la liste que si on est déjà
  /// en train de l'afficher (pas pendant un téléchargement / une erreur).
  Future<void> _silentReload() async {
    if (_phase != _Phase.list) return;
    try {
      final pending = await _receiver.transfers.listIncoming(widget.device);
      if (mounted && _phase == _Phase.list) setState(() => _pending = pending);
    } catch (_) {
      // tick silencieux : on ignore une erreur ponctuelle de réseau
    }
  }

  Future<void> _loadList() async {
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      final pending = await _receiver.transfers.listIncoming(widget.device);
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _phase = _Phase.list;
      });
    } on TransferException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.message;
      });
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _phase = _Phase.running;
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_summary(result))));
      await _loadList(); // les fichiers remis disparaissent de la liste
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

  String _summary(IncomingResult r) {
    if (r.isEmpty) return 'Aucun fichier à récupérer.';
    final parts = <String>[];
    if (r.gallery > 0) parts.add('${r.gallery} dans la galerie');
    if (r.documents > 0) parts.add('${r.documents} dans « LinkupReçus »');
    return '${parts.join(' · ')}${r.failed > 0 ? ' · ${r.failed} échec(s)' : ''}.';
  }

  List<TransferSummary> get _visible {
    bool keep(_Kind k) {
      switch (_filter) {
        case _Filter.all:
          return true;
        case _Filter.images:
          return k == _Kind.image;
        case _Filter.videos:
          return k == _Kind.video;
        case _Filter.documents:
          return k == _Kind.document;
      }
    }

    return _pending.where((t) => keep(_kindOf(t.filename))).toList();
  }

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: const EdgeInsets.all(16), child: _buildBody());
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text('Reçus du PC — ${widget.device.pcName}')),
      body: body,
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());

      case _Phase.running:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 4)),
              const SizedBox(height: 20),
              Text(_total == 0 ? 'Recherche…' : 'Enregistrement $_done/$_total'),
            ],
          ),
        );

      case _Phase.error:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 72, color: Colors.red.shade400),
              const SizedBox(height: 12),
              const Text('Récupération impossible', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(_error ?? '', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _loadList, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
            ],
          ),
        );

      case _Phase.list:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _filterBar(),
            const SizedBox(height: 12),
            Expanded(child: _buildList()),
            SafeArea(
              top: false,
              child: FilledButton.icon(
                onPressed: _pending.isEmpty ? null : _fetch,
                icon: const Icon(Icons.download),
                label: Text(_pending.isEmpty
                    ? 'Aucun fichier en attente'
                    : 'Récupérer ${_pending.length} fichier(s)'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
          ],
        );
    }
  }

  /// Filtre en chips défilables (évite l'overflow des libellés longs).
  Widget _filterBar() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip('Tout', _Filter.all),
          _chip('Images', _Filter.images),
          _chip('Vidéos', _Filter.videos),
          _chip('Documents', _Filter.documents),
        ],
      ),
    );
  }

  Widget _chip(String label, _Filter value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _buildList() {
    final items = _visible;
    if (items.isEmpty) {
      return Center(
        child: Text(_pending.isEmpty
            ? 'Aucun fichier envoyé par le PC.\nDépose-en depuis l\'onglet « Envoyer » du dashboard.'
            : 'Rien pour ce filtre.'),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final t = items[i];
        final kind = _kindOf(t.filename);
        return ListTile(
          leading: Icon(switch (kind) {
            _Kind.image => Icons.image,
            _Kind.video => Icons.videocam,
            _Kind.document => Icons.description,
          }),
          title: Text(t.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }
}
