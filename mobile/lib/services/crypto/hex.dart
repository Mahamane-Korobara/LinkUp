/// Encode des octets en hexadécimal minuscule (2 caractères par octet).
///
/// Centralise le `toRadixString(16).padLeft(2, '0')` qui était réimplémenté
/// dans plusieurs services (empreintes de clé, SHA-256 d'un transfert,
/// identifiants/OTP aléatoires).
String hexEncode(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
