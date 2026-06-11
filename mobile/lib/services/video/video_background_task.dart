import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Fait tourner les actions longues de l'outil vidéo (téléchargement, extraction
/// audio, transcription IA) en ARRIÈRE-PLAN :
///
/// - un **service de premier plan** (`flutter_foreground_task`) garde le process
///   vivant quand l'app passe en arrière-plan, avec une notification persistante
///   « LinkUp » + le libellé de l'action et son **pourcentage** ;
/// - à la fin, le service s'arrête et une **notification push**
///   (`flutter_local_notifications`) signale que c'est terminé.
///
/// **Best-effort** : si une permission/notif échoue, l'action continue quand même
/// (au premier plan au minimum) — on n'interrompt jamais le travail.
class VideoBackgroundTask {
  VideoBackgroundTask._();

  static const _fgChannelId = 'linkup_video';
  static const _doneChannelId = 'linkup_video_done';
  static const _doneNotifId = 4201;

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static bool _fgInited = false;
  static bool _localInited = false;
  static String _label = 'LinkUp';

  static void _ensureFgInit() {
    if (_fgInited) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _fgChannelId,
        channelName: 'LinkUp — tâches vidéo',
        channelDescription: 'Téléchargement / transcription en cours.',
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
    _fgInited = true;
  }

  static Future<void> _ensureLocalInit() async {
    if (_localInited) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
        settings: const InitializationSettings(android: android));
    _localInited = true;
  }

  /// Démarre le service de premier plan pour l'action [label]. À appeler avant
  /// de lancer le travail long.
  static Future<void> begin(String label) async {
    _label = label;
    try {
      _ensureFgInit();
      await FlutterForegroundTask.requestNotificationPermission();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
            notificationTitle: 'LinkUp', notificationText: label);
      } else {
        await FlutterForegroundTask.startService(
            notificationTitle: 'LinkUp', notificationText: label);
      }
    } catch (_) {
      // Service de premier plan indisponible → l'action reste utilisable au
      // premier plan, on ne bloque pas.
    }
  }

  /// Met à jour la progression (0..1) dans la notification persistante.
  static Future<void> progress(double p) async {
    final pct = (p.clamp(0.0, 1.0) * 100).round();
    await _update('$_label $pct%');
  }

  /// Étape sans progression chiffrée (ex. appel IA) : juste un texte.
  static Future<void> tick(String text) => _update(text);

  static Future<void> _update(String text) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
            notificationTitle: 'LinkUp', notificationText: text);
      }
    } catch (_) {
      // Best-effort : un échec de mise à jour ne doit pas couper le travail.
    }
  }

  /// Termine avec succès : arrête le service et poste un push de fin [doneText].
  static Future<void> finishOk(String doneText) async {
    await _stop();
    try {
      await _ensureLocalInit();
      await _local.show(
        id: _doneNotifId,
        title: 'LinkUp',
        body: doneText,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _doneChannelId,
            'LinkUp — terminé',
            channelDescription: 'Action vidéo terminée.',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (_) {
      // Pas de push possible : tant pis, l'écran affiche déjà le résultat.
    }
  }

  /// Termine sans push (échec, ou action dont la fin est déjà visible à l'écran,
  /// ex. lecture / partage) : on arrête juste le service.
  static Future<void> finish() => _stop();

  static Future<void> _stop() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {
      // Best-effort : si le service n'était pas/plus actif, rien à arrêter.
    }
  }
}
