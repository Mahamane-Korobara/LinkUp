import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../services/transfer/received_saver.dart';
import '../../services/video/transcript_pdf.dart';
import '../../services/video/video_hub_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/section_label.dart';

/// Affiche le transcript formaté « comme un document » : copier le texte,
/// l'enregistrer en PDF (dossier public Téléchargements/LinkUp) ou le partager.
class TranscriptScreen extends StatefulWidget {
  final TranscriptDoc doc;
  final ReceivedFileSaver saver;

  const TranscriptScreen({super.key, required this.doc, required this.saver});

  @override
  State<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends State<TranscriptScreen> {
  bool _busy = false;

  Future<void> _savePdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await buildTranscriptPdf(widget.doc);
      final name = transcriptPdfName(widget.doc.title);
      final result = await widget.saver.save(name, bytes);
      if (!mounted) return;
      final msg = result.kind == SaveKind.failed
          ? 'Échec de l\'enregistrement du PDF.'
          : 'PDF enregistré : ${result.location ?? name}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Copie tout le texte du transcript (titre + sections + paragraphes).
  Future<void> _copyText() async {
    final b = StringBuffer();
    b.writeln(widget.doc.title);
    b.writeln();
    for (final s in widget.doc.sections) {
      final h = s.heading?.trim();
      if (h != null && h.isNotEmpty) {
        b.writeln(h);
        b.writeln();
      }
      for (final p in s.paragraphs) {
        b.writeln(p);
        b.writeln();
      }
    }
    await Clipboard.setData(ClipboardData(text: b.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Texte copié.')));
  }

  Future<void> _sharePdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await buildTranscriptPdf(widget.doc);
      await Printing.sharePdf(
        bytes: bytes,
        filename: transcriptPdfName(widget.doc.title),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final formattedLabel = doc.formattedBy == 'gemini'
        ? 'Mise en forme par IA'
        : 'Mise en forme basique';
    return Scaffold(
      appBar: AppBar(title: const Text('Transcription IA')),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Text(
                  doc.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$formattedLabel · ${doc.subtitleSource == 'manual' ? 'sous-titres officiels' : 'sous-titres auto'}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
                const SizedBox(height: 20),
                for (final section in doc.sections) ...[
                  if (section.heading != null &&
                      section.heading!.trim().isNotEmpty) ...[
                    SectionLabel(section.heading!),
                    const SizedBox(height: 10),
                  ],
                  for (final para in section.paragraphs) ...[
                    Text(
                      para,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.content_copy_rounded,
                      label: 'Copier',
                      onTap: _busy ? null : _copyText,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.picture_as_pdf_rounded,
                      label: 'PDF',
                      onTap: _busy ? null : _savePdf,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.ios_share_rounded,
                      label: 'Partager',
                      onTap: _busy ? null : _sharePdf,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: AppColors.brand),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
