import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/utils/address_validators.dart';

void main() {
  group('validateAddress', () {
    test('rejects empty', () {
      expect(validateAddress(''), 'Adresse requise');
      expect(validateAddress('   '), 'Adresse requise');
      expect(validateAddress(null), 'Adresse requise');
    });

    test('accepts valid IPv4', () {
      expect(validateAddress('192.168.1.42'), isNull);
      expect(validateAddress('10.0.0.1'), isNull);
      expect(validateAddress('0.0.0.0'), isNull);
      expect(validateAddress('255.255.255.255'), isNull);
    });

    test('rejects octets > 255', () {
      expect(validateAddress('256.1.1.1'), isNotNull);
      expect(validateAddress('999.0.0.0'), isNotNull);
      expect(validateAddress('192.168.1.256'), isNotNull);
    });

    test('rejects malformed IPs', () {
      expect(validateAddress('1.2.3'), isNotNull);
      expect(validateAddress('1.2.3.4.5'), isNotNull);
      expect(validateAddress('1.2.3.a'), isNotNull);
      expect(validateAddress('1.2..4'), isNotNull);
    });

    test('accepts hostname.local', () {
      expect(validateAddress('pc.local'), isNull);
      expect(validateAddress('mahamane-VivoBook.local'), isNull);
      expect(validateAddress('abc123.local'), isNull);
    });

    test('rejects hostname without .local suffix', () {
      // Sans .local, un nom court risque une résolution DNS publique (timeout
      // long ou page de capture du FAI).
      expect(validateAddress('pc'), isNotNull);
      expect(validateAddress('mahamane-VivoBook'), isNotNull);
    });

    test('rejects garbage strings', () {
      expect(validateAddress('foobar'), isNotNull);
      expect(validateAddress('http://1.2.3.4'), isNotNull);
      expect(validateAddress('1.2.3.4:8765'), isNotNull);
    });

    test('trims whitespace before validating', () {
      expect(validateAddress('  192.168.1.42  '), isNull);
    });
  });

  group('validatePort', () {
    test('accepts valid ports', () {
      expect(validatePort('1'), isNull);
      expect(validatePort('8765'), isNull);
      expect(validatePort('65535'), isNull);
    });

    test('rejects out of range', () {
      expect(validatePort('0'), isNotNull);
      expect(validatePort('-1'), isNotNull);
      expect(validatePort('65536'), isNotNull);
      expect(validatePort('99999'), isNotNull);
    });

    test('rejects non-numeric', () {
      expect(validatePort(''), isNotNull);
      expect(validatePort(null), isNotNull);
      expect(validatePort('abc'), isNotNull);
      expect(validatePort('8080.5'), isNotNull);
    });

    test('trims whitespace', () {
      expect(validatePort('  8765  '), isNull);
    });
  });
}
