import '../pairing/paired_device_store.dart';
import '../transfer/transfer_client.dart';
import 'gallery_source.dart';

/// Progression d'un envoi de photos : où on en est dans la sélection + la
/// fraction du fichier courant.
class GallerySendProgress {
  final int done; // fichiers terminés
  final int total; // fichiers sélectionnés
  final String currentName;
  final double fileFraction; // 0..1 du fichier en cours

  const GallerySendProgress({
    required this.done,
    required this.total,
    required this.currentName,
    required this.fileFraction,
  });
}

/// Bilan d'un envoi.
class GallerySendResult {
  final int sent;
  final int failed;

  const GallerySendResult({required this.sent, required this.failed});
}

/// Envoie au PC les originaux d'une sélection de médias (S6 — modèle « je
/// choisis sur le tél »). Chaque média part comme un transfert S4 normal → il
/// atterrit dans l'inbox du PC, visible dans « Fichiers ».
///
/// Best-effort par média : un original introuvable ou un upload KO n'arrête pas
/// les suivants. Source + client transfert injectés → testable sans plugin.
class GallerySender {
  final GalleryAssetSource source;
  final TransferClient transfers;

  GallerySender({required this.source, required this.transfers});

  /// Envoie les [mediaIds] sélectionnés. [onProgress] suit l'avancement,
  /// [isCancelled] permet d'arrêter proprement entre deux fichiers.
  Future<GallerySendResult> send(
    PairedDevice device,
    List<String> mediaIds, {
    void Function(GallerySendProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var sent = 0;
    var failed = 0;

    for (var i = 0; i < mediaIds.length; i++) {
      if (isCancelled?.call() == true) break;

      final mediaId = mediaIds[i];
      try {
        final original = await source.loadOriginal(mediaId);
        if (original == null) {
          failed++;
          continue;
        }

        onProgress?.call(GallerySendProgress(
          done: i,
          total: mediaIds.length,
          currentName: original.filename,
          fileFraction: 0,
        ));

        await transfers.uploadBytes(
          device: device,
          filename: original.filename,
          bytes: original.bytes,
          onProgress: (p) => onProgress?.call(GallerySendProgress(
            done: i,
            total: mediaIds.length,
            currentName: original.filename,
            fileFraction: p.fraction,
          )),
        );
        sent++;
      } catch (_) {
        failed++;
      }
    }

    return GallerySendResult(sent: sent, failed: failed);
  }
}
