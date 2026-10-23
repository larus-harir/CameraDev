import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:physical_lens_bridge/physical_lens_bridge.dart';

/// Describes a Camera2 ID that the existing camera engine can actually open.
/// Other physical IDs reported only under a logical camera remain diagnostic.
class LensChoice {
  const LensChoice({
    required this.id,
    required this.direction,
    required this.title,
    required this.openable,
    required this.opticalFactor,
    this.focal35mm,
    this.isLogical = false,
    this.isPhysicalMetadata = false,
  });

  final String id;
  final CameraLensDirection direction;
  final String title;
  final bool openable;
  final double opticalFactor;
  final double? focal35mm;
  final bool isLogical;
  final bool isPhysicalMetadata;

  String get details {
    final equiv = focal35mm == null ? '' : ' · ${focal35mm!.toStringAsFixed(1)}mm 환산';
    final logicalHint = isLogical ? ' · 논리 멀티 카메라(내부 센서 자동 선택 가능)' : '';
    if (!openable) return '$title$equiv · 이 기기에서 직접 열 수 없음';
    if (direction == CameraLensDirection.front) return '전면 카메라 · ID $id$equiv';
    return '$title$equiv · ID $id$logicalHint';
  }
}

class LensCatalog {
  const LensCatalog(this.choices, this.hidden, this.device, this.engineMessage);
  final List<LensChoice> choices;
  final List<LensChoice> hidden;
  final String device;
  final String engineMessage;

  String diagnostics() {
    final rows = <String>[
      'Device: $device',
      'Engine: $engineMessage',
      'Selectable ${choices.length}, inaccessible ${hidden.length}',
    ];
    for (final c in [...choices, ...hidden]) {
      rows.add('id=${c.id}, open=${c.openable}, direction=${c.direction.name}, '
          'factor=${c.opticalFactor.toStringAsFixed(2)}, '
          'focal35=${c.focal35mm?.toStringAsFixed(1) ?? '?'}, '
          'logical=${c.isLogical}, ${c.title}');
    }
    return rows.join('\n');
  }

  LensChoice? forId(String id) {
    for (final choice in choices) {
      if (choice.id == id) return choice;
    }
    return null;
  }

  static Future<LensCatalog> detect(List<CameraDescription> descriptions) async {
    final map = <String, Map<String, dynamic>>{};
    String device = '';
    var engineMessage = '플랫폼에서 제공하는 카메라 ID만 표시';
    if (Platform.isAndroid) {
      try {
        final inventory = await PhysicalLensBridge.inventory();
        device = '${inventory['manufacturer'] ?? ''} ${inventory['model'] ?? ''}'.trim();
        final raw = inventory['cameras'];
        if (raw is List) {
          for (final value in raw) {
            if (value is Map) {
              final info = Map<String, dynamic>.from(value);
              final id = info['id']?.toString();
              if (id != null) map[id] = info;
            }
          }
        }
        engineMessage = 'Android Camera2 · 개별 카메라 ID 직접 개방';
      } catch (e) {
        debugPrint('[PhysicalLens] Native inventory failed: $e');
        engineMessage = 'Camera2 렌즈 메타데이터 조회 실패: $e';
      }
    }

    final knownIds = descriptions.map((e) => e.name).toSet();
    final backFocals = descriptions
        .where((d) => d.lensDirection == CameraLensDirection.back)
        .map((d) => _focal(map[d.name]))
        .where((f) => f != null && f > 0)
        .cast<double>()
        .toList();
    // Most wide cameras are ~24-28mm equivalent. Choosing the nearest one
    // avoids mistaking a tele or ultrawide sensor for 1x.
    backFocals.sort((a, b) => (a - 26).abs().compareTo((b - 26).abs()));
    final mainEquivalent = backFocals.isEmpty ? null : backFocals.first;

    LensChoice build(String id, CameraLensDirection direction, bool selectable,
        Map<String, dynamic>? meta, {bool isMetadata = false,
        CameraLensType lensType = CameraLensType.unknown}) {
      final eq = _focal(meta);
      final factor = direction == CameraLensDirection.back &&
              mainEquivalent != null && eq != null
          ? (eq / mainEquivalent).clamp(0.3, 20.0).toDouble()
          : 1.0; // iOS lensType has no reliable optical ratio metadata.
      final title = direction == CameraLensDirection.front
          ? '전면'
          : direction != CameraLensDirection.back
              ? '외부 카메라'
              : lensType == CameraLensType.ultraWide && eq == null
                  ? '초광각 렌즈'
                  : lensType == CameraLensType.telephoto && eq == null
                      ? '망원 렌즈'
                      : (eq == null || mainEquivalent == null) &&
                          lensType == CameraLensType.unknown
                          ? '후면 카메라'
                          : factor < 0.83
                      ? '초광각 · 약 ${factor.toStringAsFixed(1)}×'
                      : factor > 1.55
                          ? '망원 · 약 ${factor.toStringAsFixed(1)}×'
                          : '광각 · 약 1×';
      return LensChoice(
          id: id, direction: direction, title: title, openable: selectable,
          opticalFactor: factor, focal35mm: eq,
          isLogical: meta?['logical'] == true,
          isPhysicalMetadata: isMetadata);
    }

    final choices = descriptions.map((description) => build(
      description.name,
      description.lensDirection,
      true,
      map[description.name],
      lensType: description.lensType,
    )).toList();
    choices.sort((a, b) {
      if (a.direction != b.direction) {
        if (a.direction == CameraLensDirection.back) return -1;
        if (b.direction == CameraLensDirection.back) return 1;
        return a.id.compareTo(b.id);
      }
      return a.opticalFactor.compareTo(b.opticalFactor);
    });

    final hidden = <LensChoice>[];
    for (final entry in map.entries) {
      if (knownIds.contains(entry.key)) continue;
      final info = entry.value;
      if (info['openable'] == true) {
        // A camera advertised by Camera2 but filtered out by camera_android,
        // e.g. a non-backward-compatible sensor, is still NOT selectable.
        debugPrint('[PhysicalLens] Android engine omitted ID ${entry.key}');
      }
      final facing = info['facing']?.toString();
      hidden.add(build(entry.key,
          facing == 'back' ? CameraLensDirection.back :
          facing == 'front' ? CameraLensDirection.front :
          CameraLensDirection.external,
          false, info, isMetadata: true));
    }
    hidden.sort((a, b) => a.opticalFactor.compareTo(b.opticalFactor));
    debugPrint('[PhysicalLens] $device | $engineMessage');
    for (final entry in [...choices, ...hidden]) {
      debugPrint('[PhysicalLens] id=${entry.id} available=${entry.openable} '
          'optical=${entry.opticalFactor.toStringAsFixed(2)} '
          'logical=${entry.isLogical} ${entry.title}');
    }
    return LensCatalog(choices, hidden, device, engineMessage);
  }

  static double? _focal(Map<String, dynamic>? meta) {
    final value = meta?['focal35mm'];
    if (value is num && value > 0) return value.toDouble();
    return null;
  }
}
