import '../models/filter_preset.dart';

/// ================================================================
/// 이 파일만 수정해서 필터의 색감을 변경할 수 있습니다.
/// ================================================================
/// 빛: exposure(-5~+5 EV), contrast/highlights/shadows/whites/blacks(-100~100)
/// 색상: temperature(-100 차갑게 ~ +100 따뜻하게), tint(-100 초록 ~ +100 자홍)
///       vibrance(-100~100, 저채도 우선), saturation(-100~100, 전체 채도)
/// 효과: texture(-100~100, 미세 디테일), clarity(-100~100, 국소 대비),
///       dehaze(-100~100, 안개/대비 근사), vignette(-100~100, 음수 가장자리 어둡게),
///       grain(0~100, 필름 입자)
/// 모든 값의 0은 효과 없음. strength 0%는 원본, 100%는 설정값 전체.
/// Lightroom과 알고리즘은 다르며 결과는 근사치입니다.
/// 톤 커브는 이번 버전에 포함되지 않았습니다.
/// 참고: highlights/shadows/texture/clarity/dehaze/vignette/grain은
/// 저장된 사진에 적용됩니다. 실시간 프리뷰는 색상 매트릭스 근사만 표시합니다.
/// 프리셋을 추가할 때 id는 중복되지 않게 해주세요.
const List<FilterPreset> myCameraPresets = [
  FilterPreset(id: 'original', label: 'Original'),

  // 전달해 준 Lightroom 설정: 곡선 제외, 효과 값 모두 0.
  FilterPreset(
    id: 'preset_01', label: 'My Lightroom 01',
    exposure: 0.10, contrast: 8,
    highlights: 8, shadows: -3, whites: 10, blacks: -8,
    temperature: 2, tint: -1, vibrance: 20, saturation: -6,
    texture: 0, clarity: 0, dehaze: 0, vignette: 0, grain: 0,
  ),

  FilterPreset(id: 'preset_02', label: 'Preset 2',
    exposure: -0.10, contrast: 12, saturation: -12, temperature: -15),
  FilterPreset(id: 'preset_03', label: 'Preset 3', saturation: -100),
  FilterPreset(id: 'preset_04', label: 'Preset 4',
    exposure: 0.15, contrast: -15, saturation: -25, temperature: 12, grain: 12),
  FilterPreset(id: 'preset_05', label: 'Preset 5',
    exposure: -0.10, contrast: 18, saturation: 8, temperature: -6),
];
