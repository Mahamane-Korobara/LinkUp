import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Service de premier plan Android qui garde le serveur du Mode Hôte vivant
/// (sinon Android suspend le process en arrière-plan et coupe le socket).
///
/// Le serveur HTTP tourne dans l'isolate principal ; ce service ne fait que
/// maintenir le process en vie + afficher une notification persistante.
///
/// **Best-effort** : si l'init ou la permission échoue, l'hébergement reste
/// utilisable tant que l'app est au premier plan — on n'empêche jamais de
/// démarrer pour autant.
class HostForeground {
  static bool _inited = false;

  static void _ensureInit() {
    if (_inited) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'linkup_host',
        channelName: 'LinkUp — hébergement',
        channelDescription: 'Garde le partage tél↔tél actif.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _inited = true;
  }

  static Future<void> start(int peers) async {
    try {
      _ensureInit();
      await FlutterForegroundTask.requestNotificationPermission();
      if (await FlutterForegroundTask.isRunningService) {
        return update(peers);
      }
      await FlutterForegroundTask.startService(
        notificationTitle: 'LinkUp héberge',
        notificationText: _text(peers),
      );
    } catch (_) {/* foreground-only si FGS indisponible */}
  }

  static Future<void> update(int peers) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'LinkUp héberge',
          notificationText: _text(peers),
        );
      }
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  static String _text(int peers) => peers == 0
      ? 'En attente d\'appareils…'
      : '$peers appareil(s) appairé(s)';
}
