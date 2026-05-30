import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/services/crypto/key_manager.dart';

/// FlutterSecureStorage fake in-memory pour tests purs Dart.
/// (Le vrai backend Keystore n'est pas disponible sans plateforme Android.)
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
  }) async {
    return _data[key];
  }

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

KeyManager _make() => KeyManager(storage: _MemoryStorage());

void main() {
  group('KeyManager Ed25519', () {
    test('generates and stores a keypair on first call', () async {
      final km = _make();
      expect(await km.exists(), isFalse);

      await km.ensureKeyPair();
      expect(await km.exists(), isTrue);
    });

    test('returns the SAME keypair across calls (persistence)', () async {
      final km = _make();
      final pub1 = await km.publicKeyBase64();
      final pub2 = await km.publicKeyBase64();
      expect(pub1, equals(pub2));
    });

    test('publicKeyBase64 produces 32 raw bytes (Ed25519 spec)', () async {
      final km = _make();
      final b64 = await km.publicKeyBase64();
      final bytes = base64.decode(b64);
      expect(bytes.length, 32);
    });

    test('generates 100 unique keypairs without collision', () async {
      final publics = <String>{};
      for (int i = 0; i < 100; i++) {
        final km = _make();
        publics.add(await km.publicKeyBase64());
      }
      expect(publics.length, 100);
    });

    test('signs a message and verifies its own signature', () async {
      final km = _make();
      final message = utf8.encode('hello-linkup');
      final sig = await km.sign(message);

      final ok = await km.verify(
        message: message,
        signatureB64: sig,
        publicKeyB64: await km.publicKeyBase64(),
      );
      expect(ok, isTrue);
    });

    test('rejects a tampered message', () async {
      final km = _make();
      final sig = await km.sign(utf8.encode('original'));

      final ok = await km.verify(
        message: utf8.encode('tampered'),
        signatureB64: sig,
        publicKeyB64: await km.publicKeyBase64(),
      );
      expect(ok, isFalse);
    });

    test('rejects a signature from another keypair', () async {
      final alice = _make();
      final bob = _make();

      final sig = await alice.sign(utf8.encode('hello'));
      final ok = await bob.verify(
        message: utf8.encode('hello'),
        signatureB64: sig,
        publicKeyB64: await bob.publicKeyBase64(),
      );
      expect(ok, isFalse);
    });

    test('produces a stable 8-char hex fingerprint', () async {
      final km = _make();
      final fp1 = await km.fingerprint();
      final fp2 = await km.fingerprint();

      expect(fp1, equals(fp2));
      expect(fp1.length, 8);
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(fp1), isTrue);
    });

    test('clear() removes the keypair from storage', () async {
      final km = _make();
      await km.ensureKeyPair();
      expect(await km.exists(), isTrue);

      await km.clear();
      expect(await km.exists(), isFalse);
    });

    test('generate() rotates the keypair', () async {
      final km = _make();
      final pub1 = await km.publicKeyBase64();
      await km.generate();
      final pub2 = await km.publicKeyBase64();
      expect(pub2, isNot(equals(pub1)));
    });
  });
}
