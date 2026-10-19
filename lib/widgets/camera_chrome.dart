import 'package:flutter/material.dart';
import '../models/camera_style.dart';
import '../models/filter_preset.dart';

/// CH.4 design tokens: black metal, warm brass, understated camera typography.
class CameraPalette {
  static const base = Color(0xFF0B0C0C);
  static const panel = Color(0xFF191A18);
  static const raised = Color(0xFF272723);
  static const brass = Color(0xFFD8B884);
  static const muted = Color(0xFF9E9C92);
  static const cream = Color(0xFFF0EADD);
  static const stroke = Color(0xFF48453D);
}

class CameraStyleToggle extends StatelessWidget {
  const CameraStyleToggle({super.key, required this.style, required this.onSelected, this.enabled = true});
  final CameraStyle style;
  final ValueChanged<CameraStyle> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: CameraPalette.raised,
      border: Border.all(color: CameraPalette.stroke),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      for (final item in CameraStyle.values)
        GestureDetector(
          onTap: enabled ? () => onSelected(item) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: style == item ? CameraPalette.brass : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(item.title,
              style: TextStyle(
                fontFamily: 'monospace', fontSize: 11, letterSpacing: 1.5,
                fontWeight: FontWeight.w800,
                color: style == item ? CameraPalette.base : CameraPalette.muted,
              ),
            ),
          ),
        ),
    ]),
  );
}

class CameraIconControl extends StatelessWidget {
  const CameraIconControl({super.key, required this.icon, required this.title,
    required this.onPressed, this.active = false, this.compact = false});
  final IconData icon;
  final String title;
  final VoidCallback? onPressed;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true, label: title,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 9, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? CameraPalette.brass : CameraPalette.cream,
            size: compact ? 19 : 21),
          const SizedBox(height: 3),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: CameraPalette.muted)),
        ]),
      ),
    ),
  );
}

class LookSelector extends StatelessWidget {
  const LookSelector({super.key, required this.style, required this.presets,
    required this.selectedId, required this.onSelected});
  final CameraStyle style;
  final List<FilterPreset> presets;
  final String selectedId;
  final ValueChanged<String> onSelected;

  static const swatches = <Color>[
    Color(0xFF8AA8B7), Color(0xFFDDBA8E), Color(0xFF698778),
    Color(0xFFBAA281), Color(0xFFB4A0A0), Color(0xFF8A806C),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 73,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: presets.length,
      separatorBuilder: (_, __) => const SizedBox(width: 7),
      itemBuilder: (context, index) {
        final preset = presets[index];
        final selected = selectedId == preset.id;
        final swatch = swatches[index % swatches.length];
        return Semantics(
          button: true, selected: selected, label: '${preset.label} 색감',
          child: InkWell(
            onTap: () => onSelected(preset.id),
            borderRadius: BorderRadius.circular(9),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: style == CameraStyle.digital ? 106 : 116,
              padding: const EdgeInsets.fromLTRB(9, 7, 8, 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: selected ? CameraPalette.brass : CameraPalette.stroke,
                  width: selected ? 1.5 : 1),
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color.lerp(swatch, CameraPalette.raised, .55)!, CameraPalette.panel],
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 7, height: 7,
                    decoration: BoxDecoration(color: selected ? CameraPalette.brass : swatch, shape: BoxShape.circle)),
                  const Spacer(),
                  Text(style == CameraStyle.digital ? 'CCD' : 'FILM',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                      color: selected ? CameraPalette.brass : CameraPalette.muted)),
                ]),
                const Spacer(),
                Text(preset.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: selected ? CameraPalette.cream : CameraPalette.muted)),
                const SizedBox(height: 2),
                Container(height: 2, width: selected ? 36 : 22, color: selected ? CameraPalette.brass : CameraPalette.stroke),
              ]),
            ),
          ),
        );
      },
    ),
  );
}

