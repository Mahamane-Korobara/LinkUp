import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Infos d'affichage du téléphone, envoyées au PC pendant le handshake et
/// affichées sur le dashboard (page devices).
///
/// Purement informatif : aucune valeur de sécurité, le PC ne s'en sert que
/// pour aider l'utilisateur à reconnaître l'appareil à approuver.
class DeviceMetadata {
  /// Nom court et lisible (ex. « Pixel 7 », ou le nom iOS de l'appareil).
  final String name;

  /// Modèle complet (ex. « Google Pixel 7 »).
  final String model;

  /// Plateforme : « Android » / « iOS » / « autre ».
  final String platform;

  /// Version OS lisible (ex. « Android 14 », « iOS 17.2 »).
  final String osVersion;

  const DeviceMetadata({
    required this.name,
    required this.model,
    required this.platform,
    required this.osVersion,
  });

  /// Champs ajoutés au corps JSON du handshake `/api/pairing/handshake`.
  Map<String, String> toHandshakeFields() => {
        'device_name': name,
        'device_model': model,
        'device_platform': platform,
        'device_os': osVersion,
      };

  /// Récupère les infos via [device_info_plus]. Ne lève jamais : en cas
  /// d'échec plateforme, on retombe sur un fallback neutre (le pairing ne
  /// doit pas échouer pour une simple métadonnée d'affichage).
  static Future<DeviceMetadata> collect({DeviceInfoPlugin? plugin}) async {
    final info = plugin ?? DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return DeviceMetadata(
          name: a.model,
          model: '${a.manufacturer} ${a.model}'.trim(),
          platform: 'Android',
          osVersion: 'Android ${a.version.release}',
        );
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        return DeviceMetadata(
          name: i.name,
          model: i.utsname.machine,
          platform: 'iOS',
          osVersion: 'iOS ${i.systemVersion}',
        );
      }
    } catch (_) {
      // tombe dans le fallback ci-dessous
    }
    return const DeviceMetadata(
      name: 'Téléphone',
      model: 'inconnu',
      platform: 'autre',
      osVersion: 'inconnu',
    );
  }
}
