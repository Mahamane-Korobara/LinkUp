/// Représente un agent Linkup détecté sur le LAN ou saisi manuellement.
///
/// La source `mdns` signifie que l'agent a été découvert via zeroconf.
/// La source `manual` signifie que l'utilisateur a saisi son IP à la main
/// (fallback T1.17 quand le multicast ne passe pas).
class LinkupAgent {
  final String instanceName;
  final String host;
  final String address;
  final int reverbPort;
  final int bridgePort;
  final String? agentId;
  final String? fingerprint;
  final String? version;
  final String? hostname;
  final String? user;
  final LinkupAgentSource source;

  const LinkupAgent({
    required this.instanceName,
    required this.host,
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

  /// URL HTTP du bridge Python, utilisée pour `/health` et `/api/agent/info`
  /// (le bridge expose les deux ; Laravel parle sur un port différent, ici on
  /// vise le bridge directement pour la vérification de présence).
  Uri get bridgeHealthUri => Uri.parse('http://$address:$bridgePort/health');

  /// URL HTTP de l'agent Laravel, pour appeler `/api/agent/info`.
  /// Par convention Linkup, Laravel écoute sur 8000 en dev — le port
  /// Reverb annoncé en mDNS n'est PAS le port HTTP métier, donc on ne peut
  /// pas le déduire de l'annonce. On garde 8000 par défaut.
  Uri agentInfoUri({int laravelPort = 8000}) =>
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
      host: host,
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
  String toString() =>
      'LinkupAgent($uniqueKey, $address:$bridgePort, source=$source)';
}

enum LinkupAgentSource { mdns, manual }
