import 'package:flutter/material.dart';

import '../../services/transfer/received_saver.dart';
import '../../services/video/transcript_cache.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import 'transcript_screen.dart';

/// Liste des transcriptions IA déjà faites (cache, 2 jours). Tape une entrée →
/// rouvre la transcription **sans refaire l'appel** (économise les requêtes).
class TranscriptHistoryScreen extends StatefulWidget {
  final ReceivedFileSaver saver;

  const TranscriptHistoryScreen({super.key, required this.saver});

  @override
  State<TranscriptHistoryScreen> createState() =>
      _TranscriptHistoryScreenState();
}

class _TranscriptHistoryScreenState extends State<TranscriptHistoryScreen> {
  List<CachedTranscript> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await TranscriptCache.list();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  Future<void> _delete(CachedTranscript e) async {
    await TranscriptCache.remove(e);
    await _reload();
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Vider le cache ?'),
        content: const Text(
            'Les transcriptions enregistrées seront supprimées. Elles seront '
            'recalculées si tu en redemandes une.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Vider')),
        ],
      ),
    );
    if (ok == true) {
      await TranscriptCache.clear();
      await _reload();
    }
  }

  void _open(CachedTranscript e) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TranscriptScreen(doc: e.doc, saver: widget.saver),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcriptions récentes'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: 'Vider le cache',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const _Empty()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  itemCount: _entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _Tile(
                    entry: _entries[i],
                    onTap: () => _open(_entries[i]),
                    onDelete: () => _delete(_entries[i]),
                  ),
                ),
    );
  }
}

class _Tile extends StatelessWidget {
  final CachedTranscript entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _Tile({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.article_outlined, color: AppColors.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.doc.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _ago(entry.date),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Retirer',
            icon: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.faint),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 40, color: AppColors.faint),
            SizedBox(height: 12),
            Text(
              'Aucune transcription récente.\nElles sont gardées 2 jours.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
