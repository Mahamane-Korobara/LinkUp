import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/services/preview/preview_shim.dart';

void main() {
  group('buildNetworkShim', () {
    test('injecte chaque port exposé dans la table', () {
      final js = buildNetworkShim([5173, 4000, 6001]);
      expect(js, contains('[5173, 4000, 6001]'));
    });

    test('est idempotent côté JS (drapeau install)', () {
      final js = buildNetworkShim([3000]);
      expect(js, contains('window.__linkupShimInstalled'));
    });

    test('réécrit vers le préfixe single-origin /__linkup/', () {
      final js = buildNetworkShim([8000]);
      expect(js, contains("/__linkup/"));
    });

    test('patche les quatre primitives réseau', () {
      final js = buildNetworkShim([8000]);
      expect(js, contains('window.fetch'));
      expect(js, contains('XMLHttpRequest.prototype.open'));
      expect(js, contains('window.WebSocket'));
      expect(js, contains('window.EventSource'));
    });

    test('liste vide → shim valide sans port (no-op)', () {
      final js = buildNetworkShim(const []);
      expect(js, contains('var ports = [];'));
      expect(js, isNot(contains('__LINKUP_PORTS__'))); // placeholder bien remplacé
    });

    test('ne laisse pas le placeholder non substitué', () {
      final js = buildNetworkShim([1234]);
      expect(js, isNot(contains('__LINKUP_PORTS__')));
    });
  });
}
