import 'dart:convert';

/// Comparaison de chaînes en **temps constant** (anti-timing oracle).
///
/// Équivalent Dart de `hmac.compare_digest` (Python) / `hash_equals` (PHP) : le
/// temps d'exécution ne dépend pas de la position du premier octet qui diffère,
/// ce qui empêche de reconstituer un token/MAC octet par octet en mesurant le
/// temps de réponse. À utiliser pour TOUTE comparaison de secret (token, OTP,
/// HMAC) — jamais `==`, qui court-circuite au premier octet différent.
bool constantTimeEquals(String a, String b) {
  final ba = utf8.encode(a);
  final bb = utf8.encode(b);
  // La différence de longueur est intégrée au résultat, mais on parcourt quand
  // même la plus longue pour ne pas trahir les tailles par le timing.
  var diff = ba.length ^ bb.length;
  final n = ba.length > bb.length ? ba.length : bb.length;
  for (var i = 0; i < n; i++) {
    final x = i < ba.length ? ba[i] : 0;
    final y = i < bb.length ? bb[i] : 0;
    diff |= x ^ y;
  }
  return diff == 0;
}
