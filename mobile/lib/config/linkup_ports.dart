/// Ports utilisés par les composants Linkup côté PC.
///
/// Centralisés ici pour éviter la duplication des magic numbers dans le code.
/// Si tu changes un port côté PC (bridge `.env` ou Laravel), modifie aussi la
/// constante correspondante ici.
abstract class LinkupPorts {
  /// Port du bridge Python FastAPI (`/health`, `/mdns/*`).
  static const int bridge = 8765;

  /// Port du serveur Reverb (WebSocket Pusher).
  /// Annoncé dans le SRV mDNS.
  static const int reverb = 8080;

  /// Port HTTP de l'agent Laravel (`/api/*`).
  /// Pas dans l'annonce mDNS — convention `0.0.0.0:8000` en dev.
  static const int laravel = 8000;
}
