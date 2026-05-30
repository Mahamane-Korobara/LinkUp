import 'package:flutter/services.dart';

/// Pont Dart vers le `WifiManager.MulticastLock` natif côté Android.
///
/// Sans ce verrou, Android filtre les paquets multicast UDP 5353 reçus en
/// arrière-plan et le scan zeroconf retourne zéro résultat sans erreur.
/// Voir `MainActivity.kt` pour l'implémentation native.
class MulticastLock {
  static const MethodChannel _channel = MethodChannel('linkup/multicast');

  /// Acquiert le verrou multicast. Idempotent (le natif gère la double acquisition).
  /// Renvoie `true` si le verrou est tenu à la sortie.
  static Future<bool> acquire() async {
    try {
      final result = await _channel.invokeMethod<bool>('acquire');
      return result ?? false;
    } on MissingPluginException {
      // En mode test (sans MethodChannel branché) on échoue silencieusement.
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Libère le verrou. Toujours appeler dans `dispose()` du service mDNS.
  static Future<void> release() async {
    try {
      await _channel.invokeMethod<bool>('release');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// Vrai si le verrou est actuellement tenu.
  static Future<bool> isHeld() async {
    try {
      final result = await _channel.invokeMethod<bool>('isHeld');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
