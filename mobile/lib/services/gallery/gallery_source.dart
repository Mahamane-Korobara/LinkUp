import 'dart:typed_data';

/// Métadonnées d'affichage d'un média de la galerie (S6 — picker d'envoi).
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

  bool get isVideo => mime.startsWith('video/');
}

/// Un asset de la galerie : métadonnées + accès PARESSEUX à sa vignette (on ne
/// charge la vignette que des assets réellement affichés à l'écran).
class GalleryAsset {
  final GalleryMeta meta;
  final Future<Uint8List?> Function() loadThumbnail;

  const GalleryAsset({required this.meta, required this.loadThumbnail});
}

/// L'original d'un média (octets + nom de fichier), chargé à la demande au moment
/// de l'envoi. Séparé de [GalleryAsset] : on ne lit JAMAIS l'original pour la
/// grille, seulement pour les médias que l'utilisateur choisit d'envoyer.
class GalleryOriginal {
  final Uint8List bytes;
  final String filename;

  const GalleryOriginal({required this.bytes, required this.filename});
}

/// Type de média à lister (filtre fiable, appliqué côté plugin).
enum GalleryMediaType { all, image, video }

/// Source d'assets de la galerie. Abstraite pour injecter un faux en test sans
/// toucher au plugin natif (`PhotoManagerAssetSource` en prod).
abstract class GalleryAssetSource {
  /// Demande la permission d'accès à la galerie. `true` si accordée.
  Future<bool> requestPermission();

  /// Page d'assets (0-based), du plus récent au plus ancien, filtrée par [type].
  /// Liste vide = fin.
  Future<List<GalleryAsset>> list({
    int page = 0,
    int size = 100,
    GalleryMediaType type = GalleryMediaType.all,
  });

  /// Charge l'original d'un média par son `media_id` (pour l'import). `null` si
  /// le média n'existe plus sur le tél.
  Future<GalleryOriginal?> loadOriginal(String mediaId);
}
