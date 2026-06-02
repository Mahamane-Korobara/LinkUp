import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

/// Où un fichier reçu du PC a été rangé.
enum SaveKind { gallery, document, failed }

class SaveResult {
  final SaveKind kind;

  /// Chemin/emplacement lisible (pour informer l'utilisateur). Null si échec.
  final String? location;

  const SaveResult(this.kind, {this.location});

  static const failed = SaveResult(SaveKind.failed);
}

/// Enregistre un fichier reçu du PC au bon endroit selon son type. Abstrait pour
/// injecter un faux en test (les plugins natifs ne tournent que sur appareil).
abstract class ReceivedFileSaver {
  Future<SaveResult> save(String filename, Uint8List bytes);
}

/// Implémentation réelle :
/// - image/vidéo → galerie (`photo_manager`),
/// - tout le reste (PDF, zip, docs…) → dossier « LinkupReçus » accessible.
class DeviceFileSaver implements ReceivedFileSaver {
  static const _imageExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'};
  static const _videoExt = {'mp4', 'mov', 'mkv', 'webm', '3gp', 'avi', 'm4v'};

  static String _ext(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
  }

  @override
  Future<SaveResult> save(String filename, Uint8List bytes) async {
    final ext = _ext(filename);
    if (_imageExt.contains(ext) || _videoExt.contains(ext)) {
      return _saveToGallery(filename, bytes, isVideo: _videoExt.contains(ext));
    }
    return _saveToDocuments(filename, bytes);
  }

  Future<SaveResult> _saveToGallery(String filename, Uint8List bytes, {required bool isVideo}) async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.isAuth && !perm.hasAccess) return SaveResult.failed;

    if (isVideo) {
      final tmp = File('${Directory.systemTemp.path}/$filename');
      await tmp.writeAsBytes(bytes, flush: true);
      try {
        await PhotoManager.editor.saveVideo(tmp, title: filename);
      } finally {
        if (await tmp.exists()) await tmp.delete();
      }
    } else {
      await PhotoManager.editor.saveImage(bytes, filename: filename);
    }
    return const SaveResult(SaveKind.gallery, location: 'Galerie');
  }

  Future<SaveResult> _saveToDocuments(String filename, Uint8List bytes) async {
    // Dossier externe de l'app (visible via l'explorateur de fichiers) ; repli sur
    // le dossier documents privé si l'externe est indisponible.
    final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/LinkupReçus');
    if (!await dir.exists()) await dir.create(recursive: true);

    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return SaveResult(SaveKind.document, location: file.path);
  }
}
