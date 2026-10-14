import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import '../services/app_gallery_service.dart';
import 'filter_editor_screen.dart';

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
  bool _permissionDenied = false;
  final Map<String, Future<Uint8List?>> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _thumbnailCache.clear();
    setState(() { _loading = true; _error = null; _permissionDenied = false; });
    try {
      final items = await _service.loadItems();
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _permissionDenied = e is GalleryAccessDenied; _error = '$e'; _loading = false; });
    }
  }

  Widget _thumbnail(AppGalleryItem item) {
    if (item.localPath != null && item.isVideo) {
      return const ColoredBox(color: Colors.black54,
        child: Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 42)));
    }
    if (item.localPath != null) {
      return Image.file(File(item.localPath!), fit: BoxFit.cover, cacheWidth: 360);
    }
    final asset = item.asset;
    if (asset == null) return const Icon(Icons.image_outlined);
    // Reusing the same Future prevents fetching every thumbnail on every rebuild.
    final thumbnail = _thumbnailCache.putIfAbsent(asset.id,
      () => asset.thumbnailDataWithSize(const ThumbnailSize(360, 360)));
    return FutureBuilder<Uint8List?>(
      future: thumbnail,
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
                          if (_permissionDenied) ...[
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: () => PhotoManager.openSetting(),
                              child: const Text('앱 권한 설정 열기'),
                            ),
                          ],
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
                              child: Stack(fit: StackFit.expand, children: [Hero(
                                tag: 'gallery_${_items[index].title}_$index',
                                child: _thumbnail(_items[index]),
                              ), if (_items[index].isVideo) const Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(padding: EdgeInsets.all(5),
                                  child: Icon(Icons.videocam, color: Colors.white))),]),
                            ),
                          ),
      );
}

class _GalleryDetail extends StatelessWidget {
  final AppGalleryItem item;
  const _GalleryDetail({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.isVideo) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(item.title)),
        body: _VideoDetail(item: item),
      );
    }
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
      appBar: AppBar(title: Text(item.title), actions: [
        IconButton(icon: const Icon(Icons.auto_fix_high), tooltip: '필터 편집',
          onPressed: () async {
            final file = item.localPath != null ? File(item.localPath!) : await item.asset?.file;
            if (file == null || !context.mounted) return;
            await Navigator.push(context, MaterialPageRoute(
              builder: (_) => FilterEditorScreen(source: file)));
          }),
      ]),
      body: Center(child: image),
    );
  }
}


class _VideoDetail extends StatefulWidget {
  final AppGalleryItem item;
  const _VideoDetail({required this.item});

  @override
  State<_VideoDetail> createState() => _VideoDetailState();
}

class _VideoDetailState extends State<_VideoDetail> {
  VideoPlayerController? _player;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final file = widget.item.localPath != null
          ? File(widget.item.localPath!) : await widget.item.asset?.file;
      if (file == null) throw StateError('영상 파일에 접근할 수 없습니다.');
      final player = VideoPlayerController.file(file);
      await player.initialize();
      if (!mounted) { await player.dispose(); return; }
      setState(() { _player = player; _loading = false; });
      await player.play();
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('영상 재생 실패: $_error'));
    final player = _player!;
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      AspectRatio(aspectRatio: player.value.aspectRatio, child: VideoPlayer(player)),
      const SizedBox(height: 16),
      IconButton.filledTonal(
        onPressed: () async {
          if (player.value.isPlaying) { await player.pause(); }
          else { await player.play(); }
          if (mounted) setState(() {});
        },
        icon: Icon(player.value.isPlaying ? Icons.pause : Icons.play_arrow),
      ),
    ]));
  }
}
