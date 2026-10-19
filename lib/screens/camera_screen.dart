import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/camera_settings.dart';
import '../models/camera_style.dart';
import '../widgets/camera_chrome.dart';
import '../widgets/frame_artwork.dart';
import '../models/filter_preset.dart';
import '../services/filter_service.dart';
import '../services/video_filter_service.dart';
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
  CameraStyle _style = CameraStyle.digital;
  String _digitalId = 'digital_s';
  String _filmId = 'original';
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
      _filmFrameCounter = await _settingsService.loadFilmCounter();
      final look = await _settingsService.loadLook();
      _style = look.style;
      _digitalId = CameraFilters.digitalPresets.any((p) => p.id == look.digitalId)
          ? look.digitalId : 'digital_s';
      _filmId = CameraFilters.presets.any((p) => p.id == look.filmId)
          ? look.filmId : 'original';
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

  Future<void> _capture() async {
    if (_busy || !_ready || _cameraTransition || _videoMode || _recordingBusy) return;
    if (_pendingSaves >= 3 && !_settings.showCapturePreview && !_settings.askBeforeSaving) {
      _message('저장 작업이 밀려 있어요. 잠시 후 촬영해 주세요.');
      return;
    }
    _timerCancelled = false;
    setState(() { _busy = true; _countdown = _timer; _zoomSliderVisible = false; _advancedVisible = false; });
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
      final frame = style == CameraStyle.film
          ? _settings.addFilmFrameToExports
          : _settings.addDigitalFrameToExports;
      final shotFrame = _filmFrameCounter;
      final shotZoom = _zoom;
      final shotDate = DateTime.now();
      final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
      final photo = await _camera.takePicture();
      if (style == CameraStyle.film) {
        _filmFrameCounter = _filmFrameCounter >= 9999 ? 1 : _filmFrameCounter + 1;
        unawaited(_settingsService.saveFilmCounter(_filmFrameCounter));
      }
      // Auto-save: camera is usable again immediately after capture.
      // JPEG processing and gallery I/O continue asynchronously.
      final frameLayer = frame
          ? renderFrameArtworkPng(
              style: style, look: preset.label, ratio: ratio,
              zoom: shotZoom, frameNumber: shotFrame, date: shotDate,
              portrait: portrait)
          : null;
      if (!showPreview && !ask) {
        setState(() => _pendingSaves++);
        unawaited(_processAndSave(photo.readAsBytes(), ratio, preset,
          strength, dualSave, frameLayer, frame));
        return;
      }
      final rawBytes = await photo.readAsBytes();
      final bytes = await _filterService.processCapture(
          rawBytes, ratio, preset, strength,
          frameArtwork: frameLayer == null ? null : await frameLayer);
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

  Future<void> _processAndSave(Future<Uint8List> readBytes,
      String ratio, FilterPreset preset, double strength, bool dualSave,
      Future<Uint8List>? frameLayer, bool frame) async {
    try {
      final original = await readBytes;
      final bytes = await _filterService.processCapture(
          original, ratio, preset, strength,
          frameArtwork: frameLayer == null ? null : await frameLayer);
      await _savePair(bytes, dualSave ? original : null, ratio, preset.id, frame: frame);
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
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
      return Center(child: Container(
        padding: const EdgeInsets.all(4.5),
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
          IgnorePointer(child: CustomPaint(
            painter: FrameArtworkPainter(
              style: _recording ? _recordStyle : _style,
              look: CameraFilters.byId(_recording ? _recordFilterId : _filterId).label,
              ratio: _ratio,
              zoom: _recording ? _recordZoom : _zoom,
              frameNumber: _recording ? _recordFrameNumber : _filmFrameCounter,
              date: _recording ? _recordDate : DateTime.now(),
            ),
          )),
          Positioned(right: 7, top: 0, bottom: 0,
            child: Center(child: _zoomRail())),
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
      _zoomSliderVisible = false;
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
      _recordFrameExport = _style == CameraStyle.film
          ? _settings.addFilmFrameToExports
          : _settings.addDigitalFrameToExports;
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

  Future<void> _setZoom(double value) async {
    final target = value.clamp(_minZoom, _maxZoom).toDouble();
    if (mounted) setState(() => _zoom = target);
    try {
      await _camera.setZoom(target);
    } catch (e) {
      _message('줌 설정 실패: $e');
    }
  }

  // The zoom rail is painted OVER the live viewfinder: never resize preview.
  Widget _zoomRail() {
    final stops = <double>[];
    for (final value in [_minZoom, 0.6, 1.0, 2.0, 3.0, _maxZoom]) {
      if (value >= _minZoom && value <= _maxZoom &&
          !stops.any((previous) => (previous - value).abs() < .06)) {
        stops.add(value);
      }
    }
    stops.sort();

    if (!_zoomSliderVisible) {
      return Semantics(
        button: true, label: '줌 ${_zoom.toStringAsFixed(1)}배, 확대해서 조절',
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => setState(() => _zoomSliderVisible = true),
          child: Container(
            width: 43, height: 43,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CameraPalette.base.withValues(alpha: .78),
              border: Border.all(color: CameraPalette.stroke),
              shape: BoxShape.circle,
            ),
            child: Text('${_zoom.toStringAsFixed(1)}×',
              style: const TextStyle(fontSize: 11,
                color: CameraPalette.cream, fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      decoration: BoxDecoration(
        color: CameraPalette.base.withValues(alpha: .91),
        border: Border.all(color: CameraPalette.stroke),
        borderRadius: BorderRadius.circular(25),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 325),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final stop in stops)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _setZoom(stop),
                child: Container(
                  width: 36, height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (_zoom - stop).abs() < .06
                        ? CameraPalette.brass : Colors.transparent,
                  ),
                  child: Text(
                    '${stop.toStringAsFixed(stop == stop.roundToDouble() ? 0 : 1)}×',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 10,
                      color: (_zoom - stop).abs() < .06
                          ? CameraPalette.base : CameraPalette.cream),
                  ),
                ),
              ),
            if (_maxZoom > _minZoom) ...[
              const SizedBox(height: 4),
              SizedBox(width: 38, height: 100, child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
                  ),
                  child: Slider(
                    min: _minZoom,
                    max: _maxZoom,
                    value: _zoom.clamp(_minZoom, _maxZoom).toDouble(),
                    activeColor: CameraPalette.brass,
                    onChanged: _setZoom,
                  ),
                ),
              )),
            ],
            IconButton(
              tooltip: '줌 닫기',
              onPressed: () => setState(() => _zoomSliderVisible = false),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 35, minHeight: 29),
              icon: const Icon(Icons.close, color: CameraPalette.muted, size: 17),
            ),
          ],
        )),
      ),
    );
  }

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

  Widget _topBar({required bool landscape}) {
    final disabled = _recording || _recordingBusy || _cameraTransition || _busy;
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: const BoxDecoration(
        color: CameraPalette.panel,
        border: Border(bottom: BorderSide(color: CameraPalette.stroke, width: .6)),
      ),
      child: Row(children: [
        CameraStyleToggle(style: _style, enabled: !disabled, onSelected: _setStyle),
        const Spacer(),
        if (!landscape) ...[
          _tinyButton(
            icon: _flash == FlashMode.off ? Icons.flash_off : Icons.flash_on,
            tooltip: _videoMode ? '라이트' : '플래시',
            onPressed: disabled ? null : _cycleFlash,
          ),
          InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: disabled ? null : _cycleRatio,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
              child: Text(_ratio, style: const TextStyle(
                color: CameraPalette.cream, fontSize: 11,
                fontFamily: 'monospace', fontWeight: FontWeight.w700)),
            ),
          ),
        ],
        _tinyButton(
          icon: _advancedVisible ? Icons.tune : Icons.tune_outlined,
          tooltip: '추가 촬영 설정',
          onPressed: disabled ? null : () => setState(() {
            _advancedVisible = !_advancedVisible;
            _zoomSliderVisible = false;
          }),
          active: _advancedVisible,
        ),
      ]),
    );
  }

  Widget _tinyButton({required IconData icon, required String tooltip,
      required VoidCallback? onPressed, bool active = false}) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints(minHeight: 39, minWidth: 38),
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
        CameraIconControl(icon: Icons.flash_on_outlined,
          title: _videoMode ? '라이트' : '플래시', onPressed: _cycleFlash),
        CameraIconControl(icon: Icons.aspect_ratio_outlined,
          title: _ratio, onPressed: _cycleRatio),
      ],
      CameraIconControl(icon: Icons.timer_outlined,
        title: _timer == 0 ? '타이머 OFF' : '$_timer초',
        onPressed: _cycleTimer),
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
      _zoomSliderVisible = false;
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

  Widget _shutterRow() => Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
    CameraIconControl(icon: Icons.photo_library_outlined, title: '앨범', onPressed: _openGallery),
    _shutter(),
    CameraIconControl(icon: Icons.cameraswitch_outlined, title: '렌즈', onPressed: _switchCamera),
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
      return Container(width: 235, color: CameraPalette.panel,
        child: SingleChildScrollView(child: Column(children: [
          _topBar(landscape: true),
          if (_advancedVisible) Padding(padding: const EdgeInsets.all(7),
            child: _advancedControls(landscape: true)),
          const SizedBox(height: 8),
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
      color: CameraPalette.panel,
      padding: const EdgeInsets.only(top: 1, bottom: 3),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
            Positioned(bottom: 9, left: 12, child: IgnorePointer(child: Container(
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
