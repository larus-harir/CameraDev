import 'package:flutter/services.dart';

class PhysicalLensBridge {
  const PhysicalLensBridge._();
  static const MethodChannel _channel = MethodChannel('vintage_camera/physical_lenses');

  /// Includes hidden physical IDs as metadata, never claims those IDs can be
  /// opened by the current Flutter camera engine.
  static Future<Map<String, dynamic>> inventory() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('inventory');
    return Map<String, dynamic>.from(raw ?? const {});
  }
}
