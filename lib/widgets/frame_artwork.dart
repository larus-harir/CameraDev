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

  /// FILM: a genuine developed-negative *rebate* rather than a sticker-like
  /// black border. Ink, perforations, and date stay on the opaque border.
  /// The center remains fully transparent for both preview and exports.
  void _paintFilmGate(Canvas canvas, Size size) {
    final u = size.shortestSide / 360.0;
    final left = 16.0 * u;
    final right = size.width - left;
    final top = 31.0 * u;
    final bottom = size.height - 49.0 * u;
    final aperture = Rect.fromLTRB(left, top, right, bottom);

    const negative = Color(0xFF13110F);
    const ember = Color(0xFFF19846);
    const inkDim = Color(0xFF9C5A29);
    const gate = Color(0xFF634933);

    _matte(canvas, size, aperture, negative);
    // Developed-film stock has a subtle translucent brown rebate near the
    // actual exposed area, not a prominent rounded-picture-frame shape.
    canvas.drawRect(aperture.inflate(1.5 * u), Paint()
      ..color = gate
      ..style = PaintingStyle.stroke
      ..strokeWidth = .85 * u);
    canvas.drawRect(aperture.deflate(1.0 * u), Paint()
      ..color = const Color(0x66795934)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .5 * u);
    for (final y in [top - 3 * u, bottom + 3 * u]) {
      canvas.drawLine(Offset(left, y), Offset(right, y), Paint()
        ..color = const Color(0x554B3220)..strokeWidth = .65 * u);
    }

    // Actual 35mm film has many small, evenly repeated holes along the edges.
    // Keep them narrow and square-ish, softly backlit, not large pill buttons.
    final usableWidth = size.width - 2 * left;
    final holeCount = (usableWidth / (16 * u)).floor().clamp(5, 100);
    final holeStep = usableWidth / holeCount;
    for (var i = 0; i < holeCount; i++) {
      final x = left + holeStep * (i + .5);
      for (final cy in <double>[8.0 * u, size.height - 8.0 * u]) {
        final hole = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, cy), width: 5.9 * u, height: 7.3 * u),
          Radius.circular(.8 * u));
        canvas.drawRRect(hole, Paint()..color = const Color(0xFF070606));
        canvas.drawRRect(hole, Paint()
          ..color = const Color(0x886B472A)
          ..strokeWidth = .6 * u
          ..style = PaintingStyle.stroke);
      }
    }

    // The film name is printed on the rebate, like processed 35mm stock.
    final name = look.toUpperCase();
    final compact = name.length > 17 ? '${name.substring(0, 17)}…' : name;
    final leftText = left + 5 * u;
    _text(canvas, compact, Offset(leftText, 17.0 * u), 9.2 * u, ember);

    final dateLabel = '${date.year.toString().padLeft(4, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.'
      '${date.day.toString().padLeft(2, '0')}';
    final inkY = size.height - 33.0 * u;
    _text(canvas, dateLabel, Offset(right - 5 * u, inkY),
      11.5 * u, ember, alignRight: true);
    // Film-edge registration markings, deliberately quiet.
    for (var i = 0; i < 6; i++) {
      final x = left + 5 * u + i * 4.5 * u;
      canvas.drawLine(Offset(x, inkY + 5.5 * u),
        Offset(x, inkY + (i.isEven ? 10.5 : 8.5) * u), Paint()
          ..strokeWidth = 1.1 * u..color = inkDim);
    }
    canvas.drawLine(Offset(leftText, 28 * u), Offset(right - 5 * u, 28 * u),
      Paint()..strokeWidth = .55 * u..color = const Color(0x66492B19));
  }

  /// DIGITAL: slim satin-metal LCD frame with a deliberately restrained
  /// warm date imprint, matching the look of early compact CCD cameras.
  void _paintDigitalBezel(Canvas canvas, Size size) {
    final u = size.shortestSide / 360;
    final side = 11.0 * u;
    final top = 14.0 * u;
    final bottom = size.height - 31.0 * u;
    final aperture = Rect.fromLTRB(side, top, size.width - side, bottom);
    const steel = Color(0xFF171A1B);
    const slate = Color(0xFF626664);
    const amber = Color(0xFFF5AC66);
    _matte(canvas, size, aperture, steel);
    canvas.drawRect(aperture.inflate(1 * u), Paint()
      ..color = slate
      ..strokeWidth = .85 * u
      ..style = PaintingStyle.stroke);
    canvas.drawLine(Offset(12 * u, 5 * u),
      Offset(size.width - 12 * u, 5 * u), Paint()
        ..color = const Color(0x553F4747)..strokeWidth = .8 * u);

    // Four subtle focus-corner marks. They sit close to the bezel rather than
    // giving a large fake recording HUD over the image.
    final corners = <Offset>[
      Offset(aperture.left + 6 * u, aperture.top + 6 * u),
      Offset(aperture.right - 6 * u, aperture.top + 6 * u),
      Offset(aperture.left + 6 * u, aperture.bottom - 6 * u),
      Offset(aperture.right - 6 * u, aperture.bottom - 6 * u),
    ];
    for (final c in corners) {
      final sx = c.dx < size.width / 2 ? 1.0 : -1.0;
      final sy = c.dy < size.height / 2 ? 1.0 : -1.0;
      canvas.drawPath(Path()
        ..moveTo(c.dx + sx * 8 * u, c.dy)
        ..lineTo(c.dx, c.dy)
        ..lineTo(c.dx, c.dy + sy * 8 * u), Paint()
          ..color = const Color(0xA0DDD5C3)
          ..strokeWidth = .75 * u
          ..style = PaintingStyle.stroke);
    }

    final dateLabel = '${date.year.toString().padLeft(4, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.'
      '${date.day.toString().padLeft(2, '0')}';
    _text(canvas, dateLabel, Offset(side + 6 * u, size.height - 22 * u),
      10 * u, amber);
    final name = look.toUpperCase();
    final compact = name.length > 14 ? '${name.substring(0, 14)}…' : name;
    _text(canvas, compact, Offset(size.width - side - 6 * u,
      size.height - 22 * u), 9.0 * u,
      const Color(0xFFD4CDC0), alignRight: true);
    // One understated CCD indicator at the right of the upper metal lip.
    canvas.drawCircle(Offset(size.width - 19 * u, 7 * u),
      1.65 * u, Paint()..color = amber);
  }

  @override
  bool shouldRepaint(FrameArtworkPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.look != look ||
      oldDelegate.ratio != ratio || oldDelegate.date != date ||
      oldDelegate.zoom != zoom || oldDelegate.frameNumber != frameNumber;
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
