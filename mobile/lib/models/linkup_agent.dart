import '../config/linkup_ports.dart';

/// Représente un agent Linkup détecté sur le LAN (mDNS ou sweep /24).
///
/// La source `mdns` = découvert via zeroconf ; `lanSweep` = trouvé en frappant
/// `/health` sur le sous-réseau (fallback quand le multicast ne passe pas).
class LinkupAgent {
  final String instanceName;
  final String address;
  final int reverbPort;
  final int bridgePort;

  /// Port HTTP de l'agent Laravel, découvert via `/health` ou le TXT mDNS
  /// (`laravel_port`). Évite de coder le port en dur : 8000 en dev, 8770 dans
  /// le bundle PC. Fallback sur [LinkupPorts.laravel] si la découverte est muette.
  final int laravelPort;

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
    this.laravelPort = LinkupPorts.laravel,
    this.agentId,
    this.fingerprint,
    this.version,
    this.hostname,
    this.user,
  });

  /// Étiquette à afficher pour l'humain.
  /// Préfère le nom user (« mahamane »), puis le nom machine
  /// (« mahamane-VivoBook »), puis l'agent_id, puis l'adresse.
  /// Le `subtitleLine` fournit le reste (hostname, IP, version) pour
  /// distinguer deux agents qui auraient le même `user`.
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

  /// URL HTTP `/health` du **bridge Python** (port bridge), pour la simple
  /// vérification de présence du LAN sweep. NB : `/api/agent/info` n'est PAS
  /// servi ici mais par **Laravel** (cf. [agentInfoUri], port différent).
  Uri get bridgeHealthUri => Uri.parse('http://$address:$bridgePort/health');

  /// URL HTTP de l'agent Laravel, pour appeler `/api/agent/info`.
  /// Utilise [laravelPort] (découvert via /health ou mDNS). Un override
  /// optionnel reste possible (ex. saisie manuelle / tests).
  Uri agentInfoUri([int? laravelPortOverride]) =>
      Uri.parse('http://$address:${laravelPortOverride ?? laravelPort}/api/agent/info');

  /// Clé stable pour différencier deux agents dans une liste/dictionnaire.
  String get uniqueKey => agentId ?? '$address:$bridgePort';

  LinkupAgent copyWith({
    int? laravelPort,
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
      laravelPort: laravelPort ?? this.laravelPort,
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
/// - [paired] : agent déjà appairé, reconstitué depuis le stockage local.
enum LinkupAgentSource { mdns, lanSweep, paired }
