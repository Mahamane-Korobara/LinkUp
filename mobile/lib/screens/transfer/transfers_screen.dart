import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/pairing/paired_device_store.dart';
import '../../services/transfer/transfer_client.dart';
import 'file_transfer_screen.dart';

/// Ouvre localement un fichier (octets) — injectable pour les widget tests.
typedef FileOpener = Future<void> Function(String filename, List<int> bytes);

/// Historique des fichiers envoyés au PC + accès rapide à un nouvel envoi (S4).
///
/// Liste alimentée par `GET /api/transfers` (scopé à ce tél). Le bouton flottant
/// ouvre l'écran de sélection/envoi ; au retour, la liste se rafraîchit.
class TransfersScreen extends StatefulWidget {
  final PairedDevice device;

  /// Embarqué dans un onglet (TransferHub) → pas de Scaffold/AppBar propre.
  final bool embedded;
  final TransferClient? client;

  /// Ouverture locale injectable (sinon écrit en cache + open_filex).
  final FileOpener? openLocalFile;

  const TransfersScreen({
    super.key,
    required this.device,
    this.embedded = false,
    this.client,
    this.openLocalFile,
  });

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  late final TransferClient _client;
  late final bool _ownsClient;

  List<TransferSummary>? _items;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? TransferClient();
    _load();
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _client.listTransfers(widget.device);
      if (!mounted) return;
      setState(() => _items = items);
    } on TransferException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Re-télécharge le fichier depuis le PC et l'ouvre sur le téléphone.
  Future<void> _openOnPhone(TransferSummary item) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('Téléchargement de ${item.filename}…')));
    try {
      final bytes = await _client.downloadBytes(widget.device, item.id);
      await (widget.openLocalFile ?? _defaultOpenLocal)(item.filename, bytes);
    } on TransferException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  static Future<void> _defaultOpenLocal(String filename, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$filename';
    await File(path).writeAsBytes(bytes, flush: true);
    await OpenFilex.open(path);
  }

  Future<void> _openSend() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FileTransferScreen(device: widget.device),
      ),
    );
    // Au retour de l'envoi, on recharge l'historique.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      // Onglet « Fichier » du hub : historique + bouton d'envoi, sans Scaffold.
      return Column(
        children: [
          Expanded(child: RefreshIndicator(onRefresh: _load, child: _buildBody())),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: _openSend,
                icon: const Icon(Icons.upload_file),
                label: const Text('Envoyer un fichier'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Transferts — ${widget.device.pcName}'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSend,
        icon: const Icon(Icons.upload_file),
        label: const Text('Envoyer un fichier'),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items == null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Center(child: Text(_error!, textAlign: TextAlign.center)),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ),
        ],
      );
    }
    final items = _items ?? const [];
    if (items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.inbox, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Center(child: Text('Aucun fichier envoyé pour l\'instant.')),
        ],
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _TransferTile(
        items[i],
        // Seuls les fichiers bien arrivés sont ouvrables (sur le téléphone).
        onOpen: items[i].isCompleted ? () => _openOnPhone(items[i]) : null,
      ),
    );
  }
}

class _TransferTile extends StatelessWidget {
  final TransferSummary item;
  final VoidCallback? onOpen;
  const _TransferTile(this.item, {this.onOpen});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String label) = switch (item.status) {
      'completed' => (Icons.check_circle, Colors.green, 'Envoyé'),
      'failed' => (Icons.error, Colors.red, 'Échec'),
      'cancelled' => (Icons.cancel, Colors.grey, 'Annulé'),
      'uploading' => (Icons.upload, Colors.blue, 'En cours'),
      _ => (Icons.hourglass_empty, Colors.orange, 'En attente'),
    };

    final subtitle = [
      _formatBytes(item.size),
      _formatDate(item.completedAt ?? item.createdAt),
    ].where((s) => s.isNotEmpty).join('  •  ');

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(item.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      onTap: onOpen,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          if (onOpen != null)
            const Text('Ouvrir ›',
                style: TextStyle(fontSize: 11, color: Colors.indigo)),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} Mo';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} Go';
  }

  static String _formatDate(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
  }
}
