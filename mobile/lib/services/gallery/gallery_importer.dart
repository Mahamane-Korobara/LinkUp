import '../pairing/paired_device_store.dart';
import '../transfer/transfer_client.dart';
import 'gallery_client.dart';
import 'gallery_source.dart';

/// Résultat d'un passage d'import (pour l'UI).
class GalleryImportResult {
  final int imported;
  final int failed;

  const GalleryImportResult({required this.imported, required this.failed});

  bool get isEmpty => imported == 0 && failed == 0;
}

/// Honore les demandes d'import émises par le PC (S6.J4) :
/// 1. `GET /gallery/imports` → demandes en attente,
/// 2. pour chacune : lit l'original via la [source] et l'envoie au PC VIA LE
///    MODULE TRANSFERT S4 ([transfers]),
/// 3. `POST /gallery/imports/{id}/done` en pointant le transfert produit.
///
/// Best-effort par item (un média supprimé ou un upload KO n'arrête pas les
/// autres). Tout est injecté → testable sans plugin ni réseau réel.
class GalleryImporter {
  final GalleryAssetSource source;
  final GalleryClient client;
  final TransferClient transfers;

  GalleryImporter({
    required this.source,
    required this.client,
    required this.transfers,
  });

  /// Traite toutes les demandes en attente. [onProgress] reçoit (fait, total).
  /// [isCancelled] est consulté entre les items. Throws [GalleryException] si la
  /// LISTE des demandes est inaccessible (réseau/appairage).
  Future<GalleryImportResult> run(
    PairedDevice device, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final pending = await client.pendingImports(device);
    if (pending.isEmpty) return const GalleryImportResult(imported: 0, failed: 0);

    var imported = 0;
    var failed = 0;
    var done = 0;

    for (final req in pending) {
      if (isCancelled?.call() == true) break;

      try {
        final original = await source.loadOriginal(req.mediaId);
        if (original == null) {
          // Le média n'existe plus sur le tél : on clôt quand même la demande
          // pour ne pas la re-tenter indéfiniment.
          await client.markImported(device, req.id, null);
          failed++;
        } else {
          final transferId = await transfers.uploadBytes(
            device: device,
            filename: original.filename,
            bytes: original.bytes,
          );
          await client.markImported(device, req.id, transferId);
          imported++;
        }
      } catch (_) {
        // Upload KO : on laisse la demande en `requested` pour un prochain essai.
        failed++;
      }

      done++;
      onProgress?.call(done, pending.length);
    }

    return GalleryImportResult(imported: imported, failed: failed);
  }
}
