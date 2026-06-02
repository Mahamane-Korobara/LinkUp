import 'dart:typed_data';

import '../pairing/paired_device_store.dart';
import 'received_saver.dart';
import 'transfer_client.dart';

/// Bilan d'une récupération de fichiers reçus du PC.
class IncomingResult {
  final int gallery; // photos/vidéos rangées dans la galerie
  final int documents; // autres fichiers rangés dans « LinkupReçus »
  final int failed;

  const IncomingResult({this.gallery = 0, this.documents = 0, this.failed = 0});

  int get saved => gallery + documents;
  bool get isEmpty => saved == 0 && failed == 0;
}

/// Récupère les fichiers que le PC a envoyés à ce tél (sens to_phone) :
/// 1. `GET /transfers/incoming` → liste,
/// 2. pour chacun : télécharge, range au bon endroit (galerie / dossier),
/// 3. `POST /transfers/{id}/delivered` → sort des entrants.
///
/// Best-effort par fichier ; client transfert + saver injectés → testable.
class IncomingReceiver {
  final TransferClient transfers;
  final ReceivedFileSaver saver;

  IncomingReceiver({required this.transfers, required this.saver});

  /// Récupère tout ce qui est en attente. [onProgress] suit (fait, total).
  /// Throws [TransferException] si la LISTE est inaccessible (réseau/appairage).
  Future<IncomingResult> run(
    PairedDevice device, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final incoming = await transfers.listIncoming(device);
    if (incoming.isEmpty) return const IncomingResult();

    var gallery = 0;
    var documents = 0;
    var failed = 0;
    var done = 0;

    for (final t in incoming) {
      if (isCancelled?.call() == true) break;

      try {
        final bytes = await transfers.downloadBytes(device, t.id);
        final result = await saver.save(t.filename, Uint8List.fromList(bytes));
        switch (result.kind) {
          case SaveKind.gallery:
            gallery++;
            await transfers.markDelivered(device, t.id);
          case SaveKind.document:
            documents++;
            await transfers.markDelivered(device, t.id);
          case SaveKind.failed:
            failed++; // laissé en entrant pour un prochain essai
        }
      } catch (_) {
        failed++;
      }

      done++;
      onProgress?.call(done, incoming.length);
    }

    return IncomingResult(gallery: gallery, documents: documents, failed: failed);
  }
}
