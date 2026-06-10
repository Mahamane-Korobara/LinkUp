import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/services/transfer/received_saver.dart';

void main() {
  group('safeReceivedName (anti path-traversal)', () {
    test('garde un nom simple tel quel', () {
      expect(safeReceivedName('photo.jpg'), 'photo.jpg');
      expect(safeReceivedName('Mon Document (1).pdf'), 'Mon Document (1).pdf');
    });

    test('neutralise les tentatives de traversée', () {
      expect(safeReceivedName('../../../../etc/passwd'), 'passwd');
      expect(safeReceivedName('/sdcard/Download/evil.apk'), 'evil.apk');
      expect(safeReceivedName(r'..\..\Windows\system32\x.dll'), 'x.dll');
      expect(safeReceivedName('dossier/sous/fichier.txt'), 'fichier.txt');
    });

    test('repli sur « fichier » pour les noms vides ou dangereux seuls', () {
      expect(safeReceivedName('..'), 'fichier');
      expect(safeReceivedName('.'), 'fichier');
      expect(safeReceivedName('a/..'), 'fichier');
      expect(safeReceivedName('   '), 'fichier');
      expect(safeReceivedName('foo/'), 'fichier');
    });
  });
}
