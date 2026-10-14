import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/camera_settings.dart';
import '../models/filter_preset.dart';
import '../services/filter_service.dart';
import '../services/video_filter_service.dart';
import '../widgets/filter_selector.dart';
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
  final _filterService = FilterService();
  final _videoFilterService = VideoFilterService();
  Uint8List? _capturedOriginal;
  String _capturedRatio = '4:3';
  bool _capturedDualSave = false;
  String _recordFilterId = 'original';
  String _recordRatio = '16:9';
  bool _recordPortrait = true;
  double _recordFilterStrength = 1;
  bool _recordDualSave = false;
  String _filterId = 'original';
  double _filterStrength = 1.0;
  bool _filterPanelVisible = false;
  CameraSettings _settings = const CameraSettings();
  bool _ready = false;
  bool _cameraTransition = false;
  bool _background = false;
  bool _pageDisposed = false;
  int _cameraEpoch = 0;
  String _cameraStatus = '카메라 준비 중';
  String? _cameraError;
  int _processingVideos = 0;
  String? _videoSaveStatus;
  bool _videoMode = false;
  bool _recording = false;
  bool _recordingBusy = false;
  bool _microphone = true;
  DateTime? _recordingStarted;
  Timer? _recordingTicker;
  Duration _recordedDuration = Duration.zero;
  bool _busy = false;
  bool _showPreview = false;
  bool _savingPreview = false;
  Uint8List? _captured;
  double _zoom = 1, _minZoom = 1, _maxZoom = 1;
  bool _zoomSliderVisible = false;
  bool _timerCancelled = false;
  FlashMode _flash = FlashMode.off;
  int _timer = 0, _countdown = 0;
  String _photoRatio = '4:3';
  String _videoRatio = '16:9';
  String get _ratio => _videoMode ? _videoRatio : _photoRatio;
  Offset? _focusPoint;
  int _focusToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    if (_pageDisposed || _background || _cameraTransition) return;
    final epoch = ++_cameraEpoch;
    if (mounted) setState(() {
      _cameraTransition = true;
      _ready = false;
      _cameraError = null;
      _cameraStatus = '카메라 준비 중';
    });
    try {
      _settings = await _settingsService.load();
      final savedFilter = await _settingsService.loadFilter();
      _filterId = CameraFilters.byId(savedFilter.$1).id;
      _filterStrength = savedFilter.$2;
      // Remove any old preview from the widget tree before CameraX rebuilds.
      if (mounted) await WidgetsBinding.instance.endOfFrame;
      if (_pageDisposed || _background || epoch != _cameraEpoch) return;
      await _camera.initialize();
      if (_pageDisposed || _background || epoch != _cameraEpoch) return;
      _syncZoom();
      if (mounted) setState(() {
        _videoMode = _camera.videoMode;
        _microphone = _camera.microphoneEnabled;
        _ready = true;
      });
    } catch (e) {
      if (!_pageDisposed && !_background && epoch == _cameraEpoch) {
        if (mounted) setState(() => _cameraError = '$e');
        _message('카메라 초기화 실패: $e');
      }
    } finally {
      if (mounted && epoch == _cameraEpoch) {
        setState(() => _cameraTransition = false);
      }
    }
  }

  void _syncZoom() {
    _minZoom = _camera.minZoom;
    _maxZoom = _camera.maxZoom;
    _zoom = 1.0.clamp(_minZoom, _maxZoom).toDouble();
    _zoomSliderVisible = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_pageDisposed) return;
    if (state == AppLifecycleState.inactive) {
      // Permission dialogs and notification overlays may cause 'inactive'.
      // Disposing here races the CameraX preview's surface initialization.
      _timerCancelled = true;
      return;
    }
    if (state == AppLifecycleState.paused) {
      _background = true;
      ++_cameraEpoch;
      _timerCancelled = true;
      if (mounted) setState(() {
        _ready = false;
        _cameraTransition = false;
      });
      if (_recording) {
        unawaited(_stopRecording()); // Stop & save before closing the camera.
      } else {
        unawaited(_camera.dispose());
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _background = false;
      if (!_ready && !_cameraTransition && !_recording && !_recordingBusy) {
        unawaited(_initialize());
      }
    }
  }

  @override
  void dispose() {
    _pageDisposed = true;
    ++_cameraEpoch;
    WidgetsBinding.instance.removeObserver(this);
    _recordingTicker?.cancel();
    unawaited(_camera.dispose());
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
    if (_cameraTransition || _busy || !_ready || _recording || _recordingBusy) return;
    _timerCancelled = true;
    final epoch = ++_cameraEpoch;
    setState(() {
      _cameraTransition = true;
      _cameraStatus = '카메라 전환 중';
      _cameraError = null;
      _ready = false;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (_pageDisposed || _background) return;
      await _camera.switchCamera();
      if (_pageDisposed || _background || epoch != _cameraEpoch) return;
      _syncZoom();
      _flash = FlashMode.off;
    } catch (e) {
      if (!_background) _message('카메라 전환 실패: $e');
    } finally {
      if (mounted && epoch == _cameraEpoch) {
        setState(() {
          _cameraTransition = false;
          _ready = !_background &&
              (_camera.controller?.value.isInitialized ?? false);
          if (!_ready && !_background) _cameraError = '렌즈 초기화에 실패했어요.';
        });
      }
    }
  }

  Future<void> _cycleFlash() async {
    if (!_ready || _cameraTransition || _recordingBusy || _busy) return;
    // Video supports a continuous torch, not the still-photo auto/always modes.
    const photoModes = [FlashMode.off, FlashMode.auto, FlashMode.always, FlashMode.torch];
    final next = _videoMode
        ? (_flash == FlashMode.torch ? FlashMode.off : FlashMode.torch)
        : photoModes[(photoModes.indexOf(_flash) + 1) % photoModes.length];
    try {
      await _camera.setFlash(next);
      if (mounted) setState(() => _flash = next);
    } catch (_) {
      _message('이 카메라는 해당 플래시 모드를 지원하지 않습니다.');
    }
  }

  int _pendingSaves = 0;

  Future<void> _capture() async {
    if (_busy || !_ready || _cameraTransition || _videoMode || _recordingBusy) return;
    if (_pendingSaves >= 3 && !_settings.showCapturePreview && !_settings.askBeforeSaving) {
      _message('저장 작업이 밀려 있어요. 잠시 후 촬영해 주세요.');
      return;
    }
    _timerCancelled = false;
    setState(() { _busy = true; _countdown = _timer; _zoomSliderVisible = false; });
    try {
      for (int remaining = _timer; remaining > 0; remaining--) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted || !_ready || _timerCancelled) return;
        setState(() => _countdown = remaining - 1);
      }
      // Snapshot all settings BEFORE allowing another capture.
      final ratio = _ratio;
      final preset = CameraFilters.byId(_filterId);
      final strength = _filterStrength;
      final showPreview = _settings.showCapturePreview;
      final ask = _settings.askBeforeSaving;
      final dualSave = _settings.saveOriginalAlongsideFilter && preset.id != 'original' && strength > 0;
      final photo = await _camera.takePicture();
      // Auto-save: camera is usable again immediately after capture.
      // JPEG processing and gallery I/O continue asynchronously.
      if (!showPreview && !ask) {
        setState(() => _pendingSaves++);
        unawaited(_processAndSave(photo.readAsBytes(), ratio, preset, strength, dualSave));
        return;
      }
      final rawBytes = await photo.readAsBytes();
      final bytes = await _filterService.processCapture(rawBytes, ratio, preset, strength);
      _capturedOriginal = dualSave ? rawBytes : null;
      _capturedRatio = ratio;
      _capturedDualSave = dualSave;
      if (!mounted) return;
      if (showPreview) {
        setState(() { _captured = bytes; _showPreview = true; });
      } else {
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
      }
    } catch (e) {
      _message('촬영 실패: $e');
    } finally {
      if (mounted) setState(() { _busy = false; _countdown = 0; });
    }
  }

  Future<void> _processAndSave(Future<Uint8List> readBytes,
      String ratio, FilterPreset preset, double strength, bool dualSave) async {
    try {
      final original = await readBytes;
      final bytes = await _filterService.processCapture(original, ratio, preset, strength);
      await _savePair(bytes, dualSave ? original : null, ratio, preset.id);
      // No modal snackbar for every shot: the saving indicator vanishes when done.
    } catch (e) {
      _message('사진 저장 실패: $e');
    } finally {
      if (mounted) {
        setState(() { if (_pendingSaves > 0) _pendingSaves--; });
      } else if (_pendingSaves > 0) {
        _pendingSaves--;
      }
    }
  }

  Future<void> _save(Uint8List bytes) async {
    if (_savingPreview) return;
    if (mounted) setState(() => _savingPreview = true);
    try {
      await _savePair(bytes, _capturedDualSave ? _capturedOriginal : null, _capturedRatio, _filterId);
      if (mounted) setState(() { _showPreview = false; _captured = null; _capturedOriginal = null; });
      _message('갤러리에 저장했어요.');
    } catch (e) {
      _message('사진 저장 실패: $e');
    } finally {
      if (mounted) setState(() => _savingPreview = false);
    }
  }

  Future<void> _savePair(Uint8List filtered, Uint8List? original,
      String ratio, String filterId) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final base = 'IMG_$stamp';
    await _storage.saveToGallery(filtered, name: '${base}_${filterId.toUpperCase()}.jpg');
    if (original != null) {
      // Match the selected aspect ratio, but do not apply the color filter.
      final originalPreset = CameraFilters.byId('original');
      final cropped = await _filterService.processCapture(original, ratio, originalPreset, 0);
      await _storage.saveToGallery(cropped, name: '${base}_ORIGINAL.jpg');
    }
  }

  Future<void> _tapToFocus(TapDownDetails details, Size viewSize) async {
    if (_busy || !_ready || viewSize.width == 0 || viewSize.height == 0) return;
    final local = details.localPosition;
    final x = (local.dx / viewSize.width).clamp(0.0, 1.0);
    final y = (local.dy / viewSize.height).clamp(0.0, 1.0);
    final token = ++_focusToken;
    setState(() => _focusPoint = Offset(local.dx, local.dy));
    try {
      final result = await _camera.focusAt(x, y);
      if (!result) _message('이 렌즈에서는 터치 초점 위치를 지원하지 않을 수 있습니다.');
    } catch (e) {
      _message('초점 설정 실패: $e');
    }
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
          ColorFiltered(
            // Lightweight live preview. Video export uses FFmpeg to approximate
            // the selected preset; live preview and exported MP4 can differ.
            colorFilter: CameraFilters.colorFilter(
              CameraFilters.byId(_recording ? _recordFilterId : _filterId),
              _recording ? _recordFilterStrength : _filterStrength),
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: cameraRatio * 1000,
                height: 1000,
                child: CameraPreview(controller),
              ),
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

  Future<void> _setVideoMode(bool enabled) async {
    if (_cameraTransition || _recording || _recordingBusy || _busy ||
        !_ready || _videoMode == enabled) return;
    final epoch = ++_cameraEpoch;
    setState(() {
      _cameraTransition = true;
      _cameraStatus = enabled ? '동영상 모드 준비 중' : '사진 모드 준비 중';
      _cameraError = null;
      _ready = false;
      _filterPanelVisible = false;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (_pageDisposed || _background) return;
      await _camera.configureVideo(enabled: enabled, microphone: _microphone);
      if (_pageDisposed || _background || epoch != _cameraEpoch) return;
      _syncZoom();
      _flash = FlashMode.off;
      if (mounted) setState(() => _videoMode = enabled);
    } catch (e) {
      if (!_background) _message('촬영 모드 변경 실패: $e');
    } finally {
      if (mounted && epoch == _cameraEpoch) {
        setState(() {
          _cameraTransition = false;
          _ready = !_background &&
              (_camera.controller?.value.isInitialized ?? false);
          if (!_ready && !_background) _cameraError = '촬영 모드 초기화에 실패했어요.';
        });
      }
    }
  }

  Future<void> _toggleMicrophone() async {
    if (_cameraTransition || !_ready || !_videoMode || _recording || _recordingBusy) return;
    final next = !_microphone;
    final epoch = ++_cameraEpoch;
    setState(() {
      _cameraTransition = true;
      _cameraStatus = '마이크 설정 적용 중';
      _cameraError = null;
      _ready = false;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (_pageDisposed || _background) return;
      await _camera.configureVideo(enabled: true, microphone: next);
      if (_pageDisposed || _background || epoch != _cameraEpoch) return;
      if (mounted) setState(() => _microphone = next);
    } catch (e) {
      if (!_background) _message('마이크 설정 실패: $e');
    } finally {
      if (mounted && epoch == _cameraEpoch) {
        setState(() {
          _cameraTransition = false;
          _ready = !_background &&
              (_camera.controller?.value.isInitialized ?? false);
          if (!_ready && !_background) _cameraError = '마이크 설정을 적용하지 못했어요.';
        });
      }
    }
  }

  Future<void> _startRecording() async {
    if (!_videoMode || !_ready || _cameraTransition || _recording || _recordingBusy) return;
    _timerCancelled = false;
    setState(() {
      _recordingBusy = true;
      _countdown = _timer;
      _zoomSliderVisible = false;
    });
    try {
      for (int remaining = _timer; remaining > 0; remaining--) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted || !_ready || _timerCancelled || !_videoMode || _background) return;
        setState(() => _countdown = remaining - 1);
      }
      if (!mounted || !_ready || _timerCancelled || _background) return;
      _recordFilterId = _filterId;
      _recordRatio = _videoRatio;
      _recordPortrait = MediaQuery.orientationOf(context) == Orientation.portrait;
      _recordFilterStrength = _filterStrength;
      _recordDualSave = _settings.saveOriginalAlongsideFilter;
      if (mounted) setState(() => _filterPanelVisible = false);
      await _camera.startVideo();
      _recordingStarted = DateTime.now();
      _recordedDuration = Duration.zero;
      _recordingTicker?.cancel();
      _recordingTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted && _recordingStarted != null) {
          setState(() => _recordedDuration = DateTime.now().difference(_recordingStarted!));
        }
      });
      if (mounted) setState(() => _recording = true);
    } catch (e) {
      _message('동영상 녹화 시작 실패: $e');
    } finally {
      if (mounted) setState(() {
        _recordingBusy = false;
        _countdown = 0;
      });
      if (_background && _recording) unawaited(_stopRecording());
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording || _recordingBusy) return;
    _recordingTicker?.cancel();
    setState(() => _recordingBusy = true);
    try {
      final video = await _camera.stopVideo();
      if (mounted) setState(() => _recording = false);
      // Save and transcode in the background. Don't block the shutter on FFmpeg.
      unawaited(_publishVideo(video.path, _recordFilterId, _recordFilterStrength,
          _recordDualSave, _recordRatio, _recordPortrait));
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        await _camera.dispose();
        if (mounted) setState(() => _ready = false);
      }
    } catch (e) {
      _message('동영상 녹화 종료 실패: $e');
    } finally {
      _recordingStarted = null;
      if (mounted) setState(() => _recordingBusy = false);
      if (!_background && !_ready && !_cameraTransition && !_pageDisposed) {
        unawaited(_initialize());
      }
    }
  }

  Future<void> _publishVideo(String path, String filterId,
      double strength, bool dualSave, String ratio, bool portrait) async {
    final temporaryFiles = <String>{};
    if (mounted) setState(() {
      _processingVideos++;
      _videoSaveStatus = '동영상 저장 준비 중';
    });
    try {
      final preset = CameraFilters.byId(filterId);
      final filtered = preset.id != 'original' && strength > 0;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final base = 'VID_$stamp';
      // Standard CameraX recordings are 16:9. Other selected ratios need a
      // real crop in the exported file, not just a clipped camera preview.
      final cropNeeded = ratio != '16:9';
      if (filtered) {
        if (mounted) setState(() => _videoSaveStatus = '동영상 필터 처리 중 · 촬영 가능');
        final result = await _videoFilterService.render(path, preset, strength,
            ratio: ratio, portrait: portrait);
        if (result != path) temporaryFiles.add(result);
        if (mounted) setState(() => _videoSaveStatus = '갤러리에 동영상 저장 중');
        await _storage.saveVideoToGallery(result,
            name: '${base}_${filterId.toUpperCase()}.mp4');
        if (dualSave) {
          var originalPath = path;
          if (cropNeeded) {
            if (mounted) setState(() => _videoSaveStatus = '원본 비율 맞추는 중 · 촬영 가능');
            originalPath = await _videoFilterService.render(path,
                CameraFilters.byId('original'), 0,
                ratio: ratio, portrait: portrait);
            if (originalPath != path) temporaryFiles.add(originalPath);
          }
          await _storage.saveVideoToGallery(originalPath,
              name: '${base}_ORIGINAL.mp4');
        }
      } else {
        final result = await _videoFilterService.render(path, preset, strength,
            ratio: ratio, portrait: portrait);
        if (result != path) temporaryFiles.add(result);
        await _storage.saveVideoToGallery(result, name: '${base}_ORIGINAL.mp4');
      }
    } catch (e) {
      // Never publish an unfiltered clip under a filter name on processing error.
      _message('동영상 처리 실패: $e (원본 임시 파일 확인 필요)');
    } finally {
      for (final filePath in temporaryFiles) {
        try { await File(filePath).delete(); } catch (_) {}
      }
      // Camera plugin source is retained, to avoid losing a failed recording.
      if (mounted) setState(() {
        if (_processingVideos > 0) _processingVideos--;
        if (_processingVideos == 0) _videoSaveStatus = null;
      });
    }
  }

  String get _recordingTime {
    final minutes = _recordedDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _recordedDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _shutter() => GestureDetector(
    onTap: (_cameraTransition || !_ready || _recordingBusy || (_busy && !_videoMode))
        ? null
        : (_videoMode ? (_recording ? _stopRecording : _startRecording) : _capture),
    child: Container(
      width: 72, height: 72,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
      child: Center(child: Container(
        width: 54, height: 54,
        decoration: BoxDecoration(shape: BoxShape.circle, color: _recording ? Colors.red : (_videoMode ? Colors.redAccent : (_busy || _recordingBusy ? Colors.white38 : Colors.white))),
      )),
    ),
  );

  Future<void> _setZoom(double value) async {
    final target = value.clamp(_minZoom, _maxZoom).toDouble();
    if (mounted) setState(() => _zoom = target);
    try {
      await _camera.setZoom(target);
    } catch (e) {
      _message('줌 설정 실패: $e');
    }
  }

  Widget _zoomSelector() {
    final stops = <double>[];
    for (final v in [_minZoom, 0.6, 1.0, 2.0, 3.0, 5.0, _maxZoom]) {
      if (v >= _minZoom && v <= _maxZoom &&
          !stops.any((s) => (s - v).abs() < 0.05)) stops.add(v);
    }
    stops.sort();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(height: 43, child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(mainAxisSize: MainAxisSize.min, children: stops.map((value) {
          final selected = (_zoom - value).abs() < 0.06;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              label: Text('${value.toStringAsFixed( value == value.roundToDouble() ? 0 : 1)}x'),
              backgroundColor: selected ? const Color(0xFFD8B88A) : Colors.black54,
              labelStyle: TextStyle(color: selected ? Colors.black : Colors.white),
              onPressed: () {
                if (selected) {
                  setState(() => _zoomSliderVisible = !_zoomSliderVisible);
                } else {
                  setState(() => _zoomSliderVisible = true);
                  _setZoom(value);
                }
              },
            ),
          );
        }).toList()),
      )),
      if (_zoomSliderVisible)
        Row(children: [
          IconButton(
            onPressed: () => setState(() => _zoomSliderVisible = false),
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            tooltip: '줌 슬라이더 닫기',
          ),
          Expanded(child: Slider(
            min: _minZoom,
            max: _maxZoom > _minZoom ? _maxZoom : _minZoom + 0.001,
            value: _zoom.clamp(_minZoom, _maxZoom > _minZoom ? _maxZoom : _minZoom + 0.001).toDouble(),
            onChanged: _maxZoom > _minZoom ? (v) => _setZoom(v) : null,
          )),
          SizedBox(width: 54, child: Text('${_zoom.toStringAsFixed(1)}x',
            style: const TextStyle(color: Colors.white))),
        ]),
    ]);
  }

  void _updateFilter(String id, double strength) {
    if (_recording || _recordingBusy || _cameraTransition) return;
    setState(() { _filterId = id; _filterStrength = strength; });
    _settingsService.saveFilter(id, strength);
  }

  Widget _filterPanel() => FilterSelector(
    selectedId: _filterId,
    strength: _filterStrength,
    onSelected: (id) => _updateFilter(id, _filterStrength),
    onStrengthChanged: (v) => _updateFilter(_filterId, v),
  );

  void _cycleRatio() {
    if (!_ready || _cameraTransition || _recording || _recordingBusy || _busy) return;
    const values = ['4:3', '16:9', '1:1'];
    final current = _ratio;
    final next = values[(values.indexOf(current) + 1) % values.length];
    setState(() {
      if (_videoMode) {
        _videoRatio = next;
      } else {
        _photoRatio = next;
      }
    });
  }

  Widget _controls(bool landscape) {
    final timer = _control(Icons.timer_outlined,
        _timer == 0 ? '타이머 OFF' : '$_timer초', () {
      if (!_ready || _cameraTransition || _recording || _recordingBusy || _busy) return;
      const values = [0, 3, 5, 10];
      setState(() => _timer = values[(values.indexOf(_timer) + 1) % values.length]);
    });
    final ratio = _control(Icons.aspect_ratio, _ratio, _cycleRatio);
    final flip = _control(Icons.cameraswitch_outlined, '전환', _switchCamera);
    final grid = _control(_settings.showGrid ? Icons.grid_on : Icons.grid_off,
        '그리드', () async {
      if (_cameraTransition || _recordingBusy) return;
      final next = _settings.copyWith(showGrid: !_settings.showGrid);
      setState(() => _settings = next);
      await _settingsService.save(next);
    });
    final flashIcon = _flash == FlashMode.off
        ? Icons.flash_off
        : (_flash == FlashMode.auto ? Icons.flash_auto : Icons.flash_on);
    final flash = _control(flashIcon, _videoMode ? '라이트' : '플래시', _cycleFlash);
    final gallery = _control(Icons.photo_library_outlined, '갤러리', () {
      if (_cameraTransition || _recording || _recordingBusy) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => const GalleryScreen()));
    });
    final settings = _control(Icons.settings_outlined, '설정', () {
      if (_cameraTransition || _recording || _recordingBusy) return;
      _openSettings();
    });
    final filters = _control(Icons.auto_fix_high,
        _filterPanelVisible ? '필터 닫기' : '필터', () {
      if (_recording || _recordingBusy || _cameraTransition) return;
      setState(() => _filterPanelVisible = !_filterPanelVisible);
    });
    final microphone = _control(_microphone ? Icons.mic : Icons.mic_off,
        _microphone ? '마이크' : '무음', _toggleMicrophone);

    // Keep the same common controls, in the same order, for both modes.
    // Video-only microphone remains separate; it has no meaning in photo mode.
    if (landscape) {
      return Container(
        color: Colors.black87,
        width: 180,
        child: SingleChildScrollView(child: Column(children: [
          const SizedBox(height: 8),
          gallery, flash, timer, ratio, grid, filters, settings,
          if (_videoMode) microphone,
          if (_filterPanelVisible && !_recording)
            SizedBox(width: 180, child: _filterPanel()),
          const SizedBox(height: 8),
          _zoomSelector(),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            TextButton(
              onPressed: _recording || _recordingBusy ? null : () => _setVideoMode(false),
              child: Text('사진', style: TextStyle(
                  color: !_videoMode ? Colors.amber : Colors.white70))),
            TextButton(
              onPressed: _recording || _recordingBusy ? null : () => _setVideoMode(true),
              child: Text('동영상', style: TextStyle(
                  color: _videoMode ? Colors.amber : Colors.white70))),
          ]),
          _shutter(),
          if (_recording) Text(_recordingTime,
              style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 8), flip,
        ])),
      );
    }
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // A fixed five-control row avoids overflow when both modes show ratio.
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          gallery, flash, timer, ratio, settings,
        ]),
        Row(children: [
          Expanded(child: Center(child: grid)),
          Expanded(child: Center(child: filters)),
          Expanded(child: Center(child: _videoMode
              ? microphone : const SizedBox.shrink())),
        ]),
        _zoomSelector(),
        if (_filterPanelVisible) _filterPanel(),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton(
            onPressed: _recording || _recordingBusy ? null : () => _setVideoMode(false),
            child: Text('사진', style: TextStyle(
                color: !_videoMode ? Colors.amber : Colors.white70))),
          const SizedBox(width: 18),
          _shutter(),
          const SizedBox(width: 18),
          TextButton(
            onPressed: _recording || _recordingBusy ? null : () => _setVideoMode(true),
            child: Text('동영상', style: TextStyle(
                color: _videoMode ? Colors.amber : Colors.white70))),
          flip,
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _camera.controller;
    if (!_ready || controller == null || !controller.value.isInitialized) {
      return Scaffold(body: SafeArea(child: Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_cameraError == null) ...[
            const SizedBox(width: 32, height: 32,
              child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 18),
            Text(_cameraStatus),
          ] else ...[
            const Icon(Icons.camera_alt_outlined, size: 40, color: Colors.white70),
            const SizedBox(height: 14),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_cameraError!, textAlign: TextAlign.center)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _cameraTransition ? null : _initialize,
              child: const Text('카메라 다시 연결')),
          ],
        ],
      ))));
    }
    if (_showPreview && _captured != null) {
      return Scaffold(body: SafeArea(child: Stack(fit: StackFit.expand, children: [
        Image.memory(_captured!, fit: BoxFit.contain),
        Positioned(top: 8, left: 8, child: IconButton(
          onPressed: _savingPreview ? null : () => setState(() {
            _showPreview = false; _captured = null; _capturedOriginal = null;
          }),
          icon: const Icon(Icons.close),
        )),
        Positioned(bottom: 16, left: 20, right: 20, child: Row(children: [
          Expanded(child: OutlinedButton(onPressed: _savingPreview ? null : () => setState(() {
            _showPreview = false; _captured = null; _capturedOriginal = null;
          }), child: const Text('다시 촬영'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(
            onPressed: _savingPreview ? null : () => _save(_captured!),
            child: _savingPreview
                ? const SizedBox(height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('저장'))),
        ])),
      ])));
    }
    return Scaffold(body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
      final landscape = constraints.maxWidth > constraints.maxHeight;
      final viewfinder = Expanded(child: Stack(fit: StackFit.expand, children: [
        _viewfinder(controller),
        if (_pendingSaves > 0 || _processingVideos > 0)
          Positioned(top: 12, right: 12, child: IgnorePointer(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(color: Colors.black87,
              borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 13, height: 13,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)),
              const SizedBox(width: 9),
              Text(_processingVideos > 0
                  ? (_videoSaveStatus ?? '동영상 저장 중')
                  : '사진 저장 중 ($_pendingSaves)',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ))),
        if (_recording) Positioned(top: 12, left: 12, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: Colors.black54,
          child: Text('● REC  $_recordingTime', style: const TextStyle(
            color: Colors.redAccent, fontWeight: FontWeight.bold)),
        )),
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

