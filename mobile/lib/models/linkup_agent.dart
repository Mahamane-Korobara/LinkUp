import '../config/linkup_ports.dart';

/// Représente un agent Linkup détecté sur le LAN ou saisi manuellement.
///
/// La source `mdns` signifie que l'agent a été découvert via zeroconf.
/// La source `manual` signifie que l'utilisateur a saisi son IP à la main
/// (fallback T1.17 quand le multicast ne passe pas).
class LinkupAgent {
  final String instanceName;
  final String address;
  final int reverbPort;
  final int bridgePort;
  final String? agentId;
  final String? fingerprint;
  final String? version;

  /// Nom de la machine côté PC, nettoyé (« mahamane-VivoBook » sans `.local.`).
  /// Vient soit du TXT mDNS, soit de la réponse `/health` du bridge.
  final String? hostname;

  /// Nom d'utilisateur connecté côté PC (« mahamane »).
  /// Vient du JSON `/health` (le LAN sweep).
  final String? user;

  final LinkupAgentSource source;

  const LinkupAgent({
    required this.instanceName,
    required this.address,
    required this.reverbPort,
    required this.bridgePort,
    required this.source,
    this.agentId,
    this.fingerprint,
    this.version,
    this.hostname,
    this.user,
  });

  /// Étiquette à afficher pour l'humain.
  /// Préfère le nom user (« mahamane »), puis le nom machine
  /// (« mahamane-VivoBook »), puis l'agent_id, puis l'adresse.
  String get displayName {
    final u = user?.trim();
    if (u != null && u.isNotEmpty && u != 'unknown') return u;
    final h = hostname?.trim();
    if (h != null && h.isNotEmpty) return h;
    return agentId ?? address;
  }

  /// Sous-titre formaté pour le `ListTile` : `hostname • ip:port • vX.Y.Z`.
  /// Calculé une fois par instance (constructeur const = même résultat à
  /// chaque rebuild de l'item).
  String get subtitleLine {
    final parts = <String>[];
    if (hostname != null && hostname != displayName) parts.add(hostname!);
    parts.add('$address:$bridgePort');
    if (version != null) parts.add('v$version');
    return parts.join('  •  ');
  }

  /// URL HTTP du bridge Python, utilisée pour `/health` et `/api/agent/info`
  /// (le bridge expose les deux ; Laravel parle sur un port différent, ici on
  /// vise le bridge directement pour la vérification de présence).
  Uri get bridgeHealthUri => Uri.parse('http://$address:$bridgePort/health');

  /// URL HTTP de l'agent Laravel, pour appeler `/api/agent/info`.
  /// Par convention Linkup, Laravel écoute sur `LinkupPorts.laravel` en dev — le
  /// port Reverb annoncé en mDNS n'est PAS le port HTTP métier, donc on ne peut
  /// pas le déduire de l'annonce.
  Uri agentInfoUri({int laravelPort = LinkupPorts.laravel}) =>
      Uri.parse('http://$address:$laravelPort/api/agent/info');

  /// Clé stable pour différencier deux agents dans une liste/dictionnaire.
  String get uniqueKey => agentId ?? '$address:$bridgePort';

  LinkupAgent copyWith({
    String? agentId,
    String? fingerprint,
    String? version,
    String? hostname,
    String? user,
  }) {
    return LinkupAgent(
      instanceName: instanceName,
      address: address,
      reverbPort: reverbPort,
      bridgePort: bridgePort,
      source: source,
      agentId: agentId ?? this.agentId,
      fingerprint: fingerprint ?? this.fingerprint,
      version: version ?? this.version,
      hostname: hostname ?? this.hostname,
      user: user ?? this.user,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkupAgent && other.uniqueKey == uniqueKey;

  @override
  int get hashCode => uniqueKey.hashCode;

  @override
  String toString() => 'LinkupAgent($uniqueKey, source=${source.name})';
}

/// D'où vient un agent dans la liste de l'app.
///
/// - [mdns] : annonce zeroconf reçue (TXT record SRV+TXT+A).
/// - [lanSweep] : trouvé en frappant `/health` sur le sous-réseau /24.
///   Utile quand le multicast est bloqué (hotspot, Wi-Fi public).
/// - [manual] : saisi par l'utilisateur dans le dialog IP.
enum LinkupAgentSource { mdns, lanSweep, manual }
