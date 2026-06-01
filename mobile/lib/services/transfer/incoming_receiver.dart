import 'dart:typed_data';

import '../pairing/paired_device_store.dart';
import 'media_saver.dart';
import 'transfer_client.dart';

/// Bilan d'une récupération de fichiers reçus du PC.
class IncomingResult {
  final int saved;
  final int failed;

  const IncomingResult({required this.saved, required this.failed});

  bool get isEmpty => saved == 0 && failed == 0;
}

/// Récupère les fichiers que le PC a envoyés à ce tél (sens to_phone) :
/// 1. `GET /transfers/incoming` → liste,
/// 2. pour chacun : télécharge les octets, les enregistre dans la galerie,
/// 3. `POST /transfers/{id}/delivered` → sort des entrants.
///
/// Best-effort par fichier ; client transfert + saver injectés → testable.
class IncomingReceiver {
  final TransferClient transfers;
  final MediaSaver saver;

  IncomingReceiver({required this.transfers, required this.saver});

  /// Extensions vidéo reconnues (pour router vers saveVideo).
  static const _videoExt = {'mp4', 'mov', 'mkv', 'webm', '3gp', 'avi', 'm4v'};

  static bool _isVideo(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0) return false;
    return _videoExt.contains(filename.substring(dot + 1).toLowerCase());
  }

  /// Récupère tout ce qui est en attente. [onProgress] suit (fait, total).
  /// Throws [TransferException] si la LISTE est inaccessible (réseau/appairage).
  Future<IncomingResult> run(
    PairedDevice device, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final incoming = await transfers.listIncoming(device);
    if (incoming.isEmpty) return const IncomingResult(saved: 0, failed: 0);

    var saved = 0;
    var failed = 0;
    var done = 0;

    for (final t in incoming) {
      if (isCancelled?.call() == true) break;

      try {
        final bytes = await transfers.downloadBytes(device, t.id);
        final ok = await saver.save(
          t.filename,
          Uint8List.fromList(bytes),
          isVideo: _isVideo(t.filename),
        );
        if (ok) {
          await transfers.markDelivered(device, t.id);
          saved++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++; // on laisse le transfert en entrant pour un prochain essai
      }

      done++;
      onProgress?.call(done, incoming.length);
    }

    return IncomingResult(saved: saved, failed: failed);
  }
}
