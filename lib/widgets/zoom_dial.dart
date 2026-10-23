import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'camera_chrome.dart';

/// Camera zoom control. The collapsed state shows exactly one magnification.
/// The ruler opens on tap/drag and remains usable for several seconds after
/// the LAST interaction. Native camera zoom is throttled by CameraScreen.
class CameraZoomDial extends StatefulWidget {
  const CameraZoomDial({
    super.key,
    required this.minZoom,
    required this.maxZoom,
    required this.initialZoom,
    required this.onChanged,
    required this.onSettled,
  });

  final double minZoom;
  final double maxZoom;
  final double initialZoom;
  final ValueChanged<double> onChanged;
  final VoidCallback onSettled;

  @override
  State<CameraZoomDial> createState() => _CameraZoomDialState();
}

class _CameraZoomDialState extends State<CameraZoomDial> {
  static const _autoCloseDelay = Duration(seconds: 5);
  late double _value;
  late List<double> _stops;
  Timer? _closeTimer;
  bool _expanded = false;
  bool _dragging = false;
  double _dragStartX = 0;
  double _dragStartProgress = 0;

  @override
  void initState() {
    super.initState();
    _value = widget.initialZoom.clamp(widget.minZoom, widget.maxZoom).toDouble();
    _stops = _buildStops();
  }

  @override
  void didUpdateWidget(covariant CameraZoomDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minZoom != widget.minZoom ||
        oldWidget.maxZoom != widget.maxZoom) {
      _stops = _buildStops();
      _value = _value.clamp(widget.minZoom, widget.maxZoom).toDouble();
    }
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  List<double> _buildStops() {
    final candidates = <double>[
      widget.minZoom, 0.6, 1, 2, 3, 5, 10, 20, widget.maxZoom,
    ]..sort();
    final values = <double>[];
    for (final stop in candidates) {
      if (stop < widget.minZoom - .001 || stop > widget.maxZoom + .001) {
        continue;
      }
      if (values.isEmpty || (values.last - stop).abs() > .01) {
        values.add(stop);
      }
    }
    return values.isEmpty ? [widget.minZoom] : values;
  }

  double _progressFor(double zoom) {
    if (_stops.length < 2) return 0;
    final value = zoom.clamp(_stops.first, _stops.last).toDouble();
    for (var i = 0; i < _stops.length - 1; i++) {
      if (value <= _stops[i + 1]) {
        final part = (value - _stops[i]) / (_stops[i + 1] - _stops[i]);
        return (i + part) / (_stops.length - 1);
      }
    }
    return 1;
  }

  double _zoomFor(double progress) {
    if (_stops.length < 2) return _stops.first;
    final position = progress.clamp(0.0, 1.0).toDouble() * (_stops.length - 1);
    final i = position.floor().clamp(0, _stops.length - 2).toInt();
    return _stops[i] + (_stops[i + 1] - _stops[i]) * (position - i);
  }

  String _format(double zoom) {
    final decimal = (zoom - zoom.round()).abs() < .045 ? 0 : 1;
    return '${zoom.toStringAsFixed(decimal)}×';
  }

  void _open() {
    _closeTimer?.cancel();
    if (!_expanded) setState(() => _expanded = true);
  }

  void _close() {
    _closeTimer?.cancel();
    if (_expanded && !_dragging) setState(() => _expanded = false);
  }

  void _scheduleClose() {
    _closeTimer?.cancel();
    if (!_expanded || _dragging) return;
    _closeTimer = Timer(_autoCloseDelay, () {
      if (mounted && !_dragging) _close();
    });
  }

  void _setValue(double target) {
    final next = target.clamp(widget.minZoom, widget.maxZoom).toDouble();
    if ((_value - next).abs() < .005) return;
    setState(() => _value = next); // Only redraws the tiny zoom widget.
    widget.onChanged(next);
  }

  void _onDragStart(DragStartDetails details) {
    _dragging = true;
    _open();
    _dragStartX = details.localPosition.dx;
    _dragStartProgress = _progressFor(_value);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    // Across the whole zoom range, moving one major segment takes ~65dp.
    // This is precise near 1x and does not jump between distant focal lengths.
    final pixelsPerSegment = math.max(62.0, 62.0 * (_stops.length - 1));
    final progress = (_dragStartProgress +
            (details.localPosition.dx - _dragStartX) / pixelsPerSegment)
        .clamp(0.0, 1.0)
        .toDouble();
    _setValue(_zoomFor(progress));
  }

  void _onDragEnd() {
    if (!_dragging) return;
    _dragging = false;
    widget.onSettled();
    _scheduleClose();
  }

  void _onTap(TapUpDetails details, double width) {
    if (!_expanded) {
      _open();
      _scheduleClose();
      return;
    }
    if (details.localPosition.dy >= 43) {
      // The active magnification chip is also an explicit close control.
      _close();
      return;
    }
    // Tapping ANY tick is usable: selection doesn't immediately hide ruler.
    if (_stops.length >= 2) {
      final progress = ((details.localPosition.dx - 13) / (width - 26))
          .clamp(0.0, 1.0)
          .toDouble();
      _setValue(_zoomFor(progress));
      widget.onSettled();
    }
    _scheduleClose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(320.0, constraints.maxWidth - 20)
              .clamp(130.0, 320.0)
              .toDouble();
          return Center(
            child: RepaintBoundary(
              child: SizedBox(
                width: width,
                height: 80, // Never reflows the viewfinder on expand/collapse.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) => _onTap(details, width),
                  onHorizontalDragStart: _onDragStart,
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: (_) => _onDragEnd(),
                  onHorizontalDragCancel: _onDragEnd,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 43,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _expanded ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            child: CustomPaint(
                              size: Size(width, 43),
                              painter: _ZoomRulerPainter(
                                stops: _stops,
                                progress: _progressFor(_value),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 84,
                        height: 35,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: CameraPalette.raised,
                          border: Border.all(
                            color: _expanded
                                ? CameraPalette.brass
                                : CameraPalette.stroke,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _format(_value),
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                                color: CameraPalette.cream,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              _expanded ? Icons.expand_less : Icons.expand_more,
                              color: CameraPalette.brass,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}

class _ZoomRulerPainter extends CustomPainter {
  const _ZoomRulerPainter({required this.stops, required this.progress});
  final List<double> stops;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (stops.length < 2) return;
    const start = 13.0;
    final length = size.width - 26;
    const baseline = 15.0;
    final background = Paint()
      ..color = CameraPalette.stroke
      ..strokeWidth = 1;
    final major = Paint()
      ..color = CameraPalette.muted
      ..strokeWidth = 1.1;
    canvas.drawLine(const Offset(start, baseline),
        Offset(start + length, baseline), background);
    for (var i = 0; i < stops.length; i++) {
      final x = start + i / (stops.length - 1) * length;
      canvas.drawLine(Offset(x, 9), Offset(x, 20), major);
      if (i < stops.length - 1) {
        for (var j = 1; j < 5; j++) {
          final px = x + j * length / ((stops.length - 1) * 5);
          canvas.drawLine(Offset(px, 12), Offset(px, 18), background);
        }
      }
      if (stops.length > 7 && i.isOdd && i != stops.length - 1) continue;
      final label = stops[i].toStringAsFixed(
          stops[i] == stops[i].roundToDouble() ? 0 : 1);
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 9,
            color: CameraPalette.muted,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          (x - painter.width / 2).clamp(0.0, size.width - painter.width)
              .toDouble(),
          28,
        ),
      );
      painter.dispose();
    }
    final x = start + progress.clamp(0.0, 1.0).toDouble() * length;
    canvas.drawLine(
      Offset(x, 1),
      Offset(x, 25),
      Paint()
        ..color = CameraPalette.brass
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ZoomRulerPainter old) =>
      old.progress != progress || old.stops != stops;
}
