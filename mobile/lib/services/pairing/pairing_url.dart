/// Représente une URL de pairing `linkup://...` parsée.
///
/// Format attendu (cf. CDC + PairingService Laravel) :
/// `linkup://<ip>:<port>?pk=<base64-urlencoded>&otp=<base64url-urlencoded>&v=1`
class PairingUrl {
  final String host;
  final int port;
  final String pcPublicKey;
  final String otp;
  final int version;

  const PairingUrl({
    required this.host,
    required this.port,
    required this.pcPublicKey,
    required this.otp,
    required this.version,
  });

  /// Parse une chaîne `linkup://...` ou throw [PairingUrlException] si invalide.
  factory PairingUrl.parse(String raw) {
    final Uri uri;
    try {
      uri = Uri.parse(raw.trim());
    } on FormatException catch (e) {
      throw PairingUrlException('URL malformée : ${e.message}');
    }

    if (uri.scheme != 'linkup') {
      throw PairingUrlException(
        'Schéma incorrect : "${uri.scheme}" (attendu "linkup")',
      );
    }
    if (uri.host.isEmpty) {
      throw PairingUrlException('Host vide dans l\'URL');
    }
    if (uri.port <= 0 || uri.port > 65535) {
      throw PairingUrlException('Port invalide : ${uri.port}');
    }

    final pk = uri.queryParameters['pk'];
    final otp = uri.queryParameters['otp'];
    final v = uri.queryParameters['v'];

    if (pk == null || pk.isEmpty) {
      throw PairingUrlException('Paramètre "pk" manquant');
    }
    if (otp == null || otp.isEmpty) {
      throw PairingUrlException('Paramètre "otp" manquant');
    }
    if (v == null || v.isEmpty) {
      throw PairingUrlException('Paramètre "v" manquant');
    }

    final version = int.tryParse(v);
    if (version == null) {
      throw PairingUrlException('Version non numérique : "$v"');
    }
    if (version != 1) {
      throw PairingUrlException(
        'Version $version non supportée (attendu 1)',
      );
    }

    return PairingUrl(
      host: uri.host,
      port: uri.port,
      pcPublicKey: pk,
      otp: otp,
      version: version,
    );
  }

  /// URL HTTP de base pour appeler Laravel sur ce PC.
  Uri get laravelBaseUri => Uri.parse('http://$host:$port');

  /// URL complète de l'endpoint handshake.
  Uri get handshakeUri => laravelBaseUri.replace(path: '/api/pairing/handshake');

  @override
  String toString() =>
      'PairingUrl(host: $host, port: $port, version: $version)';
}

class PairingUrlException implements Exception {
  final String message;
  const PairingUrlException(this.message);
  @override
  String toString() => 'PairingUrlException: $message';
}
