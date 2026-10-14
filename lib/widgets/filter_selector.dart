import 'package:flutter/material.dart';
import '../models/filter_preset.dart';

class FilterSelector extends StatelessWidget {
  final String selectedId;
  final double strength;
  final ValueChanged<String> onSelected;
  final ValueChanged<double> onStrengthChanged;
  const FilterSelector({super.key, required this.selectedId, required this.strength,
    required this.onSelected, required this.onStrengthChanged});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.black87,
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(height: 46, child: ListView(
        scrollDirection: Axis.horizontal,
        children: CameraFilters.presets.map((filter) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ChoiceChip(label: Text(filter.label),
            selected: selectedId == filter.id,
            onSelected: (_) => onSelected(filter.id)),
        )).toList(),
      )),
      Row(children: [
        const SizedBox(width: 12),
        const Text('강도', style: TextStyle(fontSize: 12)),
        Expanded(child: Slider(value: strength, min: 0, max: 1,
          onChanged: selectedId == 'original' ? null : onStrengthChanged)),
        SizedBox(width: 48, child: Text('${(strength * 100).round()}%',
          style: const TextStyle(fontSize: 12))),
      ]),
    ]),
  );
}
