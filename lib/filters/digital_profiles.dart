import '../models/filter_preset.dart';

/// Independently created, subjective looks. S/C/N are creative inspirations,
/// NOT official Sony, Canon, or Nikon color science, LUTs, or endorsements.
const digitalCameraProfiles = <FilterPreset>[
  FilterPreset(
    id: 'digital_s', label: 'S · Crisp',
    exposure: -0.05, contrast: 14, highlights: -12, shadows: 5,
    whites: 5, blacks: -12, temperature: -6, tint: 1,
    vibrance: 8, saturation: 2, clarity: 6,
  ),
  FilterPreset(
    id: 'digital_c', label: 'C · Portrait',
    exposure: 0.12, contrast: -4, highlights: -18, shadows: 12,
    whites: 4, blacks: -4, temperature: 7, tint: 4,
    vibrance: 10, saturation: -3, clarity: -3,
  ),
  FilterPreset(
    id: 'digital_n', label: 'N · Vivid',
    exposure: 0.03, contrast: 12, highlights: -8, shadows: 2,
    whites: 8, blacks: -14, temperature: 2, tint: -3,
    vibrance: 18, saturation: 9, clarity: 7,
  ),
];
