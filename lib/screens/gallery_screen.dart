import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/app_gallery_service.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final AppGalleryService _service = AppGalleryService();
  List<AppGalleryItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await _service.loadItems();
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Widget _thumbnail(AppGalleryItem item) {
    if (item.localPath != null) return Image.file(File(item.localPath!), fit: BoxFit.cover);
    return FutureBuilder<Uint8List?>(
      future: item.asset?.thumbnailDataWithSize(const ThumbnailSize(360, 360)),
      builder: (context, snapshot) => snapshot.data == null
          ? const ColoredBox(color: Colors.black12, child: Center(child: Icon(Icons.image_outlined)))
          : Image.memory(snapshot.data!, fit: BoxFit.cover),
    );
  }

  void _open(AppGalleryItem item) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _GalleryDetail(item: item)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('갤러리'),
          actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: '새로고침')],
        ),
        body: kIsWeb
            ? const Center(child: Text('앱 내부 갤러리는 Android/iOS 기기에서 이용할 수 있습니다.'))
            : _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('갤러리를 불러오지 못했어요.\n$_error', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: const Text('다시 시도')),
                        ]),
                      ))
                    : _items.isEmpty
                        ? const Center(child: Text('표시할 사진이 없습니다.'))
                        : GridView.builder(
                            padding: const EdgeInsets.all(3),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3, crossAxisSpacing: 3, mainAxisSpacing: 3,
                            ),
                            itemCount: _items.length,
                            itemBuilder: (context, index) => GestureDetector(
                              onTap: () => _open(_items[index]),
                              child: Hero(
                                tag: 'gallery_${_items[index].title}_$index',
                                child: _thumbnail(_items[index]),
                              ),
                            ),
                          ),
      );
}

class _GalleryDetail extends StatelessWidget {
  final AppGalleryItem item;
  const _GalleryDetail({required this.item});

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (item.localPath != null) {
      image = Image.file(File(item.localPath!), fit: BoxFit.contain);
    } else {
      image = FutureBuilder<File?>(
        future: item.asset?.file,
        builder: (context, snapshot) => snapshot.data == null
            ? const Center(child: CircularProgressIndicator())
            : Image.file(snapshot.data!, fit: BoxFit.contain),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(item.title)),
      body: Center(child: image),
    );
  }
}
