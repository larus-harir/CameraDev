import '../models/filter_preset.dart';

/// FILM: four intentionally different looks (your Lightroom look + 3 originals).
/// These are independent approximations; they do not reproduce branded film stocks.
/// Fine-tune here without changing the shooting UI.
/// 'original' remains an internal, unfiltered processing profile for dual-save.
const List<FilterPreset> myCameraPresets = [
  // 01 | Your original Lightroom values, preserved exactly.
  FilterPreset(
    id: 'preset_01', label: 'My Lightroom 01',
    exposure: 0.10, contrast: 8,
    highlights: 8, shadows: -3, whites: 10, blacks: -8,
    temperature: 2, tint: -1, vibrance: 20, saturation: -6,
    texture: 0, clarity: 0, dehaze: 0, vignette: 0, grain: 0,
  ),
  // 02 | Rainy blue hour: subdued highlights, cool shadows and soft grain.
  FilterPreset(
    id: 'preset_02', label: 'Blue Hour',
    exposure: -0.22, contrast: 16,
    highlights: -35, shadows: 10, whites: -18, blacks: -19,
    temperature: -24, tint: 6, vibrance: -5, saturation: -19,
    texture: 3, clarity: 6, dehaze: 5, vignette: -16, grain: 9,
  ),
  // 03 | Warm, low-contrast faded summer negative.
  FilterPreset(
    id: 'preset_03', label: 'Amber 98',
    exposure: 0.22, contrast: -21,
    highlights: -30, shadows: 25, whites: -12, blacks: 21,
    temperature: 22, tint: 7, vibrance: 5, saturation: -12,
    texture: -8, clarity: -12, dehaze: -9, vignette: -10, grain: 14,
  ),
  // 04 | Hard black-and-white street photography, classic grain.
  FilterPreset(
    id: 'preset_04', label: 'Noir 400',
    exposure: -0.08, contrast: 34,
    highlights: -22, shadows: -15, whites: 21, blacks: -32,
    temperature: 0, tint: 0, vibrance: -100, saturation: -100,
    texture: 18, clarity: 22, dehaze: 11, vignette: -24, grain: 25,
  ),
];
