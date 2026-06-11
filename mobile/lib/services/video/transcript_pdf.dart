import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'video_hub_client.dart';

// Palette alignée sur l'app (AppColors).
const _ink = PdfColor.fromInt(0xFF18181B); // titres / texte fort
const _body = PdfColor.fromInt(0xFF3F3F46); // texte courant
const _muted = PdfColor.fromInt(0xFF71717A); // texte secondaire
const _hair = PdfColor.fromInt(0xFFE4E4E7); // filet

/// Rend un [TranscriptDoc] formaté en PDF avec la MÊME qualité visuelle que
/// l'écran : police Inter (Stripe/Notion, comme l'app), titre, ligne meta,
/// titres de section, paragraphes aérés (interligne généreux).
///
/// La police Inter (+ ses accents/cyrillique/grec) est chargée à la volée via
/// `printing`. Repli silencieux sur la police par défaut si le chargement échoue
/// (ex. hors-ligne, comme en test) — le PDF reste valide.
Future<Uint8List> buildTranscriptPdf(TranscriptDoc doc) async {
  pw.ThemeData? theme;
  try {
    theme = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.interRegular(),
      bold: await PdfGoogleFonts.interBold(),
    );
  } catch (_) {
    theme = null; // repli police par défaut (Helvetica) — latin uniquement
  }

  final pdf = pw.Document(title: doc.title, theme: theme);
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 50, 48, 50),
      build: (context) {
        final widgets = <pw.Widget>[
          pw.Text(
            doc.title,
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
              letterSpacing: -0.3,
              lineSpacing: 2,
            ),
          ),
        ];

        final meta = _metaLine(doc);
        if (meta != null) {
          widgets.add(pw.SizedBox(height: 5));
          widgets.add(pw.Text(
            meta,
            style: const pw.TextStyle(fontSize: 10.5, color: _muted),
          ));
        }
        widgets.add(pw.SizedBox(height: 16));
        widgets.add(pw.Divider(color: _hair, thickness: 1, height: 1));
        widgets.add(pw.SizedBox(height: 18));

        for (final section in doc.sections) {
          final heading = section.heading?.trim();
          if (heading != null && heading.isNotEmpty) {
            widgets.add(pw.SizedBox(height: 6));
            widgets.add(pw.Text(
              heading,
              style: pw.TextStyle(
                fontSize: 13.5,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
                letterSpacing: 0.1,
              ),
            ));
            widgets.add(pw.SizedBox(height: 9));
          }
          for (final para in section.paragraphs) {
            widgets.add(pw.Text(
              para,
              textAlign: pw.TextAlign.left,
              style: const pw.TextStyle(
                fontSize: 11.5,
                color: _body,
                lineSpacing: 5.5, // interligne aéré (~1,5), comme l'écran
              ),
            ));
            widgets.add(pw.SizedBox(height: 11));
          }
        }
        return widgets;
      },
    ),
  );
  return pdf.save();
}

/// Ligne secondaire sous le titre (origine + mise en forme), comme l'écran.
String? _metaLine(TranscriptDoc doc) {
  final parts = <String>[
    doc.formattedBy == 'gemini' ? 'Mise en forme par IA' : 'Mise en forme basique',
  ];
  if (doc.subtitleSource == 'manual') {
    parts.add('sous-titres officiels');
  } else if (doc.subtitleSource == 'auto') {
    parts.add('sous-titres auto');
  }
  return parts.join('  ·  ');
}

/// Nom de fichier PDF sûr dérivé du titre (slug ASCII + .pdf).
String transcriptPdfName(String title) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final base = slug.isEmpty ? 'transcript' : slug;
  return '${base.length > 60 ? base.substring(0, 60) : base}.pdf';
}
