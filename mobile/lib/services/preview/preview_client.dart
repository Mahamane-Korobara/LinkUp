import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import '../crypto/hex.dart';
import '../pairing/paired_device_store.dart';

/// Vrai si le cert feuille présenté (DER) correspond à l'empreinte épinglée.
///
/// C'est le cœur sécurité du Dev Preview in-app : la WebView n'accepte le HTTPS
/// que si le SHA-256 du cert serveur égale celui que le bridge a annoncé via le
/// canal de contrôle token-auth → confiance sans installer la CA dans l'OS, et
/// bien plus sûr qu'un « accepter tout » (qui laisserait passer un MITM).
/// Comparaison hex insensible à la casse. Fonction pure → testable sans WebView.
Future<bool> certMatchesPin(Uint8List leafDer, String? pinnedHex) async {
  if (pinnedHex == null || pinnedHex.isEmpty) return false;
  final digest = await Sha256().hash(leafDer);
  final actual = hexEncode(digest.bytes);
  return actual.toLowerCase() == pinnedHex.toLowerCase();
}

/// Erreur Dev Preview affichable.
class PreviewException implements Exception {
  final String message;
  const PreviewException(this.message);
  @override
  String toString() => 'PreviewException: $message';
}

/// Un projet de dev exposé par le PC (un proxy HTTPS écoute sur `listenPort`).
class PreviewProject {
  /// Port d'origine du serveur de dev sur le PC (ex. 5173) — pour l'affichage.
  final int targetPort;

  /// Port d'écoute du proxy LAN à joindre depuis le tél.
  final int listenPort;

  const PreviewProject({required this.targetPort, required this.listenPort});

  factory PreviewProject.fromJson(Map<String, dynamic> j) => PreviewProject(
        targetPort: (j['target_port'] as num?)?.toInt() ?? 0,
        listenPort: (j['listen_port'] as num?)?.toInt() ?? 0,
      );
}

/// Réponse de `/api/preview/projects` : les projets + de quoi bâtir leurs URLs.
class PreviewListing {
  final List<PreviewProject> projects;
  final String scheme; // 'https'
  final List<String> hosts; // IP LAN du PC

  /// SHA-256 (hex) du cert serveur du bridge, à épingler par la WebView in-app.
  /// Null si le PC est sur une version antérieure → repli sur la voie navigateur.
  final String? certSha256;

  const PreviewListing({
    required this.projects,
    required this.scheme,
    required this.hosts,
    this.certSha256,
  });
}

/// Client Dev Preview (S14) : liste les projets exposés depuis le dashboard PC
/// et construit les URLs à ouvrir dans le navigateur du tél.
class PreviewClient {
  final http.Client _http;
  final bool _ownsHttp;
  final Duration requestTimeout;

  PreviewClient({
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 10),
  })  : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  /// Projets actuellement exposés par le PC. Throws [PreviewException].
  Future<PreviewListing> projects(PairedDevice device) async {
    final res = await _get(device, '/api/preview/projects');
    if (res.statusCode == 401) {
      throw const PreviewException('Appairage expiré : re-scanne le QR.');
    }
    if (res.statusCode != 200) {
      throw PreviewException('Le PC a répondu ${res.statusCode}.');
    }
    final data = _decode(res.body);
    final list = (data['exposed'] as List?) ?? const [];
    return PreviewListing(
      projects: list
          .map((e) => PreviewProject.fromJson(e as Map<String, dynamic>))
          .toList(),
      scheme: data['scheme'] as String? ?? 'https',
      hosts: ((data['hosts'] as List?) ?? const []).map((e) => e.toString()).toList(),
      certSha256: data['cert_sha256'] as String?,
    );
  }

  /// URL du projet à ouvrir dans le navigateur (`https://<host>:<listen_port>`).
  /// `host` = IP LAN renvoyée par le PC, repli sur l'hôte de l'appairage.
  Uri projectUri(PairedDevice device, PreviewListing listing, PreviewProject p) {
    final host = listing.hosts.isNotEmpty ? listing.hosts.first : device.host;
    return Uri(scheme: listing.scheme, host: host, port: p.listenPort);
  }

  /// URL du certificat de la CA Linkup, à ouvrir une fois pour l'installer.
  Uri caCertificateUri(PairedDevice device) =>
      device.baseUri.replace(path: '/api/preview/ca.crt');

  // ----------------------------------------------------------------- helpers

  Future<http.Response> _get(PairedDevice device, String path) async {
    try {
      return await _http
          .get(device.baseUri.replace(path: path), headers: _headers(device))
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const PreviewException('Pas de réponse du PC.');
    } on SocketException catch (e) {
      throw PreviewException('Connexion refusée : ${e.message}');
    }
  }

  Map<String, String> _headers(PairedDevice device) => {
        'Accept': 'application/json',
        'X-Device-Id': device.deviceId,
        'Authorization': 'Bearer ${device.token}',
      };

  Map<String, dynamic> _decode(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const PreviewException('Réponse JSON inattendue.');
    }
    return decoded;
  }

  void close() {
    if (_ownsHttp) _http.close();
  }
}
