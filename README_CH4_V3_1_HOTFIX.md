# CH.4 v3.1 — 컴파일 오류 누락 함수 복구

## 수정 내역

v3에서 `lib/screens/camera_screen.dart`를 리디자인하는 과정에서 누락된 기존 메서드 5개를 복구했습니다.

- `_setStyle(CameraStyle next)`: DIGITAL / FILM 모드 전환
- `_updateFilter(String id, double strength)`: 선택 필터 및 강도 변경과 모드별 설정 갱신
- `_saveLook({bool immediate = false})`: 마지막으로 사용한 디지털/필름 프리셋 저장 (슬라이더 입력 디바운스)
- `_cycleRatio()`: 사진·동영상 화면비 전환
- `_cycleTimer()`: 타이머 OFF / 3 / 5 / 10초 순환

## 적용

기존 프로젝트를 백업한 다음 이 ZIP의 `lib` 폴더를 프로젝트에 덮어쓰세요. 파일 1개만 교체하고 싶다면 `lib/screens/camera_screen.dart`만 교체해도 됩니다.

```powershell
cd C:\KcwDev\flutter_application_1
dart format lib
flutter analyze
flutter run
```

## 검증 범위

이 환경에서는 Flutter SDK가 없어 실제 `flutter analyze` 및 Android 빌드를 수행하지 못했습니다. v3 코드와 v2 구현을 비교하여 누락된 호출 대상 5개를 복구하고 ZIP 파일 검증 및 코드 정적 구조 점검을 수행했습니다.
