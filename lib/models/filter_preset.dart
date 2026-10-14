import 'package:flutter/material.dart';
import '../filters/my_presets.dart';

/// Lightroom-inspired settings. Values approximate Lightroom, not identical.
class FilterPreset {
  final String id, label;
  final double exposure, contrast, highlights, shadows, whites, blacks;
  final double temperature, tint, vibrance, saturation;
  final double texture, clarity, dehaze, vignette, grain;
  const FilterPreset({required this.id, required this.label,
    this.exposure = 0, this.contrast = 0, this.highlights = 0,
    this.shadows = 0, this.whites = 0, this.blacks = 0,
    this.temperature = 0, this.tint = 0, this.vibrance = 0,
    this.saturation = 0, this.texture = 0, this.clarity = 0,
    this.dehaze = 0, this.vignette = 0, this.grain = 0});
}

class CameraFilters {
  static const identity = <double>[
    1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0,
  ];
  static const presets = myCameraPresets;
  static FilterPreset byId(String id) => presets.firstWhere(
    (f) => f.id == id, orElse: () => presets.first);

  /// Fast GPU preview approximation. Selective tonal and spatial effects are
  /// rendered on exported JPEG only; preview is therefore not pixel-identical.
  static List<double> mixedMatrix(FilterPreset p, double strength) {
    final amount = strength.clamp(0.0, 1.0);
    if (p.id == 'original' || amount == 0) return List.of(identity);
    final contrast = 1 + p.contrast.clamp(-100,100) / 100;
    final sat = (1 + (p.saturation + p.vibrance * 0.45).clamp(-100,100) / 100).clamp(0.0,2.0);
    final exposure = (p.exposure.clamp(-5,5) * 35);
    final warmth = p.temperature.clamp(-100,100) * 0.5;
    final tint = p.tint.clamp(-100,100) * 0.4;
    final offset = 128 * (1 - contrast) + exposure + p.whites * 0.10 + p.blacks * 0.10;
    const weights = [0.2126,0.7152,0.0722];
    final rows = <List<double>>[];
    for (var channel=0; channel<3; channel++) {
      final row = <double>[];
      for (var source=0; source<3; source++) {
        row.add(contrast * ((channel==source ? sat : 0) + (1-sat)*weights[source]));
      }
      row.add(0);
      row.add(offset + (channel==0 ? warmth : channel==2 ? -warmth : tint));
      rows.add(row);
    }
    final full = [...rows[0],...rows[1],...rows[2],0.0,0.0,0.0,1.0,0.0];
    return List<double>.generate(20, (i)=>identity[i]+(full[i]-identity[i])*amount);
  }
  static ColorFilter colorFilter(FilterPreset p,double strength) =>
    ColorFilter.matrix(mixedMatrix(p,strength));
}
