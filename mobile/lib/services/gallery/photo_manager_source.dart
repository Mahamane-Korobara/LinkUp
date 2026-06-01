import 'package:photo_manager/photo_manager.dart';

import 'gallery_source.dart';

/// Source galerie réelle (Android/iOS) via `photo_manager`.
///
/// Isolée du reste pour que l'indexeur et ses tests ne dépendent pas du plugin.
class PhotoManagerAssetSource implements GalleryAssetSource {
  @override
  Future<bool> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state.isAuth || state.hasAccess;
  }

  @override
  Future<List<GalleryAsset>> list({int page = 0, int size = 100}) async {
    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.common, // images + vidéos
    );
    if (paths.isEmpty) return const [];

    final assets = await paths.first.getAssetListPaged(page: page, size: size);

    return assets
        .map((a) => GalleryAsset(
              meta: GalleryMeta(
                mediaId: a.id,
                // mime exact non garanti côté plugin : on déduit du type (suffisant
                // pour l'index ; l'import lira le vrai fichier).
                mime: a.type == AssetType.video ? 'video/mp4' : 'image/jpeg',
                takenAt: a.createDateTime,
                width: a.width,
                height: a.height,
              ),
              loadThumbnail: () =>
                  a.thumbnailDataWithSize(const ThumbnailSize.square(200)),
            ))
        .toList();
  }
}
