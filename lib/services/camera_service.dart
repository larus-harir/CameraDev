import 'package:camera/camera.dart';
import 'package:flutter/material.dart' show Offset;

class CameraService {
  CameraController? controller;
  List<CameraDescription> cameras = [];
  int currentCameraIndex = 0;
  double minZoom = 1.0;
  double maxZoom = 1.0;

  Future<void> initialize() async {
    cameras = await availableCameras();
    if (cameras.isEmpty) throw Exception('사용 가능한 카메라가 없습니다.');
    if (currentCameraIndex >= cameras.length) currentCameraIndex = 0;
    await _startCurrentCamera();
  }

  Future<void> _startCurrentCamera() async {
    final oldController = controller;
    controller = null;
    await oldController?.dispose();

    controller = CameraController(
      cameras[currentCameraIndex],
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await controller!.initialize();
    minZoom = await controller!.getMinZoomLevel();
    maxZoom = await controller!.getMaxZoomLevel();
    await setZoom(1.0.clamp(minZoom, maxZoom).toDouble());
  }

  Future<void> switchCamera() async {
    if (cameras.length < 2) return;
    currentCameraIndex = (currentCameraIndex + 1) % cameras.length;
    await _startCurrentCamera();
  }

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


  Future<void> focusAt(double x, double y) async {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    final point = Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
    try {
      await c.setFocusMode(FocusMode.auto);
      await c.setFocusPoint(point);
    } catch (_) {
      // Some devices do not support custom focus points.
    }
    try {
      await c.setExposurePoint(point);
    } catch (_) {
      // Exposure point selection is optional.
    }
  }

  Future<XFile> takePicture() async {
    final c = controller;
    if (c == null || !c.value.isInitialized) {
      throw Exception('카메라가 준비되지 않았습니다.');
    }
    return c.takePicture();
  }

  Future<void> dispose() async {
    final old = controller;
    controller = null;
    await old?.dispose();
  }
}
