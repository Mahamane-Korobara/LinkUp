import 'dart:io';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

/// Enregistre un média reçu dans la galerie du téléphone. Abstrait pour pouvoir
/// injecter un faux en test (le plugin natif n'est dispo que sur appareil).
abstract class MediaSaver {
  /// Enregistre [bytes] sous [filename]. [isVideo] choisit photo/vidéo.
  /// Retourne `true` si l'enregistrement a réussi.
  Future<bool> save(String filename, Uint8List bytes, {required bool isVideo});
}

/// Implémentation réelle via `photo_manager` (MediaStore Android / Photos iOS).
class PhotoManagerMediaSaver implements MediaSaver {
  @override
  Future<bool> save(String filename, Uint8List bytes, {required bool isVideo}) async {
    // Permission d'ÉCRITURE dans la galerie (différente de la lecture).
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.isAuth && !perm.hasAccess) return false;

    if (isVideo) {
      // saveVideo veut un fichier : on passe par un temporaire.
      final tmp = File('${Directory.systemTemp.path}/$filename');
      await tmp.writeAsBytes(bytes, flush: true);
      try {
        await PhotoManager.editor.saveVideo(tmp, title: filename);
        return true; // une erreur d'enregistrement lève → remontée à l'appelant
      } finally {
        if (await tmp.exists()) await tmp.delete();
      }
    }

    await PhotoManager.editor.saveImage(bytes, filename: filename);
    return true;
  }
}
