import 'dart:convert';

import 'package:flutter/services.dart';

/// Une application installée sur ce téléphone, telle qu'exposée par le canal
/// natif `linkup/apps` — de quoi l'AFFICHER (nom, icône) et l'ENVOYER (chemin de
/// l'APK) à un autre téléphone en Mode Hôte, façon Xender.
class InstalledApp {
  final String name;
  final String packageName;
  final String? versionName;

  /// Taille du base.apk (octets) — affichée et utile pour estimer le transfert.
  final int sizeBytes;

  /// Chemin du base.apk (`applicationInfo.sourceDir`) ; lisible par le Dart pour
  /// en lire les octets au moment de l'envoi.
  final String apkPath;

  /// Icône de l'app décodée (PNG) ; `null` si le rendu natif a échoué.
  final Uint8List? icon;

  const InstalledApp({
    required this.name,
    required this.packageName,
    required this.sizeBytes,
    required this.apkPath,
    this.versionName,
    this.icon,
  });

  /// Nom de fichier proposé pour l'APK envoyé (nom lisible + version).
  String get suggestedFilename {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').trim();
    final base = safe.isEmpty ? packageName : safe;
    final v = (versionName ?? '').replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '');
    return v.isEmpty ? '$base.apk' : '$base-$v.apk';
  }
}

/// Accès aux applications installées via le canal natif Android `linkup/apps`.
class InstalledAppsService {
  static const MethodChannel _channel = MethodChannel('linkup/apps');

  const InstalledAppsService();

  /// Liste les apps lançables installées par l'utilisateur (triées par nom).
  /// Lève une [PlatformException] si l'énumération échoue côté natif.
  Future<List<InstalledApp>> list() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('list') ?? const [];
    return raw.map((e) {
      final m = (e as Map).cast<String, dynamic>();
      final iconB64 = m['icon'] as String?;
      return InstalledApp(
        name: m['name'] as String? ?? '?',
        packageName: m['package'] as String? ?? '',
        versionName: m['versionName'] as String?,
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        apkPath: m['apkPath'] as String? ?? '',
        icon: iconB64 == null ? null : base64Decode(iconB64),
      );
    }).toList();
  }
}
