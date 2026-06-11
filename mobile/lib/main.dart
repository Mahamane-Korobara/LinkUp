import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'screens/launch_gate.dart';
import 'screens/tools/video_tool_screen.dart';
import 'services/share/shared_link.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const LinkupApp());
}

class LinkupApp extends StatefulWidget {
  const LinkupApp({super.key});

  @override
  State<LinkupApp> createState() => _LinkupAppState();
}

class _LinkupAppState extends State<LinkupApp> {
  // Clé du Navigator racine : permet d'ouvrir le téléchargeur depuis le handler
  // de partage (hors d'un BuildContext de page).
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  @override
  void initState() {
    super.initState();
    _initShareIntake();
  }

  /// Reçoit les LIENS partagés depuis d'autres apps (Android, cf. AndroidManifest
  /// ACTION_SEND text/plain) et ouvre le téléchargeur vidéo avec le lien rempli.
  void _initShareIntake() {
    // App déjà ouverte : flux des partages entrants (onNewIntent / singleTop).
    _shareSub = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_handleShared, onError: (_) {});
    // App lancée par un partage (démarrage à froid).
    ReceiveSharingIntent.instance.getInitialMedia().then((media) {
      _handleShared(media);
      // Évite de re-traiter ce partage au prochain resume.
      ReceiveSharingIntent.instance.reset();
    });
  }

  void _handleShared(List<SharedMediaFile> media) {
    final url = _firstSharedUrl(media);
    if (url == null) return;
    // Le Navigator peut ne pas être prêt au tout premier frame d'un cold start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => VideoToolScreen(initialUrl: url)),
      );
    });
  }

  /// Première URL trouvée dans un partage texte/lien.
  static String? _firstSharedUrl(List<SharedMediaFile> media) {
    for (final m in media) {
      if (m.type == SharedMediaType.text || m.type == SharedMediaType.url) {
        final url = firstHttpUrl(m.path);
        if (url != null) return url;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Linkup',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // S2.J5 : reconnexion auto si un PC est déjà appairé (cf. LaunchGate).
      home: const LaunchGate(),
    );
  }
}
