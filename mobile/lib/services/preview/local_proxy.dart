import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Proxy local on-device pour le Dev Preview (S14, Lot G).
///
/// **Pourquoi.** Le WebView Android n'invoque PAS le callback de pinning
/// (`onReceivedServerTrustAuthRequest`) pour les requêtes `fetch`/`XHR` : tout
/// appel AJAX vers le proxy HTTPS auto-signé du PC échoue en
/// `ERR_CERT_AUTHORITY_INVALID` (net_error -202). Donc la com front↔back est
/// cassée même si la page se charge.
///
/// **Solution.** On écoute sur `127.0.0.1` (sur le téléphone) et on relaie les
/// octets bruts vers le bridge du PC en **TLS** (en épinglant son certificat). Le
/// WebView charge alors `http://localhost:<port>` :
/// - `localhost` est un **contexte sécurisé** (exemption localhost) → caméra /
///   géoloc / service workers continuent de marcher **sans HTTPS** ;
/// - c'est du **cleartext** côté WebView → plus aucun rejet de certificat → les
///   `fetch`/`XHR`/`WebSocket` passent ;
/// - **zéro install CA**. Le cleartext ne quitte jamais le téléphone ; la liaison
///   LAN reste chiffrée (TLS) et le pinning (anti-MITM) est conservé, déplacé ici.
class LocalPreviewProxy {
  /// IP LAN du PC (hôte du bridge), ex. `192.168.1.20`.
  final String pcHost;

  /// Port d'écoute du proxy HTTPS du projet sur le PC (le `listen_port`).
  final int targetListenPort;

  /// Empreinte SHA-256 (hex) attendue du cert serveur. Null → refus (pas de pin).
  final String? certSha256;

  /// Port d'écoute LOCAL préféré (sur 127.0.0.1 du téléphone) = le port d'origine
  /// du serveur de dev (ex. 3001). En écoutant sur le MÊME port, la WebView charge
  /// `http://127.0.0.1:3001` ≈ `http://localhost:3001` du PC → Next dev reconnaît
  /// son origine et accepte le WebSocket HMR (sinon refus → hydratation gelée). 0
  /// laisse l'OS choisir (repli si le port est déjà pris sur le téléphone).
  final int preferredListenPort;

  /// Appelé une fois si la liaison TLS au PC est refusée (cert non conforme ou PC
  /// injoignable) — pour afficher une erreur claire à l'écran.
  final void Function(String message)? onUpstreamFailure;

  ServerSocket? _server;
  bool _failureReported = false;
  int _connSeq = 0;

  LocalPreviewProxy({
    required this.pcHost,
    required this.targetListenPort,
    required this.certSha256,
    this.preferredListenPort = 0,
    this.onUpstreamFailure,
  });

  /// Démarre l'écoute locale et renvoie le port effectivement ouvert sur 127.0.0.1.
  /// Tente d'abord [preferredListenPort] (origine identique au PC) ; s'il est déjà
  /// pris sur le téléphone, retombe sur un port libre choisi par l'OS.
  Future<int> start() async {
    ServerSocket server;
    try {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, preferredListenPort);
    } on SocketException {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    }
    _server = server;
    server.listen(_handleClient, onError: (_) {});
    return server.port;
  }

  Future<void> _handleClient(Socket client) async {
    // [perf] chrono temporaire : localise les 30-60s (handshake ? attente avant
    // requête ? TTFB tunnel ?). À retirer une fois le coupant identifié.
    final id = ++_connSeq;
    final sw = Stopwatch()..start();
    SecureSocket upstream;
    try {
      upstream = await SecureSocket.connect(
        pcHost,
        targetListenPort,
        onBadCertificate: _certMatchesPin,
        timeout: const Duration(seconds: 10),
      );
    } catch (e) {
      client.destroy();
      if (!_failureReported) {
        _failureReported = true;
        onUpstreamFailure?.call(e.toString());
      }
      return;
    }
    final connectMs = sw.elapsedMilliseconds;
    debugPrint('[perf:$preferredListenPort#$id] TLS connecté en ${connectMs}ms');
    // TCP_NODELAY des deux côtés : évite que Nagle bufferise les petits paquets.
    _noDelay(client);
    _noDelay(upstream);

    var reqAt = -1;
    var respAt = -1;
    var reqLine = '(aucune requête)';
    var hasContentLength = false;
    var respBytes = 0;
    // tél → PC : 1ᵉʳ octet = moment où le navigateur envoie enfin la requête.
    client.listen(
      (data) {
        if (reqAt < 0) {
          reqAt = sw.elapsedMilliseconds;
          // 1ʳᵉ ligne = "METHOD /chemin HTTP/1.1" → identifie l'endpoint.
          final head = String.fromCharCodes(data.take(200));
          reqLine = head.split('\r\n').first;
          debugPrint('[perf:$preferredListenPort#$id] → $reqLine (envoyée à +${reqAt}ms)');
        }
        try {
          upstream.add(data);
        } catch (_) {
          client.destroy();
        }
      },
      onError: (_) => upstream.destroy(),
      onDone: () {
        debugPrint('[perf:$preferredListenPort#$id] ⟵ NAVIGATEUR ferme à +${sw.elapsedMilliseconds}ms '
            '[$reqLine] (resp ${respBytes}o, content-length=$hasContentLength)');
        upstream.destroy();
      },
      cancelOnError: true,
    );
    // PC → tél : 1ᵉʳ octet = réponse ; TTFB = depuis l'envoi de la requête.
    upstream.listen(
      (data) {
        respBytes += data.length;
        if (respAt < 0) {
          respAt = sw.elapsedMilliseconds;
          final head = String.fromCharCodes(data.take(400)).toLowerCase();
          hasContentLength = head.contains('content-length:');
          final status = String.fromCharCodes(data.take(200)).split('\r\n').first;
          debugPrint('[perf:$preferredListenPort#$id] ← $status à +${respAt}ms '
              '(TTFB=${reqAt < 0 ? "?" : respAt - reqAt}ms, content-length=$hasContentLength)');
        }
        try {
          client.add(data);
        } catch (_) {
          upstream.destroy();
        }
      },
      onError: (_) => client.destroy(),
      onDone: () {
        debugPrint('[perf:$preferredListenPort#$id] ⟸ PHP/BACK ferme à +${sw.elapsedMilliseconds}ms '
            '[$reqLine] (resp ${respBytes}o)');
        client.destroy();
      },
      cancelOnError: true,
    );
  }

  void _noDelay(Socket s) {
    try {
      s.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {
      // Best-effort : TCP_NODELAY n'est qu'une optimisation de latence ; si la
      // plateforme le refuse, le proxy fonctionne quand même.
    }
  }

  /// Épingle le cert serveur du bridge (SHA-256 du DER). Renvoyé à
  /// `SecureSocket.onBadCertificate` → doit être SYNCHRONE (d'où `package:crypto`).
  bool _certMatchesPin(X509Certificate cert) {
    final pin = certSha256;
    if (pin == null || pin.isEmpty) return false;
    final actual = sha256.convert(cert.der).toString();
    return actual.toLowerCase() == pin.toLowerCase();
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }
}
