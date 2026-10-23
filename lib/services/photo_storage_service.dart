import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PhotoStorageService {
  // Permission is stable during normal capture sessions; still let Gal report
  // revoked access and invalidate this cache on any publication failure.
  bool _savePermissionGranted = false;

  Future<void> _ensureAccess() async {
    if (_savePermissionGranted) return;
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess && !await Gal.requestAccess()) {
      throw Exception('사진/동영상 저장 권한이 거부되었습니다.');
    }
    _savePermissionGranted = true;
  }

  Future<String> saveToGallery(Uint8List bytes, {String? name}) async {
    if (kIsWeb) {
      throw UnsupportedError('웹 브라우저에서는 휴대폰 갤러리에 저장할 수 없습니다.');
    }
    await _ensureAccess();

    final filename = name ?? 'Vintage_${DateTime.now().microsecondsSinceEpoch}.jpg';
    // Persist bytes only once on the Dart side. Gal imports from this file.
    // Avoid Gal.putImageBytes followed by a second app-directory write.
    final appDir = await getApplicationDocumentsDirectory();
    final captureDir = Directory(p.join(appDir.path, 'captures'));
    await captureDir.create(recursive: true);
    final file = File(p.join(captureDir.path, filename));
    await file.writeAsBytes(bytes, flush: false);
    try {
      await Gal.putImage(file.path);
    } catch (_) {
      _savePermissionGranted = false;
      // Retain the local copy as recovery in case publishing fails.
      rethrow;
    }
    return file.path;
  }

  Future<String> saveVideoToGallery(String sourcePath, {String? name}) async {
    if (kIsWeb) throw UnsupportedError('웹에서는 동영상을 저장할 수 없습니다.');
    await _ensureAccess();
    // Rename within the SAME directory: a filesystem metadata operation,
    // not a full-file copy. This retains the intended VID_* gallery filename.
    // The caller can keep using sourcePath after publication only for cleanup.
    File? renamedFile;
    String publishingPath = sourcePath;
    if (name != null && p.basename(sourcePath) != name) {
      final destination = p.join(p.dirname(sourcePath), name);
      try {
        renamedFile = await File(sourcePath).rename(destination);
        publishingPath = renamedFile.path;
      } catch (_) {
        // Fall back to the source name if a rename isn't permitted.
      }
    }
    try {
      // No Documents copy of potentially hundreds of megabytes of MP4.
      await Gal.putVideo(publishingPath);
      if (renamedFile != null) {
        try { await renamedFile.delete(); } catch (_) {}
      }
      return sourcePath;
    } catch (_) {
      _savePermissionGranted = false;
      // Try to restore the original path for caller recovery.
      if (renamedFile != null) {
        try {
          await renamedFile.rename(sourcePath);
          publishingPath = sourcePath;
        } catch (_) {}
      }
      // Keep a recoverable app-private copy if gallery publication failed.
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(docs.path, 'captures'));
      await folder.create(recursive: true);
      final filename = name ??
          'Vintage_${DateTime.now().microsecondsSinceEpoch}.mp4';
      try {
        await File(publishingPath).copy(p.join(folder.path, filename));
      } catch (_) {}
      rethrow;
    }
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
