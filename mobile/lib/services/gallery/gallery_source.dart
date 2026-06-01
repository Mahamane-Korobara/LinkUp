import 'dart:typed_data';

/// Métadonnées d'un média de la galerie (envoyées à l'index du PC, S6).
class GalleryMeta {
  final String mediaId;
  final String mime;
  final int size;
  final DateTime? takenAt;
  final int? width;
  final int? height;

  const GalleryMeta({
    required this.mediaId,
    required this.mime,
    this.size = 0,
    this.takenAt,
    this.width,
    this.height,
  });

  Map<String, dynamic> toSyncJson() => {
        'media_id': mediaId,
        'mime': mime,
        'size': size,
        if (takenAt != null) 'taken_at': takenAt!.toUtc().toIso8601String(),
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };
}

/// Un asset de la galerie : métadonnées + accès PARESSEUX à sa vignette (on ne
/// génère la vignette que pour les médias que le PC n'a pas encore).
class GalleryAsset {
  final GalleryMeta meta;
  final Future<Uint8List?> Function() loadThumbnail;

  const GalleryAsset({required this.meta, required this.loadThumbnail});
}

/// L'original d'un média (octets + nom de fichier), chargé à la demande lors d'un
/// import (S6.J4). Séparé de [GalleryAsset] car on ne lit JAMAIS l'original au
/// fil de l'indexation — seulement quand le PC le réclame explicitement.
class GalleryOriginal {
  final Uint8List bytes;
  final String filename;

  const GalleryOriginal({required this.bytes, required this.filename});
}

/// Source d'assets de la galerie. Abstraite pour injecter un faux en test sans
/// toucher au plugin natif (`PhotoManagerAssetSource` en prod).
abstract class GalleryAssetSource {
  /// Demande la permission d'accès à la galerie. `true` si accordée.
  Future<bool> requestPermission();

  /// Page d'assets (0-based). Liste vide = fin.
  Future<List<GalleryAsset>> list({int page = 0, int size = 100});

  /// Charge l'original d'un média par son `media_id` (pour l'import). `null` si
  /// le média n'existe plus sur le tél.
  Future<GalleryOriginal?> loadOriginal(String mediaId);
}
