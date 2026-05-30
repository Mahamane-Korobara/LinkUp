// Validation des entrées du dialog manuel (T1.17).
//
// Extraits ici pour être unit-testables sans monter le widget. Le picker
// les utilise comme `validator:` de ses `TextFormField`.

/// IPv4 stricte : 0-255 sur chaque octet, 4 octets séparés par des points.
final ipv4Regex = RegExp(
  r'^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)'
  r'(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$',
);

/// Hostname mDNS strict : `nom.local` uniquement (le suffixe est obligatoire).
///
/// Sans `.local`, un nom court comme `pc` part en résolution DNS publique :
/// timeout long, ou réponse NXDOMAIN interceptée par le résolveur du
/// fournisseur d'accès (page de capture).
final hostnameRegex = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}\.local$');

/// Valide une adresse IPv4 ou un hostname mDNS `.local`.
/// Retourne `null` si valide, sinon un message d'erreur affichable.
String? validateAddress(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Adresse requise';
  if (!ipv4Regex.hasMatch(v) && !hostnameRegex.hasMatch(v)) {
    return 'Format invalide (ex: 192.168.1.10 ou pc.local)';
  }
  return null;
}

/// Valide un port TCP/UDP. Retourne `null` si valide.
String? validatePort(String? value) {
  final n = int.tryParse(value?.trim() ?? '');
  if (n == null || n <= 0 || n > 65535) {
    return 'Port entre 1 et 65535';
  }
  return null;
}
