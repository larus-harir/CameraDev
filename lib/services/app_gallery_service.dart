import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppGalleryItem {
  final AssetEntity? asset;
  final String? localPath;
  final String title;
  final bool isVideo;

  const AppGalleryItem({this.asset, this.localPath, required this.title, this.isVideo = false});
}

class GalleryAccessDenied implements Exception {
  @override
  String toString() => '사진 접근 권한이 없습니다. 기기 설정에서 사진 접근을 허용해 주세요.';
}

class AppGalleryService {
  Future<List<AppGalleryItem>> loadItems() async {
    if (kIsWeb) return [];
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) throw GalleryAccessDenied();

    final items = <AppGalleryItem>[];
    final docs = await getApplicationDocumentsDirectory();
    final captureDir = Directory(p.join(docs.path, 'captures'));
    if (await captureDir.exists()) {
      // Avoid synchronous directory / file-stat I/O on Flutter's UI isolate.
      final entries = await captureDir.list().toList();
      final mediaFiles = entries.whereType<File>().where((f) =>
          ['.jpg', '.jpeg', '.png', '.mp4', '.mov']
              .contains(p.extension(f.path).toLowerCase()));
      final files = await Future.wait(mediaFiles.map((file) async =>
          (file: file, modified: await file.lastModified())));
      files.sort((a, b) => b.modified.compareTo(a.modified));
      for (final item in files) {
        final file = item.file;
        items.add(AppGalleryItem(localPath: file.path, title: p.basename(file.path),
          isVideo: ['.mp4', '.mov'].contains(p.extension(file.path).toLowerCase())));
      }
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    if (albums.isNotEmpty) {
      final album = albums.firstWhere(
        (a) => a.isAll,
        orElse: () => albums.first,
      );
      final count = await album.assetCountAsync;
      final assets = await album.getAssetListRange(start: 0, end: count.clamp(0, 250));
      for (final asset in assets) {
        items.add(AppGalleryItem(asset: asset, title: asset.title ?? '미디어',
            isVideo: asset.type == AssetType.video));
      }
    }
    // App-private copies and gallery assets can refer to the same photo.
    // Prefer system gallery entries when available; keep private copies only
    // when no system photo is returned (e.g. media index has not updated).
    if (items.any((e) => e.asset != null)) {
      // System gallery is canonical; local fallback is for indexing delays.
      return items.where((e) => e.asset != null).toList();
    }
    return items;
  }
}
