import 'dart:io';

/// Trouve l'IPv4 LAN de l'appareil (hors loopback) à mettre dans l'URL
/// d'appairage que le pair scanne. Préfère une IP privée (192.168/10/172.16-31),
/// ce qui couvre le cas « le téléphone hôte EST le point d'accès ».
class HostNetwork {
  static Future<String?> lanIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (_isPrivate(addr.address)) return addr.address;
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          return addr.address;
        }
      }
    } catch (_) {/* pas de réseau */}
    return null;
  }

  static bool _isPrivate(String ip) =>
      ip.startsWith('192.168.') ||
      ip.startsWith('10.') ||
      RegExp(r'^172\.(1[6-9]|2[0-9]|3[0-1])\.').hasMatch(ip);
}
