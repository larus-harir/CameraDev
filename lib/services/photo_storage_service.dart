import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PhotoStorageService {
  Future<String> saveToGallery(Uint8List bytes) async {
    if (kIsWeb) {
      throw UnsupportedError('웹 브라우저에서는 휴대폰 갤러리에 저장할 수 없습니다.');
    }
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess && !await Gal.requestAccess()) {
      throw Exception('사진 저장 권한이 거부되었습니다.');
    }

    final name = 'Vintage_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await Gal.putImageBytes(bytes, name: name);

    // Keep a private app copy as well, so the app can display its own captures
    // even on platforms where gallery indexing is delayed.
    final appDir = await getApplicationDocumentsDirectory();
    final captureDir = Directory(p.join(appDir.path, 'captures'));
    await captureDir.create(recursive: true);
    final file = File(p.join(captureDir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> importExistingImage(Uint8List bytes, String originalName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final captureDir = Directory(p.join(appDir.path, 'captures'));
    await captureDir.create(recursive: true);
    final safeName = originalName.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final name = '${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final file = File(p.join(captureDir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
