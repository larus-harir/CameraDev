import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/camera_style.dart';

/// Shared design for the live camera viewfinder AND the exported JPG/MP4 matte.
/// The same painter is rendered at different resolutions; all geometry is
/// expressed relative to the canvas size, not to the device pixel ratio.
class FrameArtworkPainter extends CustomPainter {
  const FrameArtworkPainter({
    required this.style,
    required this.look,
    required this.ratio,
    required this.zoom,
    required this.frameNumber,
    required this.date,
  });

  final CameraStyle style;
  final String look;
  final String ratio;
  final double zoom;
  final int frameNumber;
  final DateTime date;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (style == CameraStyle.film) {
      _paintFilmGate(canvas, size);
    } else {
      _paintDigitalBezel(canvas, size);
    }
  }

  /// Fill only the area *outside* the photograph. This preserves the camera
  /// image beneath the inner rectangle and makes a real inset photo window.
  void _matte(Canvas canvas, Size size, Rect aperture, Color matte) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(aperture);
    canvas.drawPath(path, Paint()..color = matte);
  }

  void _text(Canvas canvas, String value, Offset position, double fontSize,
      Color color, {bool alignRight = false}) {
    final p = TextPainter(
      text: TextSpan(text: value,
        style: TextStyle(
          fontFamily: 'monospace',
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        )),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    p.paint(canvas, position.translate(alignRight ? -p.width : 0, 0));
    p.dispose();
  }

  /// FILM: a restrained photographic negative gate, not a comic filmstrip.
  /// No 35mm labels, frame counters or oversized perforations.
  void _paintFilmGate(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final unit = s / 360.0;
    // The outer matte is part of the exported image, not an on-screen-only UI.
    final horizontalInset = 15.0 * unit;
    final topInset = 17.0 * unit;
    final bottomInset = 25.0 * unit;
    final aperture = Rect.fromLTRB(horizontalInset, topInset,
      size.width - horizontalInset, size.height - bottomInset);
    const darkNegative = Color(0xFF1B1916);
    const subduedGold = Color(0xFF8C7958);
    const edgeInk = Color(0xFF504739);

    _matte(canvas, size, aperture, darkNegative);

    // Thin analogue gate border with a warm, very soft inside highlight.
    canvas.drawRect(aperture.deflate(.55 * unit), Paint()
      ..color = const Color(0x8DBDA781)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75 * unit);
    canvas.drawRect(aperture.inflate(2.4 * unit), Paint()
      ..color = edgeInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6 * unit);

    // Small, subtle edge registration marks on the matte. No punched-out
    // sprockets, large holes, fake film codes, or overlapping labels.
    final marks = Paint()
      ..color = subduedGold.withValues(alpha: .48)
      ..strokeWidth = 1.2 * unit
      ..strokeCap = StrokeCap.round;
    for (final fraction in <double>[.18, .5, .82]) {
      final y = aperture.top + aperture.height * fraction;
      canvas.drawLine(Offset(5 * unit, y - 3 * unit),
          Offset(5 * unit, y + 3 * unit), marks);
      canvas.drawLine(Offset(size.width - 5 * unit, y - 3 * unit),
          Offset(size.width - 5 * unit, y + 3 * unit), marks);
    }

    // A discreet dividing line beneath the image gives a photographic-mat
    // impression, while keeping the center and text completely uncluttered.
    final centerX = size.width / 2;
    final lineY = size.height - 11 * unit;
    canvas.drawLine(Offset(centerX - 18 * unit, lineY),
        Offset(centerX + 18 * unit, lineY), Paint()
          ..color = subduedGold.withValues(alpha: .56)
          ..strokeWidth = 1.0 * unit);
    canvas.drawCircle(Offset(centerX, lineY), 1.5 * unit,
        Paint()..color = const Color(0xFFE0C69A));
  }

  /// DIGITAL: compact-camera LCD aperture, no busy viewfinder typography.
  /// Labels sit ON the opaque bottom lip so background photographs can't
  /// swallow them. REC stays a live-only state indicator elsewhere.
  void _paintDigitalBezel(Canvas canvas, Size size) {
    final unit = size.shortestSide / 360.0;
    final side = 11.0 * unit;
    final top = 12.0 * unit;
    final bottom = 27.0 * unit;
    final aperture = Rect.fromLTRB(side, top,
        size.width - side, size.height - bottom);
    _matte(canvas, size, aperture, const Color(0xFF171B1A));
    canvas.drawRect(aperture.inflate(1.2 * unit), Paint()
      ..color = const Color(0xFF525750)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75 * unit);

    final highlight = Paint()
      ..color = const Color(0xA4D2C9AF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1 * unit;
    final segment = 11.0 * unit;
    for (final x in [aperture.left + 5 * unit, aperture.right - 5 * unit]) {
      for (final y in [aperture.top + 5 * unit, aperture.bottom - 5 * unit]) {
        final dx = x < size.width / 2 ? 1.0 : -1.0;
        final dy = y < size.height / 2 ? 1.0 : -1.0;
        canvas.drawPath(Path()
          ..moveTo(x + dx * segment, y)
          ..lineTo(x, y)
          ..lineTo(x, y + dy * segment), highlight);
      }
    }
    final dateLabel = '${date.year.toString().padLeft(4, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.'
      '${date.day.toString().padLeft(2, '0')}';
    final fontSize = 9.0 * unit;
    final labelY = size.height - 19 * unit;
    _text(canvas, dateLabel, Offset(side + 5 * unit, labelY), fontSize,
        const Color(0xFFD0C8B9));
    final compactLook = look.length > 14 ? '${look.substring(0, 14)}…' : look;
    _text(canvas, compactLook.toUpperCase(),
        Offset(size.width - side - 5 * unit, labelY), fontSize,
        const Color(0xFFB8AD96), alignRight: true);
  }

  @override
  bool shouldRepaint(FrameArtworkPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.look != look ||
      oldDelegate.ratio != ratio || oldDelegate.zoom != zoom ||
      oldDelegate.frameNumber != frameNumber || oldDelegate.date != date;
}

/// The PNG is transparent inside the aperture and opaque around its edges.
/// PhotoService composites it over JPEG; FFmpeg composites it over MP4.
Future<Uint8List> renderFrameArtworkPng({
  required CameraStyle style,
  required String look,
  required String ratio,
  required double zoom,
  required int frameNumber,
  required DateTime date,
  required bool portrait,
}) async {
  final double aspect = switch (ratio) {
    '1:1' => 1,
    '16:9' => 16 / 9,
    _ => 4 / 3,
  };
  final width = portrait ? 720 : (720 * aspect).round();
  final height = portrait ? (720 * aspect).round() : 720;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  FrameArtworkPainter(
    style: style,
    look: look,
    ratio: ratio,
    zoom: zoom,
    frameNumber: frameNumber,
    date: date,
  ).paint(canvas, Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (encoded == null) throw StateError('프레임 렌더링 실패');
  return encoded.buffer.asUint8List();
}
