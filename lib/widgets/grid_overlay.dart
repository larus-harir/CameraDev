import 'package:flutter/material.dart';

class GridOverlay extends StatelessWidget {
  const GridOverlay({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GridPainter());
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.55)..strokeWidth = 0.7;
    for (final x in [size.width / 3, size.width * 2 / 3]) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (final y in [size.height / 3, size.height * 2 / 3]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
