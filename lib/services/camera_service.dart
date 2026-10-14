import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart' show Offset;
import 'package:flutter/foundation.dart' show debugPrint;

/// Serializes operations which replace or close the native camera. In particular,
/// the permission dialog / app lifecycle must not race a mode switch.
class CameraService {
  CameraController? controller;
  List<CameraDescription> cameras = [];
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
          cameras.sort((a, b) {
            int priority(CameraDescription c) {
              if (c.lensDirection == CameraLensDirection.back) return 0;
              if (c.lensDirection == CameraLensDirection.front) return 1;
              return 2;
            }
            return priority(a).compareTo(priority(b));
          });
        }
        if (cameras.isEmpty) throw StateError('사용 가능한 카메라가 없습니다.');
        if (currentCameraIndex >= cameras.length) currentCameraIndex = 0;
        await _startCurrentCamera();
      });

  Future<void> _startCurrentCamera() async {
    final previous = controller;
    controller = null;
    if (previous != null) await previous.dispose();

    // An Android permission dialog or a newly disposed CameraX preview surface
    // can briefly leave the Flutter surface producer unavailable. Retry ONLY
    // that known transient failure, recreating the controller each time.
    for (var attempt = 0; attempt < 3; attempt++) {
      CameraController? next;
      try {
        next = CameraController(
          cameras[currentCameraIndex],
          videoMode ? ResolutionPreset.high : ResolutionPreset.max,
          enableAudio: videoMode && microphoneEnabled,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        await next.initialize();
        final minimum = await next.getMinZoomLevel();
        final maximum = await next.getMaxZoomLevel();
        await next.setZoomLevel(1.0.clamp(minimum, maximum).toDouble());
        minZoom = minimum;
        maxZoom = maximum;
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
        debugPrint('CameraX initialization attempt ${attempt + 1} failed: $detail');
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
