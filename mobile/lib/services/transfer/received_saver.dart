import 'dart:io';

import 'package:flutter/services.dart';
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

  /// Canal natif d'enregistrement public (cf. MainActivity, MediaStore).
  static const _saveChannel = MethodChannel('linkup/savefile');

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
    // Écrit d'abord dans un temp, puis pousse vers le dossier public.
    final tmp = File('${Directory.systemTemp.path}/$filename');
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      return await _saveDocumentFromFile(filename, tmp);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }

  Future<SaveResult> _saveDocumentFromFile(String filename, File source) async {
    // Cible publique « Téléchargements/LinkUp » (visible par l'utilisateur).
    final publicLoc = await _saveToPublicDownloads(source, filename);
    if (publicLoc != null) {
      return SaveResult(SaveKind.document, location: publicLoc);
    }
    // Repli : ancien dossier externe de l'app (si le canal natif a échoué).
    final dest = File('${await _documentsDir()}/$filename');
    await source.copy(dest.path); // copie disque→disque, pas de RAM
    return SaveResult(SaveKind.document, location: dest.path);
  }

  /// Enregistre [source] dans le dossier PUBLIC Téléchargements/LinkUp via le
  /// canal natif (MediaStore). Renvoie l'emplacement lisible, ou null si échec.
  Future<String?> _saveToPublicDownloads(File source, String filename) async {
    try {
      return await _saveChannel.invokeMethod<String>('saveToDownloads', {
        'srcPath': source.path,
        'filename': filename,
        'mime': _mimeFor(filename),
      });
    } catch (_) {
      return null; // canal indispo / refus → repli appelant
    }
  }

  static String _mimeFor(String filename) {
    switch (_ext(filename)) {
      case 'pdf':
        return 'application/pdf';
      case 'm4a':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'opus':
      case 'ogg':
        return 'audio/ogg';
      case 'wav':
        return 'audio/wav';
      case 'txt':
        return 'text/plain';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  /// Dossier externe de l'app (repli) — utilisé seulement si l'enregistrement
  /// public échoue (ex. canal natif indisponible).
  Future<String> _documentsDir() async {
    final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/LinkupReçus');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
}
