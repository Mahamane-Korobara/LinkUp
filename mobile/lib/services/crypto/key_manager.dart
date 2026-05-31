import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Gestionnaire de la paire de clés Ed25519 du téléphone Linkup.
///
/// - Génère une paire au premier appel à `ensureKeyPair()`
/// - Stocke la **seed 32 octets** (base64) dans le secure storage Android
///   (Keystore matériel) sous deux clés : public + seed
/// - Re-dérive la `SimpleKeyPair` depuis la seed à chaque lecture
///
/// S2.J1 — base pour le handshake Noise IK (S2.J3) et la signature des
/// messages broadcast Reverb (S3).
class KeyManager {
  static const String _seedKey = 'linkup.ed25519.seed';
  static const String _publicKey = 'linkup.ed25519.public';

  final FlutterSecureStorage _storage;
  final Ed25519 _algo;

  KeyManager({
    FlutterSecureStorage? storage,
    Ed25519? algo,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _algo = algo ?? Ed25519();

  /// Renvoie la paire de clés, génère + stocke si absente.
  Future<SimpleKeyPair> ensureKeyPair() async {
    final existing = await _loadKeyPair();
    if (existing != null) return existing;
    return _generateAndStore();
  }

  /// Génère une nouvelle paire et l'écrase en stockage. Réservé aux tests
  /// ou à une rotation explicite — sinon préférer ensureKeyPair().
  Future<SimpleKeyPair> generate() async {
    return _generateAndStore();
  }

  /// Clé publique base64 — utilisée dans le QR pairing.
  Future<String> publicKeyBase64() async {
    final pub = await _readPublicKey();
    return base64.encode(pub.bytes);
  }

  /// Signe un message avec la clé privée locale.
  /// Retourne la signature détachée en base64.
  Future<String> sign(List<int> message) async {
    final kp = await ensureKeyPair();
    final signature = await _algo.sign(message, keyPair: kp);
    return base64.encode(signature.bytes);
  }

  /// Vérifie une signature contre une clé publique base64 (signature détachée).
  ///
  /// Réservé S3 : pas encore appelé dans `lib/` (le pairing valide l'identité
  /// du PC par égalité de clé publique, pas par signature). Servira à vérifier
  /// les messages broadcast Reverb signés par le PC. Couvert par les tests.
  Future<bool> verify({
    required List<int> message,
    required String signatureB64,
    required String publicKeyB64,
  }) async {
    try {
      final signature = Signature(
        base64.decode(signatureB64),
        publicKey: SimplePublicKey(
          base64.decode(publicKeyB64),
          type: KeyPairType.ed25519,
        ),
      );
      return _algo.verify(message, signature: signature);
    } on FormatException {
      return false;
    }
  }

  /// Empreinte SHA-256 courte (8 hex chars) de la clé publique du tél.
  ///
  /// Réservé : pas encore appelé dans `lib/` (l'empreinte du tél affichée vient
  /// de la réponse serveur `device_fingerprint`). Gardé pour un affichage local
  /// futur de sa propre empreinte. Couvert par les tests. Même algo que le PC
  /// (`KeyManager::fingerprint` côté Laravel) → valeurs comparables.
  Future<String> fingerprint() async {
    final pub = await _readPublicKey();
    final hash = await Sha256().hash(pub.bytes);
    return hash.bytes
        .sublist(0, 4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Vrai si une paire est déjà stockée.
  Future<bool> exists() async {
    final seed = await _storage.read(key: _seedKey);
    final pub = await _storage.read(key: _publicKey);
    return seed != null && pub != null;
  }

  /// Efface la paire stockée. Utile pour les tests ou un reset complet.
  Future<void> clear() async {
    await _storage.delete(key: _seedKey);
    await _storage.delete(key: _publicKey);
  }

  Future<SimpleKeyPair> _generateAndStore() async {
    final kp = await _algo.newKeyPair();
    final seed = await kp.extractPrivateKeyBytes();
    final pub = await kp.extractPublicKey();
    await _storage.write(key: _seedKey, value: base64.encode(seed));
    await _storage.write(key: _publicKey, value: base64.encode(pub.bytes));
    return kp;
  }

  Future<SimpleKeyPair?> _loadKeyPair() async {
    final seedB64 = await _storage.read(key: _seedKey);
    if (seedB64 == null) return null;
    try {
      final seed = base64.decode(seedB64);
      return _algo.newKeyPairFromSeed(seed);
    } on FormatException {
      return null;
    }
  }

  Future<SimplePublicKey> _readPublicKey() async {
    final kp = await ensureKeyPair();
    return kp.extractPublicKey();
  }
}
