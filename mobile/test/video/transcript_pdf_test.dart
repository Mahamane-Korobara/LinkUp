import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/services/video/transcript_pdf.dart';
import 'package:linkup_mobile/services/video/video_hub_client.dart';

void main() {
  // PdfGoogleFonts accède au bundle/réseau ; en test ça échoue et le builder
  // retombe sur la police par défaut. On initialise le binding pour un échec propre.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildTranscriptPdf produit un PDF non vide', () async {
    const doc = TranscriptDoc(
      available: true,
      title: 'Mon transcript',
      sections: [
        TranscriptSection('Intro', ['Bonjour à toutes et à tous.']),
        TranscriptSection(null, ['Paragraphe sans titre, avec accents : éàç.']),
      ],
    );
    final bytes = await buildTranscriptPdf(doc);
    expect(bytes.length, greaterThan(500));
    // En-tête magique d'un fichier PDF : "%PDF".
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('transcriptPdfName slugifie le titre', () {
    expect(transcriptPdfName('Mon Super Titre !'), 'mon-super-titre.pdf');
    expect(transcriptPdfName(''), 'transcript.pdf');
    expect(transcriptPdfName('   '), 'transcript.pdf');
  });
}
