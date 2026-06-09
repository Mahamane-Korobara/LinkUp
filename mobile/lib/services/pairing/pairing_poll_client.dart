import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../crypto/key_manager.dart';

/// Statut renvoyé par le PC lors d'une poll de pairing.
enum PollStatus { pending, approved, rejected, unknown }

PollStatus _parseStatus(String? raw) => switch (raw) {
      'pending' => PollStatus.pending,
      'approved' => PollStatus.approved,
      'rejected' => PollStatus.rejected,
      _ => PollStatus.unknown,
    };

/// Résultat d'une poll. [token] n'est présent qu'au tout premier passage en
/// `approved` (le PC ne le livre qu'une fois).
class PollResult {
  final PollStatus status;
  final String? token;

  const PollResult(this.status, {this.token});

  bool get isTerminal =>
      status == PollStatus.approved || status == PollStatus.rejected;
}

/// Erreur réseau / transport pendant la poll.
class PollNetworkException implements Exception {
  final String message;
  const PollNetworkException(this.message);
  @override
  String toString() => 'PollNetworkException: $message';
}

/// Interroge le PC (`POST /api/pairing/poll`) pour savoir si le device a été
/// approuvé, et récupérer son token persistant.
///
/// La requête est authentifiée : le tel signe son `device_id` avec sa clé
/// privée Ed25519, le PC vérifie la signature contre la clé publique
/// enregistrée. Personne d'autre ne peut sonder / voler le token du device.
class PairingPollClient {
  final KeyManager _keyManager;
  final http.Client _http;
  final bool _ownsHttp;

  /// Intervalle entre deux polls dans [waitForResolution]. Mis à zéro dans les
  /// tests pour ne pas attendre.
  final Duration pollInterval;

  /// Timeout d'une requête HTTP individuelle.
  final Duration requestTimeout;

  PairingPollClient({
    required KeyManager keyManager,
    http.Client? httpClient,
    this.pollInterval = const Duration(seconds: 2),
    this.requestTimeout = const Duration(seconds: 5),
  })  : _keyManager = keyManager,
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  /// Une seule poll. Throws [PollNetworkException] en cas d'échec transport.
  Future<PollResult> pollOnce(Uri baseUri, String deviceId) async {
    final signature = await _keyManager.sign(utf8.encode(deviceId));

    final http.Response response;
    try {
      response = await _http
          .post(
            baseUri.replace(path: '/api/pairing/poll'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'device_id': deviceId, 'signature': signature}),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const PollNetworkException('Pas de réponse du PC dans le délai imparti.');
    } on SocketException catch (e) {
      throw PollNetworkException('Connexion refusée : ${e.message}');
    } on http.ClientException catch (e) {
      throw PollNetworkException('Erreur HTTP : ${e.message}');
    }

    if (response.statusCode == 403) {
      throw const PollNetworkException('Signature refusée par le PC.');
    }
    // 404 : le device n'existe plus côté PC. Pendant l'attente d'approbation,
    // ça ne peut vouloir dire qu'une chose — le PC a refusé/supprimé l'appareil
    // (le handshake l'avait créé juste avant de commencer à poller). On le
    // traite comme un refus terminal plutôt que de retenter jusqu'au timeout.
    if (response.statusCode == 404) {
      return const PollResult(PollStatus.rejected);
    }
    if (response.statusCode != 200) {
      throw PollNetworkException('PC a répondu ${response.statusCode}.');
    }

    final Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const PollNetworkException('Réponse JSON invalide du PC.');
      }
      body = decoded;
    } on FormatException {
      throw const PollNetworkException('Réponse JSON invalide du PC.');
    }

    return PollResult(
      _parseStatus(body['status'] as String?),
      token: body['token'] as String?,
    );
  }

  /// Poll en boucle jusqu'à un statut terminal (approved / rejected) ou
  /// expiration de [timeout]. Les erreurs réseau transitoires sont retentées
  /// tant que le timeout n'est pas atteint.
  Future<PollResult> waitForResolution(
    Uri baseUri,
    String deviceId, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (true) {
      try {
        final result = await pollOnce(baseUri, deviceId);
        if (result.isTerminal) return result;
      } on PollNetworkException {
        // transitoire : on retente jusqu'au deadline
        if (DateTime.now().isAfter(deadline)) rethrow;
      }

      if (DateTime.now().isAfter(deadline)) {
        throw const PollNetworkException(
          'Toujours en attente d\'approbation après le délai imparti.',
        );
      }
      if (pollInterval > Duration.zero) {
        await Future<void>.delayed(pollInterval);
      }
    }
  }

  void close() {
    if (_ownsHttp) _http.close();
  }
}
