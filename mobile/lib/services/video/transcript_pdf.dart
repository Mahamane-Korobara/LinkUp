import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'video_hub_client.dart';

/// Rend un [TranscriptDoc] formaté en PDF (titre → sections → paragraphes).
///
/// La police Helvetica par défaut du paquet `pdf` encode en WinAnsi : couvre le
/// français/anglais/latin (accents, guillemets « », ', —). Limite connue : les
/// alphabets non-latins (arabe, cyrillique, CJK) ne s'affichent pas — il faudrait
/// embarquer une police Unicode (Noto) si on transcrit ces langues.
Future<Uint8List> buildTranscriptPdf(TranscriptDoc doc) async {
  final pdf = pw.Document(title: doc.title);
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) {
        final widgets = <pw.Widget>[
          pw.Header(
            level: 0,
            child: pw.Text(
              doc.title,
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 8),
        ];
        for (final section in doc.sections) {
          if (section.heading != null && section.heading!.trim().isNotEmpty) {
            widgets.add(pw.SizedBox(height: 10));
            widgets.add(pw.Text(
              section.heading!,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ));
            widgets.add(pw.SizedBox(height: 4));
          }
          for (final para in section.paragraphs) {
            widgets.add(pw.Paragraph(
              text: para,
              style: const pw.TextStyle(fontSize: 11.5, lineSpacing: 2),
            ));
          }
        }
        return widgets;
      },
    ),
  );
  return pdf.save();
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
