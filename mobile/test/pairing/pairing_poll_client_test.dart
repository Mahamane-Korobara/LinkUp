import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/services/crypto/key_manager.dart';
import 'package:linkup_mobile/services/pairing/pairing_poll_client.dart';

/// Storage en mémoire pour ne pas toucher au Keystore Android.
class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String?> _data = {};

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

final _baseUri = Uri.parse('http://1.2.3.4:8000');

void main() {
  group('PairingPollClient', () {
    test('pollOnce returns pending', () async {
      final keyManager = KeyManager(storage: _MemoryStorage());
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'status': 'pending'}), 200));

      final client = PairingPollClient(keyManager: keyManager, httpClient: mock);
      final result = await client.pollOnce(_baseUri, 'dev-1');

      expect(result.status, PollStatus.pending);
      expect(result.token, isNull);
      expect(result.isTerminal, isFalse);
    });

    test('pollOnce returns approved with token + signs the device_id', () async {
      final keyManager = KeyManager(storage: _MemoryStorage());
      Map<String, dynamic>? sent;
      final mock = MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'status': 'approved', 'token': 'secret-token'}),
          200,
        );
      });

      final client = PairingPollClient(keyManager: keyManager, httpClient: mock);
      final result = await client.pollOnce(_baseUri, 'dev-42');

      expect(result.status, PollStatus.approved);
      expect(result.token, 'secret-token');
      expect(result.isTerminal, isTrue);
      expect(sent!['device_id'], 'dev-42');
      expect(sent!['signature'], isA<String>());
    });

    test('pollOnce throws on 403 (forged signature)', () async {
      final keyManager = KeyManager(storage: _MemoryStorage());
      final mock = MockClient((req) async => http.Response('', 403));

      final client = PairingPollClient(keyManager: keyManager, httpClient: mock);

      expect(
        () => client.pollOnce(_baseUri, 'dev-1'),
        throwsA(isA<PollNetworkException>()),
      );
    });

    test('pollOnce treats 404 as a terminal rejection', () async {
      // Le device n'existe plus côté PC = il a été refusé/supprimé pendant
      // l'attente. C'est un refus, pas une erreur réseau à retenter.
      final keyManager = KeyManager(storage: _MemoryStorage());
      final mock = MockClient((req) async => http.Response('', 404));

      final client = PairingPollClient(keyManager: keyManager, httpClient: mock);
      final result = await client.pollOnce(_baseUri, 'dev-1');

      expect(result.status, PollStatus.rejected);
      expect(result.isTerminal, isTrue);
    });

    test('waitForResolution polls until approved', () async {
      final keyManager = KeyManager(storage: _MemoryStorage());
      var calls = 0;
      final mock = MockClient((req) async {
        calls++;
        final status = calls < 3 ? 'pending' : 'approved';
        return http.Response(
          jsonEncode({'status': status, if (status == 'approved') 'token': 't'}),
          200,
        );
      });

      final client = PairingPollClient(
        keyManager: keyManager,
        httpClient: mock,
        pollInterval: Duration.zero,
      );
      final result = await client.waitForResolution(_baseUri, 'dev-1');

      expect(result.status, PollStatus.approved);
      expect(result.token, 't');
      expect(calls, 3);
    });

    test('waitForResolution returns rejected terminal', () async {
      final keyManager = KeyManager(storage: _MemoryStorage());
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'status': 'rejected'}), 200));

      final client = PairingPollClient(
        keyManager: keyManager,
        httpClient: mock,
        pollInterval: Duration.zero,
      );
      final result = await client.waitForResolution(_baseUri, 'dev-1');

      expect(result.status, PollStatus.rejected);
    });

    test('waitForResolution times out if never approved', () async {
      final keyManager = KeyManager(storage: _MemoryStorage());
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'status': 'pending'}), 200));

      final client = PairingPollClient(
        keyManager: keyManager,
        httpClient: mock,
        pollInterval: Duration.zero,
      );

      expect(
        () => client.waitForResolution(
          _baseUri,
          'dev-1',
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<PollNetworkException>()),
      );
    });
  });
}
