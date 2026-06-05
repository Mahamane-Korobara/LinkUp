import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:linkup_mobile/services/pairing/paired_device_store.dart';
import 'package:linkup_mobile/services/preview/preview_client.dart';

const _device = PairedDevice(
  deviceId: 'dev-1',
  host: '192.168.1.42',
  port: 8000,
  token: 'tok',
  pcPublicKey: 'pk',
  pcFingerprint: 'fp',
  pcName: 'PC-Bureau',
);

void main() {
  group('PreviewClient', () {
    test('parses exposed projects and builds the project URL', () async {
      late http.Request seen;
      final mock = MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode({
            'exposed': [
              {'target_port': 5173, 'listen_port': 41234, 'started_at': 0},
            ],
            'scheme': 'https',
            'hosts': ['192.168.1.42'],
            'cert_sha256': 'ab' * 32,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = PreviewClient(httpClient: mock);

      final listing = await client.projects(_device);

      // Appel authentifié sur la bonne route Laravel.
      expect(seen.url.path, '/api/preview/projects');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.headers['X-Device-Id'], 'dev-1');

      expect(listing.projects, hasLength(1));
      expect(listing.projects.first.targetPort, 5173);
      expect(listing.certSha256, 'ab' * 32); // empreinte à épingler

      final uri = client.projectUri(_device, listing, listing.projects.first);
      expect(uri.toString(), 'https://192.168.1.42:41234');
    });

    test('falls back to the paired host when hosts is empty', () async {
      final mock = MockClient((req) async => http.Response(
            jsonEncode({'exposed': [], 'scheme': 'https', 'hosts': []}),
            200,
          ));
      final client = PreviewClient(httpClient: mock);

      final listing = await client.projects(_device);
      const project = PreviewProject(targetPort: 3000, listenPort: 5000);
      final uri = client.projectUri(_device, listing, project);

      expect(uri.host, '192.168.1.42'); // device.host
      expect(uri.port, 5000);
    });

    test('throws a clear message on expired pairing (401)', () async {
      final mock = MockClient((req) async => http.Response('{}', 401));
      final client = PreviewClient(httpClient: mock);

      expect(
        () => client.projects(_device),
        throwsA(isA<PreviewException>()),
      );
    });

    test('CA certificate URL points at the public Laravel route', () {
      final client = PreviewClient();
      expect(
        client.caCertificateUri(_device).toString(),
        'http://192.168.1.42:8000/api/preview/ca.crt',
      );
      client.close();
    });
  });

  group('certMatchesPin', () {
    final der = Uint8List.fromList([1, 2, 3, 4, 5]);

    Future<String> hexOf(Uint8List data) async =>
        (await Sha256().hash(data)).bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();

    test('accepts the cert whose SHA-256 matches the pin', () async {
      expect(await certMatchesPin(der, await hexOf(der)), isTrue);
    });

    test('is case-insensitive on the pinned hex', () async {
      expect(await certMatchesPin(der, (await hexOf(der)).toUpperCase()), isTrue);
    });

    test('rejects a different cert (potential MITM)', () async {
      final other = Uint8List.fromList([9, 9, 9]);
      expect(await certMatchesPin(other, await hexOf(der)), isFalse);
    });

    test('rejects when the pin is null or empty (no fallback to trust-all)',
        () async {
      expect(await certMatchesPin(der, null), isFalse);
      expect(await certMatchesPin(der, ''), isFalse);
    });
  });
}
