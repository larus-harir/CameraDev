import 'package:flutter/material.dart';
import 'camera_chrome.dart';

/// Minimal tap-to-focus feedback. Deliberately no label, center dot, or
/// game-like scale/bounce animation. This is not an AF lock-success signal.
class CameraFocusIndicator extends StatelessWidget {
  const CameraFocusIndicator({
    super.key,
    required this.sequence,
    required this.visible,
  });

  final int sequence;
  final bool visible;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedOpacity(
          key: ValueKey(sequence),
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: const SizedBox(
            width: 54,
            height: 54,
            child: CustomPaint(painter: _ThinFocusCorners()),
          ),
        ),
      );
}

class _ThinFocusCorners extends CustomPainter {
  const _ThinFocusCorners();

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 6.0;
    const corner = 11.0;
    final left = pad;
    final top = pad;
    final right = size.width - pad;
    final bottom = size.height - pad;
    final path = Path()
      ..moveTo(left, top + corner)
      ..lineTo(left, top)
      ..lineTo(left + corner, top)
      ..moveTo(right - corner, top)
      ..lineTo(right, top)
      ..lineTo(right, top + corner)
      ..moveTo(right, bottom - corner)
      ..lineTo(right, bottom)
      ..lineTo(right - corner, bottom)
      ..moveTo(left + corner, bottom)
      ..lineTo(left, bottom)
      ..lineTo(left, bottom - corner);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x99000000)
        ..strokeWidth = 1.9
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = CameraPalette.cream
        ..strokeWidth = 1.05
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _ThinFocusCorners old) => false;
}
