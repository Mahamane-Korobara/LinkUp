import 'dart:async';

import 'package:flutter/services.dart';

/// Surveille les changements du presse-papier du téléphone, **tant que l'app est
/// au 1er plan** (Android interdit l'écoute en arrière-plan depuis Android 10).
///
/// Implémenté nativement par MainActivity via un `OnPrimaryClipChangedListener`
/// exposé sur l'EventChannel `linkup/clipboard_events`. Injectable pour les
/// widget tests (on n'a pas besoin du vrai plugin).
abstract class ClipboardWatcher {
  /// Émet à chaque changement du presse-papier (sans la valeur — on relit ensuite).
  Stream<void> get onChanged;

  Future<void> start();
  Future<void> stop();
}

/// Implémentation Android (EventChannel). Sur les autres plateformes ou en test
/// sans plugin branché, le stream ne reçoit simplement rien (échec silencieux).
class NativeClipboardWatcher implements ClipboardWatcher {
  static const EventChannel _events = EventChannel('linkup/clipboard_events');

  final StreamController<void> _controller = StreamController<void>.broadcast();
  StreamSubscription<dynamic>? _sub;

  @override
  Stream<void> get onChanged => _controller.stream;

  @override
  Future<void> start() async {
    // S'abonner déclenche `onListen` côté natif → enregistrement du listener.
    _sub ??= _events.receiveBroadcastStream().listen(
      (_) {
        if (!_controller.isClosed) _controller.add(null);
      },
      onError: (_) {}, // EventChannel non branché (desktop/test) → ignoré
    );
  }

  @override
  Future<void> stop() async {
    // Annuler déclenche `onCancel` côté natif → retrait du listener.
    await _sub?.cancel();
    _sub = null;
  }
}
