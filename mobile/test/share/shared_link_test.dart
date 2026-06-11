import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/services/share/shared_link.dart';

void main() {
  test('extrait une URL seule', () {
    expect(firstHttpUrl('https://youtu.be/abc'), 'https://youtu.be/abc');
  });

  test('extrait l\'URL au milieu d\'un texte', () {
    expect(
      firstHttpUrl('Regarde ça https://www.tiktok.com/@x/video/123 trop bien'),
      'https://www.tiktok.com/@x/video/123',
    );
  });

  test('gère http et garde la première', () {
    expect(
      firstHttpUrl('http://a.test/1 et https://b.test/2'),
      'http://a.test/1',
    );
  });

  test('renvoie null sans lien', () {
    expect(firstHttpUrl('aucun lien ici'), isNull);
    expect(firstHttpUrl(''), isNull);
  });
}
