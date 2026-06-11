import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/share/shared_link.dart';
import '../../services/transfer/received_saver.dart';
import '../../services/video/transcript_cache.dart';
import '../../services/video/video_background_task.dart';
import '../../services/video/video_hub_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/section_label.dart';
import 'transcript_history_screen.dart';
import 'transcript_screen.dart';
import 'video_player_screen.dart';

/// Outil STANDALONE (sans PC) : coller un lien vidéo → aperçu → télécharger /
/// extraire l'audio / partager le fichier / transcript PDF / lire.
class VideoToolScreen extends StatefulWidget {
  /// Injectables pour les tests (sinon valeurs réelles).
  final VideoHubClient? client;
  final ReceivedFileSaver? saver;

  /// Lien pré-rempli (ex. ouvert via un partage entrant) : analysé au démarrage.
  final String? initialUrl;

  const VideoToolScreen({super.key, this.client, this.saver, this.initialUrl});

  @override
  State<VideoToolScreen> createState() => _VideoToolScreenState();
}

class _VideoToolScreenState extends State<VideoToolScreen> {
  late final VideoHubClient _client;
  late final ReceivedFileSaver _saver;
  final _urlController = TextEditingController();

  VideoMeta? _meta;
  bool _resolving = false;
  String? _error;

  /// Action de téléchargement en cours (libellé) + progression, pour ne lancer
  /// qu'une opération à la fois et afficher un état clair.
  String? _busyLabel;
  double _progress = 0;

  /// Fichiers déjà téléchargés (cache), pour que Lire / Télécharger / Partager
  /// réutilisent le même fichier au lieu de re-télécharger à chaque fois.
  /// Invalidés dès qu'on analyse un nouveau lien.
  File? _videoFile;
  File? _audioFile;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? VideoHubClient();
    _saver = widget.saver ?? DeviceFileSaver();
    // Lien reçu par partage : pré-remplir et analyser tout de suite.
    final shared = widget.initialUrl?.trim();
    if (shared != null && shared.isNotEmpty) {
      _urlController.text = shared;
      WidgetsBinding.instance.addPostFrameCallback((_) => _analyze());
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  bool get _busy => _busyLabel != null;

  Future<void> _analyze() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _resolving = true;
      _error = null;
      _meta = null;
      // Nouveau lien → on jette les fichiers téléchargés du lien précédent.
      _videoFile = null;
      _audioFile = null;
    });
    try {
      final meta = await _client.resolve(url);
      if (!mounted) return;
      setState(() => _meta = meta);
    } on VideoHubException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Erreur réseau : $e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Colle le lien depuis le presse-papier (en isolant l'URL si elle est noyée
  /// dans du texte) puis lance l'analyse.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    final url = firstHttpUrl(text) ?? (text.startsWith('http') ? text : '');
    if (url.isEmpty) {
      _snack('Aucun lien dans le presse-papier.');
      return;
    }
    _urlController.text = url;
    _analyze();
  }

  /// Ouvre la liste des transcriptions récentes (cache 2 jours).
  void _openHistory() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TranscriptHistoryScreen(saver: _saver),
    ));
  }

  /// Exécute [task] sous un service de premier plan : l'action continue si l'app
  /// passe en arrière-plan, avec une notification de progression. [donePush] est
  /// le texte de la notification de fin (null = pas de push, ex. lecture/partage
  /// dont la fin est déjà visible). [task] renvoie `true` si l'action a abouti.
  Future<void> _runBackground(
    String running,
    String? donePush,
    Future<bool> Function() task,
  ) async {
    await VideoBackgroundTask.begin(running);
    var ok = false;
    try {
      ok = await task();
    } finally {
      if (ok && donePush != null) {
        await VideoBackgroundTask.finishOk(donePush);
      } else {
        await VideoBackgroundTask.finish();
      }
    }
  }

  /// Télécharge le média dans un fichier temporaire avec progression, ou renvoie
  /// le fichier déjà en cache (évite de re-télécharger pour Lire/Partager).
  Future<File?> _download(String kind) async {
    final cached = kind == 'audio' ? _audioFile : _videoFile;
    if (cached != null && await cached.exists()) return cached;

    final url = _urlController.text.trim();
    setState(() {
      _busyLabel = kind == 'audio' ? 'Extraction audio…' : 'Téléchargement…';
      _progress = 0;
    });
    try {
      final file = await _client.downloadToFile(
        url,
        kind: kind,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
          // Reflète la progression dans la notification d'arrière-plan.
          VideoBackgroundTask.progress(p);
        },
      );
      if (kind == 'audio') {
        _audioFile = file;
      } else {
        _videoFile = file;
      }
      return file;
    } on VideoHubException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Échec : $e');
    } finally {
      if (mounted) setState(() => _busyLabel = null);
    }
    return null;
  }

  Future<void> _saveVideo() => _runBackground(
        'Téléchargement…',
        'Vidéo enregistrée dans la galerie',
        () async {
          final file = await _download('video');
          if (file == null) return false;
          final result = await _saver.saveFile(file.path.split('/').last, file);
          final ok = result.kind != SaveKind.failed;
          _snack(ok
              ? 'Vidéo enregistrée dans la galerie.'
              : 'Échec de l\'enregistrement.');
          return ok;
        },
      );

  Future<void> _saveAudio() => _runBackground(
        'Extraction audio…',
        'Audio enregistré',
        () async {
          final file = await _download('audio');
          if (file == null) return false;
          final result = await _saver.saveFile(file.path.split('/').last, file);
          final ok = result.kind != SaveKind.failed;
          _snack(ok
              ? 'Audio enregistré : ${result.location ?? 'Documents'}'
              : 'Échec de l\'enregistrement.');
          return ok;
        },
      );

  Future<void> _shareVideo() => _runBackground(
        'Téléchargement…',
        null, // l'ouverture du partage est déjà la « fin » visible
        () async {
          final file = await _download('video');
          if (file == null) return false;
          await SharePlus.instance.share(
            ShareParams(files: [XFile(file.path)], text: _meta?.title),
          );
          return true;
        },
      );

  Future<void> _play() => _runBackground(
        'Téléchargement…',
        null, // la lecture est déjà la « fin » visible
        () async {
          final file = await _download('video');
          if (file == null || !mounted) return false;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                VideoPlayerScreen(file: file, title: _meta?.title ?? 'Vidéo'),
          ));
          return true;
        },
      );

  Future<void> _transcript() async {
    final url = _urlController.text.trim();
    // 1) Cache (2 jours) : si cette vidéo a déjà été transcrite récemment, on
    //    rouvre le résultat SANS rappeler le serveur (économise les requêtes IA).
    final cached = await TranscriptCache.get(url);
    if (cached != null) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TranscriptScreen(doc: cached, saver: _saver),
      ));
      _snack('Déjà transcrit récemment — réutilisé (cache).');
      return;
    }
    // 2) Sinon : appel serveur en arrière-plan, puis mise en cache du résultat.
    await _runBackground('Transcription IA…', 'Transcription prête', () async {
      setState(() {
        _busyLabel = 'Transcription IA en cours… patiente un peu';
        _progress = 0;
      });
      try {
        final doc = await _client.transcript(url);
        if (!mounted) return false;
        if (!doc.available) {
          _snack(doc.reason ?? 'Sous-titres non présents sur cette vidéo.');
          return false;
        }
        await TranscriptCache.put(url, doc, thumbnail: _meta?.thumbnail);
        if (!mounted) return false;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TranscriptScreen(doc: doc, saver: _saver),
        ));
        return true;
      } on VideoHubException catch (e) {
        _snack(e.message);
        return false;
      } catch (e) {
        _snack('Échec : $e');
        return false;
      } finally {
        if (mounted) setState(() => _busyLabel = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const AppLogo(size: 30, showWordmark: true),
        actions: [
          IconButton(
            tooltip: 'Transcriptions récentes',
            icon: const Icon(Icons.history_rounded),
            onPressed: _busy ? null : _openHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_resolving || _busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                const SectionLabel('Lien de la vidéo'),
                const SizedBox(height: 12),
                _UrlField(
                  controller: _urlController,
                  enabled: !_busy,
                  onSubmit: _analyze,
                  onPaste: _busy ? null : _paste,
                ),
                const SizedBox(height: 12),
                _PrimaryButton(
                  label: 'Analyser',
                  busy: _resolving,
                  onTap: _busy ? null : _analyze,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(message: _error!),
                ],
                if (_meta != null) ...[
                  const SizedBox(height: 24),
                  _PreviewCard(meta: _meta!),
                  const SizedBox(height: 20),
                  const SectionLabel('Actions'),
                  const SizedBox(height: 12),
                  if (_busy) ...[
                    _BusyRow(label: _busyLabel!, progress: _progress),
                    const SizedBox(height: 12),
                  ],
                  _ActionTile(
                    icon: Icons.play_circle_outline_rounded,
                    title: 'Lire',
                    subtitle: 'Télécharger puis lire sur le téléphone',
                    onTap: _busy ? null : _play,
                  ),
                  _ActionTile(
                    icon: Icons.download_rounded,
                    title: 'Télécharger la vidéo',
                    subtitle: 'Enregistrer dans la galerie',
                    onTap: _busy ? null : _saveVideo,
                  ),
                  _ActionTile(
                    icon: Icons.music_note_rounded,
                    title: 'Extraire l\'audio',
                    subtitle: 'Garder juste le son (M4A)',
                    onTap: _busy ? null : _saveAudio,
                  ),
                  _ActionTile(
                    icon: Icons.ios_share_rounded,
                    title: 'Partager la vidéo',
                    subtitle: 'Envoyer le fichier (pas le lien)',
                    onTap: _busy ? null : _shareVideo,
                  ),
                  _ActionTile(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Transcription IA',
                    subtitle: _meta!.hasSubtitles
                        ? 'Texte mis en forme par IA → PDF (peut prendre un moment)'
                        : 'Sous-titres non présents sur cette vidéo',
                    enabled: _meta!.hasSubtitles,
                    onTap: (_busy || !_meta!.hasSubtitles) ? null : _transcript,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

class _UrlField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmit;
  final VoidCallback? onPaste;

  const _UrlField({
    required this.controller,
    required this.enabled,
    required this.onSubmit,
    this.onPaste,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.url,
      autocorrect: false,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        hintText: 'Coller un lien (YouTube, TikTok, Insta…)',
        prefixIcon: const Icon(Icons.link_rounded, color: AppColors.faint),
        suffixIcon: TextButton.icon(
          onPressed: onPaste,
          icon: const Icon(Icons.content_paste_rounded, size: 18),
          label: const Text('Coller'),
          style: TextButton.styleFrom(foregroundColor: AppColors.brand),
        ),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.line),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onTap;

  const _PrimaryButton({required this.label, this.busy = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label,
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final VideoMeta meta;

  const _PreviewCard({required this.meta});

  @override
  Widget build(BuildContext context) {
    final duration = _formatDuration(meta.durationSeconds);
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meta.thumbnail != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  meta.thumbnail!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.bg,
                    child: const Icon(Icons.movie_outlined, color: AppColors.faint),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            meta.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (meta.uploader.isNotEmpty) meta.uploader,
              if (duration.isNotEmpty) duration,
            ].join('  ·  '),
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _BusyRow extends StatelessWidget {
  final String label;
  final double progress;

  const _BusyRow({required this.label, required this.progress});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.brand,
              value: progress > 0 && progress < 1 ? progress : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              progress > 0 && progress < 1
                  ? '$label ${(progress * 100).round()}%'
                  : label,
              style: const TextStyle(fontSize: 14, color: AppColors.body),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? AppColors.ink : AppColors.faint;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: enabled ? AppColors.brandSoft : AppColors.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: enabled ? AppColors.brand : AppColors.faint),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: fg,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            if (enabled)
              const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
