import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PhotoStorageService {
  Future<String> saveToGallery(Uint8List bytes, {String? name}) async {
    if (kIsWeb) {
      throw UnsupportedError('웹 브라우저에서는 휴대폰 갤러리에 저장할 수 없습니다.');
    }
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess && !await Gal.requestAccess()) {
      throw Exception('사진 저장 권한이 거부되었습니다.');
    }

    final filename = name ?? 'Vintage_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await Gal.putImageBytes(bytes, name: filename);

    // Keep a private app copy as well, so the app can display its own captures
    // even on platforms where gallery indexing is delayed.
    final appDir = await getApplicationDocumentsDirectory();
    final captureDir = Directory(p.join(appDir.path, 'captures'));
    await captureDir.create(recursive: true);
    final file = File(p.join(captureDir.path, filename));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<String> saveVideoToGallery(String sourcePath, {String? name}) async {
    if (kIsWeb) throw UnsupportedError('웹에서는 동영상을 저장할 수 없습니다.');
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess && !await Gal.requestAccess()) {
      throw Exception('동영상 저장 권한이 거부되었습니다.');
    }
    // Keep a private copy in case the media database takes time to index.
    final docs = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(docs.path, 'captures'));
    await folder.create(recursive: true);
    final target = p.join(folder.path,
        name ?? 'Vintage_${DateTime.now().microsecondsSinceEpoch}.mp4');
    final copy = await File(sourcePath).copy(target);
    try {
      await Gal.putVideo(copy.path);
    } catch (_) {
      // Keep the local recording if gallery publication fails; caller gets error.
      rethrow;
    }
    return copy.path;
  }

  Future<String> importExistingImage(Uint8List bytes, String originalName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final captureDir = Directory(p.join(appDir.path, 'captures'));
    await captureDir.create(recursive: true);
    final safeName = originalName.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final name = '${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final file = File(p.join(captureDir.path, name));
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
