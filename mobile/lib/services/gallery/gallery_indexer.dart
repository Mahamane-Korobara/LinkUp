import '../pairing/paired_device_store.dart';
import 'gallery_client.dart';
import 'gallery_source.dart';

/// Progression d'une indexation de galerie.
class GalleryProgress {
  final int indexed;
  final int thumbsSent;

  const GalleryProgress({required this.indexed, required this.thumbsSent});
}

/// Orchestre l'indexation de la galerie du tél vers le PC (S6) :
/// 1. permission, 2. pages de métadonnées → `POST /gallery/sync`,
/// 3. pour chaque média sans vignette → génère + `POST /gallery/thumb`.
///
/// Best-effort par vignette (un échec ponctuel n'arrête pas tout). Indépendant
/// du plugin (la [source] est injectée) → entièrement testable.
class GalleryIndexer {
  final GalleryAssetSource source;
  final GalleryClient client;
  final int pageSize;

  GalleryIndexer({
    required this.source,
    required this.client,
    this.pageSize = 100,
  });

  /// Lance l'indexation. Émet la progression via [onProgress]. [isCancelled]
  /// est consulté entre les pages/vignettes pour un arrêt propre.
  /// Throws [GalleryException] (permission refusée, sync KO).
  Future<void> run(
    PairedDevice device, {
    void Function(GalleryProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!await source.requestPermission()) {
      throw const GalleryException('Permission galerie refusée.');
    }

    var indexed = 0;
    var thumbsSent = 0;
    var page = 0;

    while (isCancelled?.call() != true) {
      final assets = await source.list(page: page, size: pageSize);
      if (assets.isEmpty) break;

      final pending = (await client.syncBatch(device, assets.map((a) => a.meta).toList())).toSet();
      indexed += assets.length;
      onProgress?.call(GalleryProgress(indexed: indexed, thumbsSent: thumbsSent));

      for (final asset in assets) {
        if (isCancelled?.call() == true) return;
        if (!pending.contains(asset.meta.mediaId)) continue;

        final thumb = await asset.loadThumbnail();
        if (thumb == null) continue;
        try {
          await client.uploadThumbnail(device, asset.meta.mediaId, thumb);
          thumbsSent++;
          onProgress?.call(GalleryProgress(indexed: indexed, thumbsSent: thumbsSent));
        } on GalleryException {
          // vignette best-effort : on continue avec les suivantes
        }
      }

      page++;
    }
  }
}
