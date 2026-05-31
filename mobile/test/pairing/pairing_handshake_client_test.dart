import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/services/crypto/key_manager.dart';
import 'package:linkup_mobile/services/pairing/device_metadata.dart';
import 'package:linkup_mobile/services/pairing/pairing_handshake_client.dart';
import 'package:linkup_mobile/services/pairing/pairing_url.dart';

/// Storage en mémoire pour ne pas toucher au Keystore Android.
class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String?> _data = {};

  _MemoryStorage();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}

PairingUrl _fakeUrl({String pcPub = 'PCKEYBASE64'}) =>
    PairingUrl(host: '1.2.3.4', port: 8000, pcPublicKey: pcPub, otp: 'OTPABC', version: 1);

void main() {
  group('PairingHandshakeClient', () {
    test('returns HandshakeResult on 200 + matching pc_public_key', () async {
      const pcPub = 'PCKEYBASE64';
      final keyManager = KeyManager(storage: _MemoryStorage());

      Map<String, dynamic>? sentBody;
      final mock = MockClient((req) async {
        sentBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'status': 'pending_approval',
            'device_id': 'abc-123',
            'pc_public_key': pcPub,
            'pc_fingerprint': 'deadbeef',
            'pc_name': 'mahamane-VivoBook',
          }),
          200,
        );
      });

      final client = PairingHandshakeClient(
        keyManager: keyManager,
        httpClient: mock,
      );
      final result = await client.handshake(_fakeUrl(pcPub: pcPub));

      expect(result.deviceId, 'abc-123');
      expect(result.isPending, isTrue);
      expect(result.pcFingerprint, 'deadbeef');

      expect(sentBody!['otp'], 'OTPABC');
      expect(sentBody!['signature'], isA<String>());
      expect(sentBody!['tel_public_key'], isA<String>());
    });

    test('sends device metadata fields when provided', () async {
      const pcPub = 'PCKEYBASE64';
      final keyManager = KeyManager(storage: _MemoryStorage());

      Map<String, dynamic>? sentBody;
      final mock = MockClient((req) async {
        sentBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'status': 'pending_approval',
            'device_id': 'abc-123',
            'pc_public_key': pcPub,
            'pc_fingerprint': 'deadbeef',
            'pc_name': 'pc',
          }),
          200,
        );
      });

      final client = PairingHandshakeClient(keyManager: keyManager, httpClient: mock);
      await client.handshake(
        _fakeUrl(pcPub: pcPub),
        metadata: const DeviceMetadata(
          name: 'Pixel 7',
          model: 'Google Pixel 7',
          platform: 'Android',
          osVersion: 'Android 14',
        ),
      );

      expect(sentBody!['device_name'], 'Pixel 7');
      expect(sentBody!['device_model'], 'Google Pixel 7');
      expect(sentBody!['device_platform'], 'Android');
      expect(sentBody!['device_os'], 'Android 14');
    });

    test('omits device metadata fields when not provided', () async {
      const pcPub = 'PCKEYBASE64';
      final keyManager = KeyManager(storage: _MemoryStorage());

      Map<String, dynamic>? sentBody;
      final mock = MockClient((req) async {
        sentBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'status': 'pending_approval',
            'device_id': 'abc-123',
            'pc_public_key': pcPub,
            'pc_fingerprint': 'deadbeef',
            'pc_name': 'pc',
          }),
          200,
        );
      });

      final client = PairingHandshakeClient(keyManager: keyManager, httpClient: mock);
      await client.handshake(_fakeUrl(pcPub: pcPub));

      expect(sentBody!.containsKey('device_model'), isFalse);
      expect(sentBody!.containsKey('device_name'), isFalse);
    });

    test('throws HandshakeRejected on 422 with reason_code', () async {
      final keyManager = KeyManager(storage: _MemoryStorage());
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({'reason_code': 'otp_invalid', 'message': 'OTP expiré'}),
          422,
        );
      });

      final client = PairingHandshakeClient(
        keyManager: keyManager,
        httpClient: mock,
      );

      try {
        await client.handshake(_fakeUrl());
        fail('should throw');
      } on HandshakeRejected catch (e) {
        expect(e.reasonCode, 'otp_invalid');
        expect(e.message, contains('expiré'));
      }
    });

    test('throws HandshakeRejected on pc_pubkey mismatch (anti-MITM)', () async {
      final keyManager = KeyManager(storage: _MemoryStorage());
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'status': 'pending_approval',
            'device_id': 'x',
            'pc_public_key': 'ATTACKER_KEY',
            'pc_fingerprint': '0',
            'pc_name': 'fake',
          }),
          200,
        );
      });

      final client = PairingHandshakeClient(
        keyManager: keyManager,
        httpClient: mock,
      );

      try {
        await client.handshake(_fakeUrl(pcPub: 'LEGIT_KEY'));
        fail('should throw');
      } on HandshakeRejected catch (e) {
        expect(e.reasonCode, 'pc_pubkey_mismatch');
      }
    });

    test('throws HandshakeNetworkException on non-200/422', () async {
      final keyManager = KeyManager(storage: _MemoryStorage());
      final mock = MockClient((req) async => http.Response('boom', 500));

      final client = PairingHandshakeClient(
        keyManager: keyManager,
        httpClient: mock,
      );

      try {
        await client.handshake(_fakeUrl());
        fail('should throw');
      } on HandshakeNetworkException catch (e) {
        expect(e.message, contains('500'));
      }
    });

    test('throws HandshakeNetworkException on garbage JSON', () async {
      final keyManager = KeyManager(storage: _MemoryStorage());
      final mock = MockClient((req) async => http.Response('not-json', 200));

      final client = PairingHandshakeClient(
        keyManager: keyManager,
        httpClient: mock,
      );

      expect(
        () => client.handshake(_fakeUrl()),
        throwsA(isA<HandshakeNetworkException>()),
      );
    });
  });
}
