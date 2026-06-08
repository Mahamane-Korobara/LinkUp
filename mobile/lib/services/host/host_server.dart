import 'dart:io';

import '../../config/linkup_ports.dart';
import 'host_router.dart';

/// Serveur HTTP embarqué du Mode Hôte (tél↔tél).
///
/// Un `HttpServer` dart:io unique, lié sur `0.0.0.0:<port bridge>`, qui joue à
/// la fois les rôles agent Laravel et bridge Python pour les téléphones pairs.
/// Le code client mobile reste inchangé : il croit parler à un PC.
///
/// **Survie en arrière-plan** : à lancer depuis un service de premier plan
/// Android (cf. host_foreground.dart) — sinon Android tue le socket. Le serveur
/// lui-même n'en dépend pas (testable sur loopback en pur Dart).
class HostServer {
  final HostRouter router;
  final InternetAddress address;
  final int port;

  HttpServer? _server;

  HostServer({
    required this.router,
    InternetAddress? address,
    this.port = LinkupPorts.bridge,
  }) : address = address ?? InternetAddress.anyIPv4;

  /// Port effectivement ouvert (utile en test quand [port] vaut 0 = éphémère).
  int get boundPort => _server?.port ?? port;

  bool get isRunning => _server != null;

  /// Démarre l'écoute et renvoie le port ouvert. Throw [SocketException] si le
  /// port est déjà pris (à remonter à l'UI : « hébergement déjà actif »).
  Future<int> start() async {
    final server = await HttpServer.bind(address, port);
    _server = server;
    server.listen(_handle, onError: (_) {});
    return server.port;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      await router.dispatch(request);
    } catch (_) {
      // Un handler qui throw ne doit jamais tuer le serveur : on renvoie 500.
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {/* réponse déjà engagée */}
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
