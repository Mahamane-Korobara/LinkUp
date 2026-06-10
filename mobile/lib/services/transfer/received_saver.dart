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

/// Réduit un nom de fichier reçu à un **basename sûr** (anti path-traversal).
///
/// Le nom vient d'une source distante — le PC, ou un PAIR en Mode Hôte (header
/// `X-Transfer-Filename`). Sans ça, un nom comme `../../../evil` ferait écrire
/// le fichier HORS du dossier prévu (écrasement). On ne garde que le dernier
/// segment, jamais `/`, `\`, `.` ni `..`. (Le bridge Python fait `Path(n).name`.)
String safeReceivedName(String filename) {
  final last = filename.split(RegExp(r'[/\\]')).last.trim();
  if (last.isEmpty || last == '.' || last == '..') return 'fichier';
  return last;
}

/// Enregistre un fichier reçu du PC au bon endroit selon son type. Abstrait pour
/// injecter un faux en test (les plugins natifs ne tournent que sur appareil).
abstract class ReceivedFileSaver {
  /// Enregistre depuis des octets déjà en mémoire (petits fichiers / aperçus).
  Future<SaveResult> save(String filename, Uint8List bytes);

  /// Variante **streaming** : enregistre depuis un fichier déjà sur disque, sans
  /// charger tout le contenu en mémoire (transferts volumineux). Implémentation
  /// par défaut : lit le fichier puis délègue à [save] (suffisant pour les fakes
  /// de test) ; surchargée par [DeviceFileSaver] pour un vrai streaming.
  Future<SaveResult> saveFile(String filename, File source) async =>
      save(filename, await source.readAsBytes());
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
    final name = safeReceivedName(filename);
    final ext = _ext(name);
    if (_imageExt.contains(ext) || _videoExt.contains(ext)) {
      return _saveToGallery(name, bytes, isVideo: _videoExt.contains(ext));
    }
    return _saveToDocuments(name, bytes);
  }

  @override
  Future<SaveResult> saveFile(String filename, File source) async {
    final name = safeReceivedName(filename);
    final ext = _ext(name);
    // Vidéos & documents : copie disque→disque, jamais tout chargé en RAM
    // (évite l'OOM sur un gros fichier reçu d'un pair). Les images sont petites
    // et l'API galerie demande des octets → on les lit.
    if (_videoExt.contains(ext)) return _saveVideoFromFile(name, source);
    if (_imageExt.contains(ext)) {
      return _saveToGallery(name, await source.readAsBytes(), isVideo: false);
    }
    return _saveDocumentFromFile(name, source);
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

  Future<SaveResult> _saveVideoFromFile(String filename, File source) async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.isAuth && !perm.hasAccess) return SaveResult.failed;
    // photo_manager veut un fichier nommé : on copie (sans RAM) vers un temp.
    final tmp = File('${Directory.systemTemp.path}/$filename');
    await source.copy(tmp.path);
    try {
      await PhotoManager.editor.saveVideo(tmp, title: filename);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
    return const SaveResult(SaveKind.gallery, location: 'Galerie');
  }

  Future<SaveResult> _saveToDocuments(String filename, Uint8List bytes) async {
    final file = File('${await _documentsDir()}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return SaveResult(SaveKind.document, location: file.path);
  }

  Future<SaveResult> _saveDocumentFromFile(String filename, File source) async {
    final dest = File('${await _documentsDir()}/$filename');
    await source.copy(dest.path); // copie disque→disque, pas de RAM
    return SaveResult(SaveKind.document, location: dest.path);
  }

  /// Dossier externe de l'app (visible via l'explorateur de fichiers) ; repli sur
  /// le dossier documents privé si l'externe est indisponible.
  Future<String> _documentsDir() async {
    final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/LinkupReçus');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
}
