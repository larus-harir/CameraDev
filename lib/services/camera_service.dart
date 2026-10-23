import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart' show Offset;
import 'package:flutter/foundation.dart' show debugPrint;
import 'lens_catalog.dart';

/// Serializes operations which replace or close the native camera. In particular,
/// the permission dialog / app lifecycle must not race a mode switch.
class CameraService {
  CameraController? controller;
  List<CameraDescription> cameras = [];
  LensCatalog? lensCatalog;
  LensChoice? get currentLens => cameras.isEmpty ? null :
      lensCatalog?.forId(cameras[currentCameraIndex].name);
  double get opticalFactor => currentLens?.opticalFactor ?? 1.0;
  int currentCameraIndex = 0;
  double minZoom = 1.0;
  double maxZoom = 1.0;
  bool videoMode = false;
  bool microphoneEnabled = true;

  Future<void> _queue = Future<void>.value();

  Future<T> _exclusive<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        final result = await task();
        completer.complete(result);
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<void> initialize() => _exclusive(() async {
        if (controller?.value.isInitialized ?? false) return;
        if (cameras.isEmpty) {
          cameras = await availableCameras();
          debugPrint('[CameraLens] Camera2 descriptions: '
              '${cameras.map((c) => '${c.name}/${c.lensDirection.name}').join(', ')}');
          lensCatalog = await LensCatalog.detect(cameras);
          final priority = <String, int>{};
          final ordered = lensCatalog!.choices;
          for (var i = 0; i < ordered.length; i++) {
            priority[ordered[i].id] = i;
          }
          cameras.sort((a, b) =>
              (priority[a.name] ?? 999).compareTo(priority[b.name] ?? 999));
          // On launch, use the true wide/1x lens rather than selecting
          // ultrawide simply because its native camera ID sorts first.
          final defaultIndex = cameras.indexWhere((c) =>
              c.lensDirection == CameraLensDirection.back &&
              (lensCatalog?.forId(c.name)?.opticalFactor ?? 1) >= .83 &&
              (lensCatalog?.forId(c.name)?.opticalFactor ?? 1) <= 1.55);
          currentCameraIndex = defaultIndex >= 0 ? defaultIndex : 0;
        }
        if (cameras.isEmpty) throw StateError('사용 가능한 카메라가 없습니다.');
        if (currentCameraIndex >= cameras.length) currentCameraIndex = 0;
        await _startCurrentCamera();
      });

  Future<void> _startCurrentCamera() async {
    final previous = controller;
    controller = null;
    if (previous != null) await previous.dispose();

    // An Android permission dialog or a newly disposed native preview surface
    // can briefly leave the Flutter surface producer unavailable. Retry ONLY
    // that known transient failure, recreating the controller each time.
    for (var attempt = 0; attempt < 3; attempt++) {
      CameraController? next;
      try {
        next = CameraController(
          cameras[currentCameraIndex],
          // Avoid very large sensor JPEGs (sometimes 48 MP+) that delay the
          // shutter and then get resized by our edited-JPEG pipeline anyway.
          // Switch ultraHigh to max for maximum full-resolution originals.
          videoMode ? ResolutionPreset.high : ResolutionPreset.ultraHigh,
          enableAudio: videoMode && microphoneEnabled,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        await next.initialize();
        final minimum = await next.getMinZoomLevel();
        final maximum = await next.getMaxZoomLevel();
        await next.setZoomLevel(1.0.clamp(minimum, maximum).toDouble());
        minZoom = minimum;
        maxZoom = maximum;
        debugPrint('[CameraLens] Active camera=${cameras[currentCameraIndex].name}, '
            'minZoom=$minimum, maxZoom=$maximum. '
            'Camera2 camera ID is opened directly; optical multiplier=$opticalFactor.');
        controller = next;
        return;
      } catch (error) {
        if (next != null) {
          try {
            await next.dispose();
          } catch (_) {
            // Continue reporting the original initialization error.
          }
        }
        final detail = error.toString();
        debugPrint('Camera initialization attempt ${attempt + 1} failed: $detail');
        final transientSurfaceError =
            detail.contains('surfaceProducerHandlesCropAndRotation') ||
            detail.contains('flutterSurfaceProducer');
        if (!transientSurfaceError || attempt == 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
  }

  Future<void> configureVideo({
    required bool enabled,
    required bool microphone,
  }) => _exclusive(() async {
        if (controller?.value.isRecordingVideo ?? false) {
          throw StateError('녹화 중에는 모드를 바꿀 수 없습니다.');
        }
        if (videoMode == enabled && microphoneEnabled == microphone &&
            (controller?.value.isInitialized ?? false)) return;
        videoMode = enabled;
        microphoneEnabled = microphone;
        await _startCurrentCamera();
      });

  Future<void> switchCamera() => _exclusive(() async {
        if (cameras.length < 2) return;
        if (controller?.value.isRecordingVideo ?? false) {
          throw StateError('녹화 중에는 렌즈를 바꿀 수 없습니다.');
        }
        final direction = cameras[currentCameraIndex].lensDirection;
        final target = direction == CameraLensDirection.back
            ? CameraLensDirection.front
            : CameraLensDirection.back;
        final index = cameras.indexWhere((c) => c.lensDirection == target);
        currentCameraIndex =
            index >= 0 ? index : (currentCameraIndex + 1) % cameras.length;
        await _startCurrentCamera();
      });


  /// Open the exact Camera2 ID verified by the platform inventory.
  /// A logical-only physical ID is deliberately rejected.
  Future<void> selectLens(String cameraId) => _exclusive(() async {
        if (controller?.value.isRecordingVideo ?? false) {
          throw StateError('녹화 중에는 렌즈를 바꿀 수 없습니다.');
        }
        final targetIndex = cameras.indexWhere((c) => c.name == cameraId);
        final selected = lensCatalog?.forId(cameraId);
        if (targetIndex < 0 || selected == null || !selected.openable) {
          throw StateError('이 렌즈는 현재 카메라 엔진에서 직접 열 수 없습니다 (ID $cameraId).');
        }
        if (targetIndex == currentCameraIndex && (controller?.value.isInitialized ?? false)) {
          return;
        }
        final oldIndex = currentCameraIndex;
        currentCameraIndex = targetIndex;
        try {
          await _startCurrentCamera();
          debugPrint('[PhysicalLens] SELECTED opened Camera2 id=$cameraId '
              'factor=${selected.opticalFactor.toStringAsFixed(2)}');
        } catch (e) {
          debugPrint('[PhysicalLens] switch failed for $cameraId: $e');
          currentCameraIndex = oldIndex;
          try { await _startCurrentCamera(); } catch (_) {}
          rethrow;
        }
      });

  Future<void> startVideo() => _exclusive(() async {
        final c = controller;
        if (c == null || !c.value.isInitialized || c.value.isRecordingVideo) {
          throw StateError('녹화를 시작할 수 없습니다.');
        }
        await c.startVideoRecording();
      });

  Future<XFile> stopVideo() => _exclusive(() async {
        final c = controller;
        if (c == null || !c.value.isRecordingVideo) {
          throw StateError('진행 중인 녹화가 없습니다.');
        }
        return c.stopVideoRecording();
      });

  Future<XFile> takePicture() => _exclusive(() async {
        final c = controller;
        if (c == null || !c.value.isInitialized) {
          throw StateError('카메라가 준비되지 않았습니다.');
        }
        return c.takePicture();
      });

  Future<void> setZoom(double value) async {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    await c.setZoomLevel(value.clamp(minZoom, maxZoom).toDouble());
  }

  Future<void> setFlash(FlashMode mode) async {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    await c.setFlashMode(mode);
  }

  Future<bool> focusAt(double x, double y) async {
    final c = controller;
    if (c == null || !c.value.isInitialized) return false;
    var focused = false;
    final point = Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
    try {
      await c.setFocusMode(FocusMode.auto);
      await c.setFocusPoint(point);
      focused = true;
    } catch (_) {
      // Custom focus isn't implemented by every camera.
    }
    try {
      await c.setExposurePoint(point);
    } catch (_) {
      // Exposure points are optional.
    }
    return focused;
  }

  Future<void> dispose() => _exclusive(() async {
        final previous = controller;
        controller = null;
        await previous?.dispose();
      });
}
