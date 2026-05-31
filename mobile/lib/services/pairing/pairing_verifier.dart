import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'paired_device_store.dart';

/// Vérifie auprès du PC qu'un appairage local est ENCORE valide côté serveur.
///
/// L'empreinte stockée localement ne suffit pas : après un `migrate:fresh` ou
/// une révocation, le PC a oublié le device alors que le tél se croit appairé.
/// On appelle `/api/me` avec le token du device :
///   - 200 → toujours appairé (token valide)  → [PairingValidity.valid]
///   - 401 → appairage périmé (token invalide) → [PairingValidity.stale]
///   - réseau KO / autre → indéterminé          → [PairingValidity.unknown]
enum PairingValidity { valid, stale, unknown }

abstract class PairingVerifier {
  Future<PairingValidity> verify(PairedDevice device);
}

class HttpPairingVerifier implements PairingVerifier {
  final http.Client _http;
  final bool _ownsHttp;
  final Duration timeout;

  HttpPairingVerifier({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 4),
  })  : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  @override
  Future<PairingValidity> verify(PairedDevice device) async {
    final uri = device.baseUri.replace(path: '/api/me');
    try {
      final res = await _http.get(uri, headers: {
        'Accept': 'application/json',
        'X-Device-Id': device.deviceId,
        'Authorization': 'Bearer ${device.token}',
      }).timeout(timeout);

      if (res.statusCode == 200) return PairingValidity.valid;
      if (res.statusCode == 401) return PairingValidity.stale;
      return PairingValidity.unknown;
    } on TimeoutException {
      return PairingValidity.unknown;
    } on SocketException {
      return PairingValidity.unknown;
    } on http.ClientException {
      return PairingValidity.unknown;
    }
  }

  void close() {
    if (_ownsHttp) _http.close();
  }
}
