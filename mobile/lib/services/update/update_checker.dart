import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Une mise à jour disponible (version distante > version installée).
class UpdateInfo {
  final String versionName;
  final String apkUrl;
  final String? notes;

  const UpdateInfo({
    required this.versionName,
    required this.apkUrl,
    this.notes,
  });
}

/// Vérifie s'il existe une version plus récente de l'app, en lisant un petit
/// manifeste JSON servi par le VPS. L'app étant distribuée hors Play Store (APK
/// direct), c'est notre mécanisme de notification de mise à jour.
///
/// `version.json` attendu :
/// `{"versionCode": 4, "versionName": "1.2.0", "url": "…/linkup.apk", "notes": "…"}`
///
/// **Best-effort** : toute erreur (hors-ligne, JSON cassé, plugin) renvoie `null`
/// → aucune bannière, l'app fonctionne normalement.
class UpdateChecker {
  UpdateChecker({http.Client? client, this.manifestUrl = _defaultUrl})
      : _http = client ?? http.Client();

  static const _defaultUrl = 'https://linkup.sahelstack.tech/dl/version.json';

  final String manifestUrl;
  final http.Client _http;

  Future<UpdateInfo?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;

      final resp = await _http
          .get(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;

      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final latest = (j['versionCode'] as num?)?.toInt() ?? 0;
      if (latest <= current) return null;

      return UpdateInfo(
        versionName: (j['versionName'] as String?) ?? '',
        apkUrl: (j['url'] as String?) ??
            'https://linkup.sahelstack.tech/dl/linkup.apk',
        notes: j['notes'] as String?,
      );
    } catch (_) {
      return null; // pas de réseau / réponse invalide → on n'embête pas l'utilisateur
    }
  }

  void close() => _http.close();
}
