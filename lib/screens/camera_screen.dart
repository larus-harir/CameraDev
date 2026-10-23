import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/camera_settings.dart';
import '../models/camera_style.dart';
import '../widgets/camera_chrome.dart';
import '../widgets/frame_artwork.dart';
import '../widgets/zoom_dial.dart';
import '../widgets/focus_indicator.dart';
import '../models/filter_preset.dart';
import '../services/filter_service.dart';
import '../services/video_filter_service.dart';
import '../services/camera_service.dart';
import '../services/lens_catalog.dart';
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
  CameraStyle _style = CameraStyle.digital;
  String _digitalId = 'digital_s';
  String _filmId = 'preset_01';
  double _digitalStrength = 1;
  double _filmStrength = 1;
  bool _advancedVisible = false;
  bool _capturedFrame = false;
  String _capturedFilterId = 'original';
  bool _recordFrameExport = false;
  CameraStyle _recordStyle = CameraStyle.digital;
  int _recordFrameNumber = 1;
  double _recordZoom = 1.0;
  DateTime _recordDate = DateTime.now();
  String _recordLook = '';
  int _filmFrameCounter = 1;
  Timer? _lookSaveDebounce;
  String _filterId = 'digital_s';
  double _filterStrength = 1.0;
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
  bool _zoomApplying = false;
  double? _zoomTarget;
  Timer? _zoomFlushTimer;
  DateTime _lastZoomCommand = DateTime.fromMillisecondsSinceEpoch(0);
  int _zoomCommandDurationMs = 0;
  bool _timerCancelled = false;
  FlashMode _flash = FlashMode.off;
  int _timer = 0, _countdown = 0;
  String _photoRatio = '4:3';
  String _videoRatio = '16:9';
  String get _ratio => _videoMode ? _videoRatio : _photoRatio;
  Offset? _focusPoint;
  bool _focusVisible = false;
  Timer? _focusHideTimer;
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
      _filmFrameCounter = await _settingsService.loadFilmCounter();
      final look = await _settingsService.loadLook();
      _style = look.style;
      _digitalId = CameraFilters.digitalPresets.any((p) => p.id == look.digitalId)
          ? look.digitalId : 'digital_s';
      _filmId = CameraFilters.presets.any((p) => p.id == look.filmId)
          ? look.filmId : 'preset_01';
      _digitalStrength = look.digitalStrength;
      _filmStrength = look.filmStrength;
      _filterId = _style == CameraStyle.digital ? _digitalId : _filmId;
      _filterStrength = _style == CameraStyle.digital ? _digitalStrength : _filmStrength;
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
    _zoomFlushTimer?.cancel();
    _zoomTarget = null;
    _zoomCommandDurationMs = 0;
    final optical = _camera.opticalFactor;
    _minZoom = _camera.minZoom * optical;
    _maxZoom = math.min(30.0, _camera.maxZoom * optical);
    _zoom = optical.clamp(_minZoom, _maxZoom).toDouble();
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
    _zoomFlushTimer?.cancel();
    _focusHideTimer?.cancel();
    if (_lookSaveDebounce?.isActive ?? false) {
      _lookSaveDebounce?.cancel();
      _saveLook(immediate: true);
    }
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
  // One photo-processing isolate at a time avoids memory pressure and CPU
  // contention from decoding several multi-megapixel JPEGs simultaneously.
  // The shutter stays available while queued photos finish in the background.
  Future<void> _photoSaveQueue = Future<void>.value();

  void _queuePhotoSave(String path, String ratio, FilterPreset preset,
      double strength, bool dualSave,
      Future<Uint8List> Function()? renderFrame, bool frame) {
    _photoSaveQueue = _photoSaveQueue.then((_) => _processAndSave(
        path, ratio, preset, strength, dualSave, renderFrame, frame));
  }


  Future<void> _capture() async {
    if (_busy || !_ready || _cameraTransition || _videoMode || _recordingBusy) return;
    if (_pendingSaves >= 3 && !_settings.showCapturePreview && !_settings.askBeforeSaving) {
      _message('저장 작업이 밀려 있어요. 잠시 후 촬영해 주세요.');
      return;
    }
    _timerCancelled = false;
    setState(() { _busy = true; _countdown = _timer; _advancedVisible = false; });
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
      final style = _style;
      // CH.4 v8: keep the frame-export option and rendering pipeline for
      // future design work, but export no decorative frame for now.
      const frame = false;
      final shotFrame = _filmFrameCounter;
      final shotZoom = _zoom;
      final shotDate = DateTime.now();
      final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
      final shotTimer = Stopwatch()..start();
      final photo = await _camera.takePicture();
      debugPrint('[CameraPerf] camera.takePicture: '
          '${shotTimer.elapsedMilliseconds} ms');
      if (style == CameraStyle.film) {
        _filmFrameCounter = _filmFrameCounter >= 9999 ? 1 : _filmFrameCounter + 1;
        unawaited(_settingsService.saveFilmCounter(_filmFrameCounter));
      }
      // Auto-save: camera is usable again immediately after capture.
      // JPEG processing and gallery I/O continue asynchronously.
      // Defer expensive PNG frame rasterization and JPEG file reading until
      // the queued save starts, rather than holding up the next shutter press.
      Future<Uint8List> Function()? renderFrame = frame
          ? () => renderFrameArtworkPng(
              style: style, look: preset.label, ratio: ratio,
              zoom: shotZoom, frameNumber: shotFrame, date: shotDate,
              portrait: portrait)
          : null;
      if (!showPreview && !ask) {
        setState(() => _pendingSaves++);
        _queuePhotoSave(photo.path, ratio, preset,
            strength, dualSave, renderFrame, frame);
        return;
      }
      final rawBytes = await photo.readAsBytes();
      final bytes = await _filterService.processCapture(
          rawBytes, ratio, preset, strength,
          frameArtwork: renderFrame == null ? null : await renderFrame());
      _capturedOriginal = dualSave ? rawBytes : null;
      _capturedRatio = ratio;
      _capturedDualSave = dualSave;
      _capturedFrame = frame;
      _capturedFilterId = preset.id;
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

  Future<void> _processAndSave(String photoPath,
      String ratio, FilterPreset preset, double strength, bool dualSave,
      Future<Uint8List> Function()? renderFrame, bool frame) async {
    final elapsed = Stopwatch()..start();
    try {
      final original = await File(photoPath).readAsBytes();
      final bytes = await _filterService.processCapture(
          original, ratio, preset, strength,
          frameArtwork: renderFrame == null ? null : await renderFrame());
      final editMs = elapsed.elapsedMilliseconds;
      await _savePair(bytes, dualSave ? original : null, ratio, preset.id, frame: frame);
      debugPrint('[CameraPerf] photo edit=$editMs ms, gallery='
          '${elapsed.elapsedMilliseconds - editMs} ms');
      // No modal snackbar for every shot: the saving indicator vanishes when done.
    } catch (e) {
      _message('사진 저장 실패: $e');
    } finally {
      debugPrint('[CameraPerf] photo processed + gallery save: '
          '${elapsed.elapsedMilliseconds} ms');
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
      await _savePair(bytes, _capturedDualSave ? _capturedOriginal : null, _capturedRatio, _capturedFilterId, frame: _capturedFrame);
      if (mounted) setState(() { _showPreview = false; _captured = null; _capturedOriginal = null; });
      _message('갤러리에 저장했어요.');
    } catch (e) {
      _message('사진 저장 실패: $e');
    } finally {
      if (mounted) setState(() => _savingPreview = false);
    }
  }

  Future<void> _savePair(Uint8List filtered, Uint8List? original,
      String ratio, String filterId, {bool frame = false}) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final base = 'IMG_$stamp';
    await _storage.saveToGallery(filtered, name: '${base}_${frame ? 'FRAME_' : ''}${filterId.toUpperCase()}.jpg');
    if (original != null) {
      // Match the selected aspect ratio, but do not apply the color filter.
      final originalPreset = CameraFilters.byId('original');
      final cropped = await _filterService.processCapture(original, ratio, originalPreset, 0);
      await _storage.saveToGallery(cropped, name: '${base}_ORIGINAL.jpg');
    }
  }

  Future<void> _tapToFocus(TapDownDetails details, Size viewSize,
      double sourceAspectRatio) async {
    if (!_ready || _cameraTransition || _background ||
        viewSize.width <= 0 || viewSize.height <= 0) return;
    final local = details.localPosition;
    final token = ++_focusToken;
    _focusHideTimer?.cancel();
    // Display feedback immediately; do not wait for Android's focus command.
    setState(() {
      _focusPoint = local;
      _focusVisible = true;
    });
    _focusHideTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted && token == _focusToken) {
        setState(() => _focusVisible = false);
      }
    });

    // CameraPreview uses BoxFit.cover. Match its center crop when mapping a
    // user's visible tap back to camera plugin's normalized focus coordinates.
    const sourceHeight = 1000.0;
    final sourceWidth = sourceAspectRatio * sourceHeight;
    final scale = math.max(viewSize.width / sourceWidth,
        viewSize.height / sourceHeight);
    final fittedWidth = sourceWidth * scale;
    final fittedHeight = sourceHeight * scale;
    final x = ((local.dx + (fittedWidth - viewSize.width) / 2) / fittedWidth)
        .clamp(0.0, 1.0).toDouble();
    final y = ((local.dy + (fittedHeight - viewSize.height) / 2) / fittedHeight)
        .clamp(0.0, 1.0).toDouble();
    try {
      final supported = await _camera.focusAt(x, y);
      if (!supported && mounted && token == _focusToken) {
        _message('현재 렌즈에서 터치 초점 설정을 지원하지 않습니다.');
      }
    } catch (e) {
      if (mounted && token == _focusToken) _message('초점 설정 실패: $e');
    }
  }

  Widget _viewfinder(CameraController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: LayoutBuilder(builder: (context, constraints) {
      final portrait = constraints.maxHeight >= constraints.maxWidth;
      final landscapeRatio = _ratio == '1:1' ? 1.0 : _ratio == '16:9' ? 16 / 9 : 4 / 3;
      final targetRatio = portrait ? 1 / landscapeRatio : landscapeRatio;
      // Reserve space for a physical-camera-style bezel around the image.
      // The inner viewfinder preserves its aspect ratio: no stretching.
      final available = Size(
        (constraints.maxWidth - 9).clamp(1.0, double.infinity).toDouble(),
        (constraints.maxHeight - 9).clamp(1.0, double.infinity).toDouble(),
      );
      final frameWidth = available.width < available.height * targetRatio
          ? available.width : available.height * targetRatio;
      final frameHeight = frameWidth / targetRatio;
      final cameraRatio = portrait ? 1 / controller.value.aspectRatio : controller.value.aspectRatio;
      // Pin the viewfinder toward the top when there is spare vertical room;
      // the lower space becomes an ergonomic thumb zone for the zoom dial.
      return Align(
        alignment: portrait ? Alignment.topCenter : Alignment.center,
        child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: CameraPalette.raised,
          border: Border.all(color: CameraPalette.stroke, width: .85),
          borderRadius: BorderRadius.circular(9),
          boxShadow: const [BoxShadow(
            color: Color(0x85000000), blurRadius: 14, offset: Offset(0, 5)),
          ],
        ),
        child: SizedBox(
        width: frameWidth,
        height: frameHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(fit: StackFit.expand, children: [
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
            onTapDown: (details) => _tapToFocus(
                details, Size(box.maxWidth, box.maxHeight), cameraRatio),
            child: Stack(children: [
              if (_focusPoint != null)
                Positioned(
                  left: (_focusPoint!.dx - 27).clamp(
                      0.0, math.max(0.0, box.maxWidth - 54)).toDouble(),
                  top: (_focusPoint!.dy - 27).clamp(
                      0.0, math.max(0.0, box.maxHeight - 54)).toDouble(),
                  child: CameraFocusIndicator(
                      sequence: _focusToken, visible: _focusVisible),
                ),
            ]),
          )),
          // Decorative frame deliberately removed in v8. This leaves the
          // full live photograph unobstructed; frame_artwork.dart remains for
          // a future, separately reviewed design.
        ])),
        ),
      ));
    }),
    );
  }

  Future<void> _setVideoMode(bool enabled) async {
    if (_cameraTransition || _recording || _recordingBusy || _busy ||
        !_ready || _videoMode == enabled) return;
    final epoch = ++_cameraEpoch;
    setState(() {
      _cameraTransition = true;
      _cameraStatus = enabled ? '동영상 모드 준비 중' : '사진 모드 준비 중';
      _cameraError = null;
      _ready = false;
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
      _advancedVisible = false;
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
      _recordStyle = _style;
      _recordFrameNumber = _filmFrameCounter;
      _recordZoom = _zoom;
      _recordDate = DateTime.now();
      _recordLook = CameraFilters.byId(_filterId).label;
      // Frame designs are temporarily disabled in preview AND in exports.
      // The setting and frame rendering pipeline remain in the project.
      _recordFrameExport = false;
      if (mounted) setState(() => _advancedVisible = false);
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
      if (_recordStyle == CameraStyle.film) {
        _filmFrameCounter = _filmFrameCounter >= 9999 ? 1 : _filmFrameCounter + 1;
        unawaited(_settingsService.saveFilmCounter(_filmFrameCounter));
      }
      // Save and transcode in the background. Don't block the shutter on FFmpeg.
      unawaited(_publishVideo(video.path, _recordFilterId, _recordFilterStrength,
          _recordDualSave, _recordRatio, _recordPortrait, _recordFrameExport,
          _recordStyle, _recordFrameNumber, _recordZoom, _recordDate, _recordLook));
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
      double strength, bool dualSave, String ratio, bool portrait, bool frame,
      CameraStyle frameStyle, int frameNumber, double frameZoom,
      DateTime frameDate, String frameLook) async {
    final temporaryFiles = <String>{};
    final elapsed = Stopwatch()..start();
    bool successfullyPublished = false;
    if (mounted) setState(() {
      _processingVideos++;
      _videoSaveStatus = '동영상 저장 준비 중';
    });
    try {
      final preset = CameraFilters.byId(filterId);
      final filtered = preset.id != 'original' && strength > 0;
      final frameLayer = frame
          ? await renderFrameArtworkPng(
              style: frameStyle, look: frameLook, ratio: ratio,
              zoom: frameZoom, frameNumber: frameNumber, date: frameDate,
              portrait: portrait)
          : null;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final base = 'VID_$stamp';
      // Standard CameraX recordings are 16:9. Other selected ratios need a
      // real crop in the exported file, not just a clipped camera preview.
      final cropNeeded = ratio != '16:9';
      if (filtered) {
        if (mounted) setState(() => _videoSaveStatus = '동영상 필터 처리 중 · 촬영 가능');
        final result = await _videoFilterService.render(path, preset, strength,
            ratio: ratio, portrait: portrait, frameArtwork: frameLayer);
        if (result != path) temporaryFiles.add(result);
        if (mounted) setState(() => _videoSaveStatus = '갤러리에 동영상 저장 중');
        await _storage.saveVideoToGallery(result,
            name: '${base}_${frame ? 'FRAME_' : ''}${filterId.toUpperCase()}.mp4');
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
            ratio: ratio, portrait: portrait, frameArtwork: frameLayer);
        if (result != path) temporaryFiles.add(result);
        await _storage.saveVideoToGallery(result,
          name: '${base}_${frame ? 'FRAME_' : ''}ORIGINAL.mp4');
      }
      successfullyPublished = true;
    } catch (e) {
      // Never publish an unfiltered clip under a filter name on processing error.
      _message('동영상 처리 실패: $e (원본 임시 파일 확인 필요)');
    } finally {
      for (final filePath in temporaryFiles) {
        try { await File(filePath).delete(); } catch (_) {}
      }
      // Only remove successfully published camera temp files. Keep failed
      // recordings so a user can recover them rather than silently lose data.
      if (successfullyPublished) {
        try {
          final temp = await getTemporaryDirectory();
          if (p.isWithin(temp.path, path)) await File(path).delete();
        } catch (_) {}
      }
      debugPrint('[CameraPerf] video processed + gallery save: '
          '${elapsed.elapsedMilliseconds} ms');
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

  Widget _shutter() => Semantics(
    button: true,
    label: _videoMode ? (_recording ? '녹화 종료' : '동영상 녹화') : '사진 촬영',
    child: GestureDetector(
      onTap: (_cameraTransition || !_ready || _recordingBusy || (_busy && !_videoMode))
          ? null : (_videoMode ? (_recording ? _stopRecording : _startRecording) : _capture),
      child: Container(
        width: 68, height: 68,
        decoration: BoxDecoration(
          color: CameraPalette.base,
          shape: BoxShape.circle,
          border: Border.all(color: CameraPalette.brass, width: 2.5),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
        ),
        child: Center(child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: _recording ? 30 : 52,
          height: _recording ? 30 : 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_recording ? 6 : 40),
            color: _videoMode ? const Color(0xFFE15446)
              : (_busy ? CameraPalette.muted : CameraPalette.cream),
          ),
        )),
      ),
    ),
  );

  // Native CameraX zoom can be expensive on some Samsung devices. Keep the
  // user's drag smoothly local to CameraZoomDial, and send only the most recent
  // value to the platform (about 7-9 calls/sec at most; fewer if the native
  // camera is slow). No parent setState while dragging or settling.
  void _setZoom(double value) {
    if (!_ready || _cameraTransition || _background) return;
    final target = value.clamp(_minZoom, _maxZoom).toDouble();
    if ((target - _zoom).abs() < .012) return;
    _zoom = target;
    _zoomTarget = target;
    _scheduleZoom();
  }

  void _scheduleZoom({bool force = false}) {
    if (_zoomApplying || _zoomTarget == null || _pageDisposed ||
        !_ready || _cameraTransition || _background) return;
    _zoomFlushTimer?.cancel();
    // If setZoomLevel was already slow, avoid issuing more native requests
    // faster than the device can apply them.
    final intervalMs = math.max(120, _zoomCommandDurationMs + 25);
    final elapsed = DateTime.now().difference(_lastZoomCommand).inMilliseconds;
    final waitMs = force ? 0 : math.max(0, intervalMs - elapsed);
    if (waitMs == 0) {
      unawaited(_flushZoom());
    } else {
      _zoomFlushTimer = Timer(Duration(milliseconds: waitMs),
          () => unawaited(_flushZoom()));
    }
  }

  Future<void> _flushZoom() async {
    if (_zoomApplying || _zoomTarget == null || _pageDisposed ||
        !_ready || _cameraTransition || _background) return;
    final value = _zoomTarget!;
    _zoomTarget = null;
    _zoomApplying = true;
    _lastZoomCommand = DateTime.now();
    final timer = Stopwatch()..start();
    try {
      // Displayed magnification is optical FoV ratio * intra-lens zoom.
      // The Camera2 controller receives the per-lens native zoom factor.
      await _camera.setZoom(value / _camera.opticalFactor);
    } catch (e) {
      debugPrint('[CameraZoom] native setZoom failed: $e');
    } finally {
      _zoomCommandDurationMs = timer.elapsedMilliseconds;
      if (_zoomCommandDurationMs > 110) {
        debugPrint('[CameraZoom] native update took ${_zoomCommandDurationMs}ms');
      }
      _zoomApplying = false;
      if (_zoomTarget != null) _scheduleZoom();
    }
  }

  void _zoomSettled() {
    // Commit the latest zoom even if intermediate commands were coalesced.
    // IMPORTANT: do not call setState here: rebuilding CameraPreview when a
    // gesture ends can cause a visible frame hitch on CameraX.
    _scheduleZoom(force: true);
  }

  Widget _zoomControl() => CameraZoomDial(
    key: ValueKey('${_camera.currentLens?.id ?? 'none'}-$_cameraEpoch'),
    minZoom: _minZoom,
    maxZoom: _maxZoom,
    initialZoom: _zoom,
    onChanged: _setZoom,
    onSettled: _zoomSettled,
  );

  void _saveLook({bool immediate = false}) {
    _lookSaveDebounce?.cancel();
    void persist() {
      unawaited(_settingsService.saveLook(CameraLookSelection(
        style: _style,
        digitalId: _digitalId,
        filmId: _filmId,
        digitalStrength: _digitalStrength,
        filmStrength: _filmStrength,
      )));
    }
    // The intensity slider generates many gestures per second: batch disk writes.
    if (immediate) {
      persist();
    } else {
      _lookSaveDebounce = Timer(const Duration(milliseconds: 260), persist);
    }
  }

  void _setStyle(CameraStyle next) {
    if (_style == next || _recording || _recordingBusy || _cameraTransition || _busy) return;
    setState(() {
      _style = next;
      _filterId = next == CameraStyle.digital ? _digitalId : _filmId;
      _filterStrength = next == CameraStyle.digital ? _digitalStrength : _filmStrength;
    });
    _saveLook(immediate: true);
  }

  void _updateFilter(String id, double strength) {
    if (_recording || _recordingBusy || _cameraTransition) return;
    if (_style == CameraStyle.digital &&
        !CameraFilters.digitalPresets.any((f) => f.id == id)) return;
    if (_style == CameraStyle.film &&
        !CameraFilters.presets.any((f) => f.id == id)) return;
    setState(() {
      _filterId = id;
      _filterStrength = strength;
      if (_style == CameraStyle.digital) {
        _digitalId = id;
        _digitalStrength = strength;
      } else {
        _filmId = id;
        _filmStrength = strength;
      }
    });
    _saveLook();
  }

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

  void _cycleTimer() {
    if (!_ready || _cameraTransition || _recording || _recordingBusy || _busy) return;
    const options = [0, 3, 5, 10];
    setState(() => _timer = options[(options.indexOf(_timer) + 1) % options.length]);
  }

  Future<void> _toggleGrid() async {
    if (_cameraTransition || _recordingBusy) return;
    final next = _settings.copyWith(showGrid: !_settings.showGrid);
    setState(() => _settings = next);
    await _settingsService.save(next);
  }

  void _openGallery() {
    if (_cameraTransition || _recording || _recordingBusy) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const GalleryScreen()));
  }

  IconData get _flashIcon {
    if (_videoMode) {
      return _flash == FlashMode.torch
          ? Icons.flashlight_on : Icons.flashlight_off;
    }
    switch (_flash) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.flashlight_on;
    }
  }

  String get _flashState {
    if (_videoMode) return _flash == FlashMode.torch ? 'ON' : 'OFF';
    switch (_flash) {
      case FlashMode.off:
        return 'OFF';
      case FlashMode.auto:
        return 'AUTO';
      case FlashMode.always:
        return 'ON';
      case FlashMode.torch:
        return 'TORCH';
    }
  }

  Widget _topBar({required bool landscape}) {
    final disabled = _recording || _recordingBusy || _cameraTransition || _busy;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: const BoxDecoration(
        color: CameraPalette.panel,
        border: Border(bottom: BorderSide(color: CameraPalette.stroke, width: .6)),
      ),
      child: Row(children: [
        CameraStyleToggle(style: _style, enabled: !disabled, onSelected: _setStyle),
        const Spacer(),
        if (!landscape) ...[
          _statusButton(icon: _flashIcon, label: _flashState,
            tooltip: _videoMode ? '라이트 $_flashState' : '플래시 $_flashState',
            onPressed: disabled ? null : _cycleFlash,
            active: _flash != FlashMode.off),
          _statusButton(icon: _timer == 0 ? Icons.timer_off_outlined : Icons.timer_outlined,
            label: _timer == 0 ? 'OFF' : '${_timer}s',
            tooltip: _timer == 0 ? '타이머 꺼짐' : '타이머 $_timer초',
            onPressed: disabled ? null : _cycleTimer,
            active: _timer > 0),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: disabled ? null : _cycleRatio,
            child: SizedBox(width: 39, height: 42,
              child: Center(child: Text(_ratio, style: const TextStyle(
                color: CameraPalette.cream, fontSize: 11,
                fontFamily: 'monospace', fontWeight: FontWeight.w700)))),
          ),
        ],
        _tinyButton(
          icon: _advancedVisible ? Icons.tune : Icons.tune_outlined,
          tooltip: '추가 촬영 설정',
          onPressed: disabled ? null : () => setState(() {
            _advancedVisible = !_advancedVisible;
          }),
          active: _advancedVisible,
        ),
      ]),
    );
  }

  Widget _statusButton({required IconData icon, required String label,
    required String tooltip, required VoidCallback? onPressed,
    bool active = false}) => Semantics(
      button: true, label: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: SizedBox(width: 39, height: 45, child: Column(
          mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 19,
              color: active ? CameraPalette.brass : CameraPalette.cream),
            const SizedBox(height: 1),
            Text(label, maxLines: 1, style: TextStyle(
              fontFamily: 'monospace', fontSize: 8,
              fontWeight: FontWeight.w700,
              color: active ? CameraPalette.brass : CameraPalette.muted)),
          ],
        )),
      ),
    );

  Widget _tinyButton({required IconData icon, required String tooltip,
      required VoidCallback? onPressed, bool active = false}) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints(minHeight: 39, minWidth: 37),
    padding: const EdgeInsets.all(6),
    onPressed: onPressed,
    icon: Icon(icon, size: 20,
      color: active ? CameraPalette.brass : CameraPalette.cream),
  );

  // An overlay, not a child of the preview's Column. Opening it never shrinks
  // the camera surface. Gallery & lens buttons are ONLY in the shutter row.
  Widget _advancedControls({bool landscape = false}) => Container(
    width: 255,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
    decoration: BoxDecoration(
      color: CameraPalette.panel.withValues(alpha: .97),
      border: Border.all(color: CameraPalette.stroke),
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [BoxShadow(blurRadius: 18, color: Colors.black54)],
    ),
    child: Wrap(alignment: WrapAlignment.spaceAround, runSpacing: 4, children: [
      if (landscape) ...[
        CameraIconControl(icon: _flashIcon,
          title: _videoMode ? '라이트 $_flashState' : '플래시 $_flashState',
          onPressed: _cycleFlash),
        CameraIconControl(icon: Icons.aspect_ratio_outlined,
          title: _ratio, onPressed: _cycleRatio),
        CameraIconControl(icon: _timer == 0
            ? Icons.timer_off_outlined : Icons.timer_outlined,
          title: _timer == 0 ? '타이머 OFF' : '$_timer초',
          onPressed: _cycleTimer),
      ],
      CameraIconControl(icon: _settings.showGrid ? Icons.grid_on : Icons.grid_off,
        title: '그리드', active: _settings.showGrid,
        onPressed: () => unawaited(_toggleGrid())),
      if (_videoMode)
        CameraIconControl(icon: _microphone ? Icons.mic_none : Icons.mic_off_outlined,
          title: _microphone ? '마이크 ON' : '마이크 OFF',
          onPressed: () => unawaited(_toggleMicrophone())),
      CameraIconControl(icon: Icons.settings_outlined,
        title: '환경 설정', onPressed: _openSettings),
    ]),
  );

  void _openLookSheet() {
    if (_cameraTransition || _recording || _recordingBusy || _busy) return;
    setState(() {
      _advancedVisible = false;
    });
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CameraPalette.panel,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refresh) {
          final profiles = _style == CameraStyle.digital
              ? CameraFilters.digitalPresets : CameraFilters.presets;
          return SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 13, 4, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 34, height: 3,
                decoration: BoxDecoration(color: CameraPalette.stroke,
                  borderRadius: BorderRadius.circular(3))),
              const SizedBox(height: 14),
              Text(_style == CameraStyle.digital ? 'DIGITAL · COLOR PROFILE' : 'FILM · FILM STOCK',
                style: const TextStyle(fontFamily: 'monospace',
                  color: CameraPalette.brass, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 10),
              LookSelector(style: _style, presets: profiles,
                selectedId: _filterId,
                onSelected: (id) {
                  _updateFilter(id, _filterStrength);
                  refresh(() {});
                }),
              Row(children: [
                const Padding(padding: EdgeInsets.only(left: 15),
                  child: Text('강도', style: TextStyle(color: CameraPalette.cream,
                    fontSize: 12))),
                Expanded(child: Slider(
                  min: 0, max: 1, value: _filterStrength,
                  activeColor: CameraPalette.brass,
                  onChanged: _filterId == 'original' ? null : (v) {
                    _updateFilter(_filterId, v);
                    refresh(() {});
                  },
                )),
                SizedBox(width: 55, child: Text('${(_filterStrength * 100).round()}%',
                  style: const TextStyle(color: CameraPalette.cream,
                    fontFamily: 'monospace', fontSize: 12))),
              ]),
            ]),
          ));
        },
      ),
    );
  }

  Widget _modeSwitcher() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _modeText('PHOTO', !_videoMode, () => _setVideoMode(false)),
    Container(width: 1, height: 15, color: CameraPalette.stroke,
      margin: const EdgeInsets.symmetric(horizontal: 17)),
    _modeText('VIDEO', _videoMode, () => _setVideoMode(true)),
  ]);

  Widget _modeText(String text, bool selected, VoidCallback action) => InkWell(
    onTap: _recording || _recordingBusy || _cameraTransition || _busy ? null : action,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(text, style: TextStyle(fontFamily: 'monospace', fontSize: 11,
          fontWeight: FontWeight.w800, letterSpacing: 2,
          color: selected ? CameraPalette.brass : CameraPalette.muted)),
        const SizedBox(height: 4),
        SizedBox(height: 2, width: 24,
          child: ColoredBox(color: selected ? CameraPalette.brass : Colors.transparent)),
      ])),
  );

  Future<void> _chooseLens(LensChoice selected) async {
    if (!_ready || _cameraTransition || _recording || _recordingBusy || _busy) return;
    if (_camera.currentLens?.id == selected.id) return;
    _timerCancelled = true;
    final epoch = ++_cameraEpoch;
    setState(() {
      _cameraTransition = true;
      _cameraStatus = '${selected.title} 렌즈 연결 중';
      _cameraError = null;
      _ready = false;
    });
    try {
      // Detach the previous CameraPreview from the widget tree before
      // reopening another exact Camera2 camera ID.
      await WidgetsBinding.instance.endOfFrame;
      if (_pageDisposed || _background || epoch != _cameraEpoch) return;
      await _camera.selectLens(selected.id);
      if (_pageDisposed || _background || epoch != _cameraEpoch) return;
      _syncZoom();
      _flash = FlashMode.off;
      debugPrint('[PhysicalLens] UI switched to camera ID ${selected.id}');
    } catch (e) {
      if (!_background) _message('렌즈 전환 실패: $e');
    } finally {
      if (mounted && epoch == _cameraEpoch) {
        setState(() {
          _cameraTransition = false;
          _ready = !_background &&
              (_camera.controller?.value.isInitialized ?? false);
          if (!_ready && !_background) _cameraError = '카메라 재연결에 실패했어요.';
        });
      }
    }
  }

  void _openLensPicker() {
    if (!_ready || _cameraTransition || _busy || _recording || _recordingBusy) return;
    final catalog = _camera.lensCatalog;
    final choices = catalog?.choices ?? const <LensChoice>[];
    if (choices.isEmpty) {
      _message('사용 가능한 카메라를 찾지 못했어요.');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CameraPalette.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * .72),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
            children: [
              const Center(child: Text('렌즈 선택', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700,
                color: CameraPalette.cream))),
              const SizedBox(height: 7),
              Text(catalog?.device ?? '', textAlign: TextAlign.center,
                style: const TextStyle(color: CameraPalette.muted, fontSize: 11)),
              const SizedBox(height: 12),
              ...choices.map((lens) => ListTile(
                dense: true,
                leading: Icon(lens.direction == CameraLensDirection.front
                    ? Icons.face : Icons.camera_outlined,
                    color: CameraPalette.brass),
                title: Text(lens.title,
                    style: const TextStyle(color: CameraPalette.cream)),
                subtitle: Text(lens.details,
                    style: const TextStyle(color: CameraPalette.muted, fontSize: 11)),
                trailing: _camera.currentLens?.id == lens.id
                    ? const Icon(Icons.check, color: CameraPalette.brass) : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_chooseLens(lens));
                },
              )),
              if (catalog != null && catalog.hidden.isNotEmpty) ...[
                const Divider(color: CameraPalette.stroke),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                  child: Text('시스템이 감지했지만 직접 열 수 없는 센서',
                    style: TextStyle(color: CameraPalette.muted, fontSize: 11))),
                ...catalog.hidden.map((lens) => ListTile(
                  dense: true,
                  enabled: false,
                  title: Text(lens.title),
                  subtitle: Text(lens.details,
                    style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.lock_outline, size: 16),
                )),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Text(catalog?.engineMessage ?? '',
                    style: const TextStyle(color: CameraPalette.muted, fontSize: 11)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Text('실제로 열 수 있는 카메라 ID만 선택 가능합니다. 확대 배율은 선택된 렌즈의 시야각을 기준으로 한 근삿값입니다.',
                    style: TextStyle(color: CameraPalette.muted, fontSize: 11)),
              ),
              if (catalog != null) Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('렌즈 진단 결과 복사'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: catalog.diagnostics()));
                    Navigator.of(sheetContext).pop();
                    _message('렌즈 목록을 복사했어요. 필요하면 보내주세요.');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shutterRow() => Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
    CameraIconControl(icon: Icons.photo_library_outlined, title: '앨범', onPressed: _openGallery),
    _shutter(),
    CameraIconControl(icon: Icons.camera_outlined, title: '렌즈', onPressed: _openLensPicker),
  ]);

  Widget _lookButton() => InkWell(
    onTap: _openLookSheet,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.photo_filter_outlined,
          color: CameraPalette.brass, size: 17),
        const SizedBox(width: 8),
        Text(_style == CameraStyle.digital ? 'PROFILE' : 'FILM',
          style: const TextStyle(fontFamily: 'monospace',
            color: CameraPalette.muted, letterSpacing: 1, fontSize: 10)),
        const SizedBox(width: 10),
        Flexible(child: Text(CameraFilters.byId(_filterId).label,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: CameraPalette.cream, fontSize: 12))),
        const SizedBox(width: 4),
        const Icon(Icons.keyboard_arrow_up, color: CameraPalette.brass, size: 18),
      ]),
    ),
  );

  Widget _controls(bool landscape) {
    if (landscape) {
      return Container(width: 235, color: CameraPalette.base,
        child: SingleChildScrollView(child: Column(children: [
          _topBar(landscape: true),
          if (_advancedVisible) Padding(padding: const EdgeInsets.all(7),
            child: _advancedControls(landscape: true)),
          const SizedBox(height: 8),
          _zoomControl(),
          _lookButton(),
          const SizedBox(height: 6),
          _modeSwitcher(),
          const SizedBox(height: 6),
          _shutterRow(),
          const SizedBox(height: 10),
        ])),
      );
    }
    return Container(
      color: CameraPalette.base,
      padding: const EdgeInsets.only(top: 0, bottom: 3),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _zoomControl(),
        Center(child: _lookButton()),
        _modeSwitcher(),
        _shutterRow(),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _camera.controller;
    if (!_ready || controller == null || !controller.value.isInitialized) {
      return Scaffold(backgroundColor: CameraPalette.base,
        body: SafeArea(child: Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, color: CameraPalette.brass, size: 34),
            const SizedBox(height: 16),
            if (_cameraError == null) ...[
              const SizedBox(width: 28, height: 28,
                child: CircularProgressIndicator(strokeWidth: 2, color: CameraPalette.brass)),
              const SizedBox(height: 14),
              Text(_cameraStatus, style: const TextStyle(color: CameraPalette.cream)),
            ] else ...[
              Padding(padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Text(_cameraError!, textAlign: TextAlign.center)),
              const SizedBox(height: 15),
              FilledButton(onPressed: _cameraTransition ? null : _initialize,
                child: const Text('카메라 다시 연결')),
            ],
          ],
        ))));
    }
    if (_showPreview && _captured != null) {
      return Scaffold(backgroundColor: CameraPalette.base,
        body: SafeArea(child: Stack(fit: StackFit.expand, children: [
          Image.memory(_captured!, fit: BoxFit.contain),
          Positioned(top: 8, left: 8, child: IconButton(
            onPressed: _savingPreview ? null : () => setState(() {
              _showPreview = false; _captured = null; _capturedOriginal = null;
            }), icon: const Icon(Icons.close))),
          Positioned(bottom: 16, left: 20, right: 20, child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: _savingPreview ? null : () => setState(() {
              _showPreview = false; _captured = null; _capturedOriginal = null;
            }), child: const Text('다시 촬영'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(
              onPressed: _savingPreview ? null : () => _save(_captured!),
              child: _savingPreview ? const SizedBox(height: 18, width: 18,
                child: CircularProgressIndicator(strokeWidth: 2)) : const Text('저장'))),
          ])),
        ])));
    }
    return Scaffold(backgroundColor: CameraPalette.base,
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final viewfinder = Expanded(child: Stack(fit: StackFit.expand, children: [
          _viewfinder(controller),
          if (_advancedVisible && !landscape)
            Positioned(top: 8, right: 8,
              child: _advancedControls()),
          if (_pendingSaves > 0 || _processingVideos > 0)
            Positioned(bottom: 12, left: 12, child: IgnorePointer(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: CameraPalette.panel.withValues(alpha: .9),
                border: Border.all(color: CameraPalette.stroke),
                borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(
                  strokeWidth: 2, color: CameraPalette.brass)),
                const SizedBox(width: 8),
                Text(_processingVideos > 0 ? (_videoSaveStatus ?? '영상 현상 중') : '사진 저장 중 ($_pendingSaves)',
                  style: const TextStyle(color: CameraPalette.cream, fontSize: 11)),
              ]),
            ))),
          if (_recording) Positioned(top: 12, left: 12, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: CameraPalette.panel.withValues(alpha: .86),
              borderRadius: BorderRadius.circular(6)),
            child: Text('● REC $_recordingTime',
              style: const TextStyle(color: Color(0xFFF56D60),
                fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          )),
          if (_countdown > 0) Center(child: IgnorePointer(child: Text('$_countdown',
            style: const TextStyle(fontSize: 100, fontWeight: FontWeight.bold,
              color: CameraPalette.cream,
              shadows: [Shadow(blurRadius: 7, color: Colors.black)])))),
        ]));
        return landscape
          ? Row(children: [viewfinder, _controls(true)])
          : Column(children: [_topBar(landscape: false), viewfinder, _controls(false)]);
      })));
  }
}
