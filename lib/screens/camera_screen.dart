import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/camera_settings.dart';
import '../services/camera_service.dart';
import '../services/photo_storage_service.dart';
import '../services/settings_service.dart';
import '../widgets/grid_overlay.dart';
import 'gallery_screen.dart';
import 'settings_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  final _camera = CameraService();
  final _settingsService = SettingsService();
  final _storage = PhotoStorageService();
  CameraSettings _settings = const CameraSettings();
  bool _ready = false;
  bool _busy = false;
  bool _showPreview = false;
  Uint8List? _captured;
  double _zoom = 1, _minZoom = 1, _maxZoom = 1;
  FlashMode _flash = FlashMode.off;
  int _timer = 0, _countdown = 0;
  String _ratio = '4:3';
  Offset? _focusPoint;
  int _focusToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _settings = await _settingsService.load();
      await _camera.initialize();
      _minZoom = _camera.minZoom;
      _maxZoom = _camera.maxZoom;
      _zoom = 1.0.clamp(_minZoom, _maxZoom).toDouble();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      _message('카메라 초기화 실패: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _camera.dispose();
      if (mounted) setState(() => _ready = false);
    } else if (state == AppLifecycleState.resumed && !_ready) {
      _initialize();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(
      initialSettings: _settings,
      onSave: (value) async {
        _settings = value;
        await _settingsService.save(value);
        if (mounted) setState(() {});
      },
    )));
    if (mounted) setState(() {});
  }

  Future<void> _switchCamera() async {
    if (_busy || !_ready) return;
    setState(() => _ready = false);
    try {
      await _camera.switchCamera();
      _minZoom = _camera.minZoom;
      _maxZoom = _camera.maxZoom;
      _zoom = 1.0.clamp(_minZoom, _maxZoom).toDouble();
      _flash = FlashMode.off;
    } catch (e) {
      _message('카메라 전환 실패: $e');
    } finally {
      if (mounted) setState(() => _ready = _camera.controller?.value.isInitialized ?? false);
    }
  }

  Future<void> _cycleFlash() async {
    const modes = [FlashMode.off, FlashMode.auto, FlashMode.always, FlashMode.torch];
    final next = modes[(modes.indexOf(_flash) + 1) % modes.length];
    try {
      await _camera.setFlash(next);
      if (mounted) setState(() => _flash = next);
    } catch (_) {
      _message('이 카메라는 해당 플래시 모드를 지원하지 않습니다.');
    }
  }

  Future<void> _capture() async {
    if (_busy || !_ready) return;
    setState(() { _busy = true; _countdown = _timer; });
    try {
      for (int remaining = _timer; remaining > 0; remaining--) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted || !_ready) return;
        setState(() => _countdown = remaining - 1);
      }
      final photo = await _camera.takePicture();
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      if (_settings.showCapturePreview) {
        setState(() { _captured = bytes; _showPreview = true; });
      } else if (_settings.askBeforeSaving) {
        final save = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('사진 저장'),
            content: const Text('촬영한 사진을 갤러리에 저장할까요?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
            ],
          ),
        );
        if (save == true) await _save(bytes);
      } else {
        await _save(bytes);
      }
    } catch (e) {
      _message('촬영 실패: $e');
    } finally {
      if (mounted) setState(() { _busy = false; _countdown = 0; });
    }
  }

  Future<void> _save(Uint8List bytes) async {
    try {
      await _storage.saveToGallery(bytes);
      if (mounted) setState(() { _showPreview = false; _captured = null; });
      _message('갤러리에 저장했어요.');
    } catch (e) {
      _message('사진 저장 실패: $e');
    }
  }

  Future<void> _tapToFocus(TapDownDetails details, Size viewSize) async {
    if (_busy || !_ready || viewSize.width == 0 || viewSize.height == 0) return;
    final local = details.localPosition;
    final x = (local.dx / viewSize.width).clamp(0.0, 1.0);
    final y = (local.dy / viewSize.height).clamp(0.0, 1.0);
    final token = ++_focusToken;
    setState(() => _focusPoint = Offset(local.dx, local.dy));
    await _camera.focusAt(x, y);
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted && token == _focusToken) setState(() => _focusPoint = null);
  }

  Widget _viewfinder(CameraController controller) {
    return LayoutBuilder(builder: (context, constraints) {
      final portrait = constraints.maxHeight >= constraints.maxWidth;
      final landscapeRatio = _ratio == '1:1' ? 1.0 : _ratio == '16:9' ? 16 / 9 : 4 / 3;
      final targetRatio = portrait ? 1 / landscapeRatio : landscapeRatio;
      final available = Size(constraints.maxWidth, constraints.maxHeight);
      final frameWidth = available.width < available.height * targetRatio
          ? available.width : available.height * targetRatio;
      final frameHeight = frameWidth / targetRatio;
      final cameraRatio = portrait ? 1 / controller.value.aspectRatio : controller.value.aspectRatio;
      return Center(child: SizedBox(
        width: frameWidth,
        height: frameHeight,
        child: ClipRect(child: Stack(fit: StackFit.expand, children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: cameraRatio * 1000,
              height: 1000,
              child: CameraPreview(controller),
            ),
          ),
          if (_settings.showGrid) const IgnorePointer(child: GridOverlay()),
          LayoutBuilder(builder: (context, box) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (details) => _tapToFocus(details, Size(box.maxWidth, box.maxHeight)),
            child: Stack(children: [
              if (_focusPoint != null)
                Positioned(
                  left: (_focusPoint!.dx - 26).clamp(0, box.maxWidth - 52),
                  top: (_focusPoint!.dy - 26).clamp(0, box.maxHeight - 52),
                  child: const IgnorePointer(child: SizedBox(
                    width: 52, height: 52,
                    child: DecoratedBox(decoration: BoxDecoration(
                      border: Border.fromBorderSide(BorderSide(color: Colors.amber, width: 2)),
                    )),
                  )),
          )]),
          )),
        ])),
      ));
    });
  }

  Widget _control(IconData icon, String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 23),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ]),
    ),
  );

  Widget _shutter() => GestureDetector(
    onTap: _capture,
    child: Container(
      width: 72, height: 72,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
      child: Center(child: Container(
        width: 54, height: 54,
        decoration: BoxDecoration(shape: BoxShape.circle, color: _busy ? Colors.white38 : Colors.white),
      )),
    ),
  );

  Widget _zoomSelector() {
    final stops = <double>[];
    for (final v in [_minZoom, 1.0, 2.0, 3.0, _maxZoom]) {
      if (v >= _minZoom && v <= _maxZoom && !stops.any((s) => (s - v).abs() < 0.05)) stops.add(v);
    }
    stops.sort();
    return SizedBox(height: 40, child: ListView(
      shrinkWrap: true, scrollDirection: Axis.horizontal,
      children: stops.map((value) {
        final selected = (_zoom - value).abs() < 0.06;
        return Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: ActionChip(
          label: Text('${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)}x'),
          backgroundColor: selected ? const Color(0xFFD8B88A) : Colors.black54,
          labelStyle: TextStyle(color: selected ? Colors.black : Colors.white),
          onPressed: () async {
            setState(() => _zoom = value);
            await _camera.setZoom(value);
          },
        ));
      }).toList(),
    ));
  }

  Widget _controls(bool landscape) {
    final timer = _control(Icons.timer_outlined, _timer == 0 ? '타이머 OFF' : '$_timer초', () {
      const values = [0, 3, 5, 10];
      setState(() => _timer = values[(values.indexOf(_timer) + 1) % values.length]);
    });
    final ratio = _control(Icons.aspect_ratio, _ratio, () {
      const values = ['4:3', '16:9', '1:1'];
      setState(() => _ratio = values[(values.indexOf(_ratio) + 1) % values.length]);
    });
    final flip = _control(Icons.cameraswitch_outlined, '전환', _switchCamera);
    final grid = _control(_settings.showGrid ? Icons.grid_on : Icons.grid_off, '그리드', () async {
      final next = _settings.copyWith(showGrid: !_settings.showGrid);
      setState(() => _settings = next);
      await _settingsService.save(next);
    });
    final flash = _control(_flash == FlashMode.off ? Icons.flash_off : Icons.flash_on, '플래시', _cycleFlash);
    final gallery = _control(Icons.photo_library_outlined, '갤러리', () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const GalleryScreen())));
    final settings = _control(Icons.settings_outlined, '설정', _openSettings);
    if (landscape) {
      return Container(color: Colors.black87, width: 116, child: SingleChildScrollView(child: Column(children: [
        const SizedBox(height: 8), gallery, settings, flash, timer, ratio,
        const SizedBox(height: 8), _zoomSelector(), const SizedBox(height: 12),
        _shutter(), const SizedBox(height: 8), flip, grid,
      ])));
    }
    return Container(color: Colors.black87, padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [gallery, flash, timer, ratio, settings]),
        _zoomSelector(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [flip, _shutter(), grid]),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _camera.controller;
    if (!_ready || controller == null || !controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_showPreview && _captured != null) {
      return Scaffold(body: SafeArea(child: Stack(fit: StackFit.expand, children: [
        Image.memory(_captured!, fit: BoxFit.contain),
        Positioned(top: 8, left: 8, child: IconButton(
          onPressed: () => setState(() { _showPreview = false; _captured = null; }),
          icon: const Icon(Icons.close),
        )),
        Positioned(bottom: 16, left: 20, right: 20, child: Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => setState(() {
            _showPreview = false; _captured = null;
          }), child: const Text('다시 촬영'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: () => _save(_captured!), child: const Text('저장'))),
        ])),
      ])));
    }
    return Scaffold(body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
      final landscape = constraints.maxWidth > constraints.maxHeight;
      final viewfinder = Expanded(child: Stack(fit: StackFit.expand, children: [
        _viewfinder(controller),
        if (_countdown > 0) Center(child: IgnorePointer(child: Text('$_countdown',
          style: const TextStyle(fontSize: 110, fontWeight: FontWeight.bold,
            shadows: [Shadow(blurRadius: 8, color: Colors.black)])))),
      ]));
      return landscape
          ? Row(children: [viewfinder, _controls(true)])
          : Column(children: [viewfinder, _controls(false)]);
    })));
  }
}
