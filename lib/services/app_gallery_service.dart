import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppGalleryItem {
  final AssetEntity? asset;
  final String? localPath;
  final String title;

  const AppGalleryItem({this.asset, this.localPath, required this.title});
}

class AppGalleryService {
  Future<List<AppGalleryItem>> loadItems() async {
    if (kIsWeb) return [];
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      throw Exception('갤러리 접근 권한이 필요합니다.');
    }

    final items = <AppGalleryItem>[];
    final docs = await getApplicationDocumentsDirectory();
    final captureDir = Directory(p.join(docs.path, 'captures'));
    if (await captureDir.exists()) {
      final files = captureDir.listSync().whereType<File>().where((f) =>
          ['.jpg', '.jpeg', '.png'].contains(p.extension(f.path).toLowerCase())).toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (final file in files) {
        items.add(AppGalleryItem(localPath: file.path, title: p.basename(file.path)));
      }
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    if (albums.isNotEmpty) {
      final album = albums.first;
      final count = await album.assetCountAsync;
      final assets = await album.getAssetListRange(start: 0, end: count.clamp(0, 250));
      for (final asset in assets) {
        items.add(AppGalleryItem(asset: asset, title: asset.title ?? '사진'));
      }
    }
    return items;
  }
}
