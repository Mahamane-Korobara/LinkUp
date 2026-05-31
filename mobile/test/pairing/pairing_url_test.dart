import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/services/pairing/pairing_url.dart';

void main() {
  group('PairingUrl.parse', () {
    test('parses a valid URL', () {
      final url = PairingUrl.parse(
        'linkup://192.168.1.42:8000?pk=AAAA&otp=BBBB&v=1',
      );
      expect(url.host, '192.168.1.42');
      expect(url.port, 8000);
      expect(url.pcPublicKey, 'AAAA');
      expect(url.otp, 'BBBB');
      expect(url.version, 1);
    });

    test('decodes URL-encoded parameters', () {
      // pk = base64 avec / et + URL-encodés
      final url = PairingUrl.parse(
        'linkup://10.0.0.1:8000?pk=g9jJ%2F8SI&otp=abc-def_123&v=1',
      );
      expect(url.pcPublicKey, 'g9jJ/8SI');
      expect(url.otp, 'abc-def_123');
    });

    test('builds Laravel base URI', () {
      final url = PairingUrl.parse(
        'linkup://192.168.1.42:8000?pk=AAAA&otp=BBBB&v=1',
      );
      expect(url.laravelBaseUri.toString(), 'http://192.168.1.42:8000');
      expect(
        url.handshakeUri.toString(),
        'http://192.168.1.42:8000/api/pairing/handshake',
      );
    });

    test('throws on wrong scheme', () {
      expect(
        () => PairingUrl.parse('https://1.2.3.4:8000?pk=A&otp=B&v=1'),
        throwsA(isA<PairingUrlException>()),
      );
    });

    test('throws on missing pk', () {
      expect(
        () => PairingUrl.parse('linkup://1.2.3.4:8000?otp=B&v=1'),
        throwsA(isA<PairingUrlException>()),
      );
    });

    test('throws on missing otp', () {
      expect(
        () => PairingUrl.parse('linkup://1.2.3.4:8000?pk=A&v=1'),
        throwsA(isA<PairingUrlException>()),
      );
    });

    test('throws on unsupported version', () {
      expect(
        () => PairingUrl.parse('linkup://1.2.3.4:8000?pk=A&otp=B&v=99'),
        throwsA(
          isA<PairingUrlException>().having(
            (e) => e.message,
            'message',
            contains('Version'),
          ),
        ),
      );
    });

    test('throws on non-numeric version', () {
      expect(
        () => PairingUrl.parse('linkup://1.2.3.4:8000?pk=A&otp=B&v=foo'),
        throwsA(isA<PairingUrlException>()),
      );
    });

    test('throws on garbage', () {
      expect(
        () => PairingUrl.parse('not a url'),
        throwsA(isA<PairingUrlException>()),
      );
    });

    test('trims whitespace', () {
      final url = PairingUrl.parse(
        '  linkup://1.2.3.4:8000?pk=A&otp=B&v=1  ',
      );
      expect(url.host, '1.2.3.4');
    });
  });
}
