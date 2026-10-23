# CH.4 v9 — Camera2 렌즈 선택과 플랫폼별 카메라 분리

## 어떤 부분을 실제로 구현했나

- Android 카메라 백엔드를 Flutter `camera_android` (Android Camera2)로 교체함.
- `packages/physical_lens_bridge` 로컬 Flutter 네이티브 플러그인을 추가.
- Android Camera2의 `CameraManager.getCameraIdList()` / `CameraCharacteristics` / `getPhysicalCameraIds()`로 카메라 ID, 렌즈 방향, 초점거리, 센서 크기, 논리 카메라 여부를 읽음.
- 실제 `availableCameras()` 목록에 있는 Camera2 ID만 선택 가능하도록 제한. 선택 시 컨트롤러를 닫고 그 **동일한 ID**로 다시 열어서 사진·영상·초점·플래시 등 기존 기능에 연결.
- 초점거리와 센서 물리 크기로 35mm 환산 초점거리를 계산하고 1배 기준을 근사. 예: 13mm/26mm/78mm 카메라가 모두 앱에 노출되면 약 0.5/1/3배로 표시.
- 플러그인에서 감지한 물리 렌즈가 Camera2를 통해 **독립적으로 열 수 없으면 선택 불가**로 별도 표시. 존재하지 않는 렌즈를 0.6/3배 버튼으로 속여 표기하지 않음.
- iOS에서는 기본 `camera_avfoundation`이 보고한 `CameraDescription.lensType` (ultraWide/wide/telephoto)을 동일한 렌즈 선택 화면에서 사용하도록 공통 코드 준비.
- 렌즈 선택 아래에 **렌즈 진단 결과 복사** 버튼 추가. 실제 기종의 렌즈 공개 범위를 확인 가능.

## 중요한 한계 — 반드시 구분

1. **검증 미완료:** 작성 환경에 Flutter/Android SDK 및 해당 삼성 실기기가 없어 컴파일·실기기 작동을 직접 검증하지 못했습니다. 예전처럼 `작동 보장`이라고 주장하지 않습니다.
2. 카메라 ID를 특정해서 여는 것은 *독립적으로 공개된 센서에 한해* 실제 렌즈 선택입니다. 삼성 기기가 논리 멀티 카메라 내부에만 숨겨 둔 물리 ID는 일반 Camera2 `openCamera(id)`로 직접 열 수 없습니다. 그러면 Camera2 OutputConfiguration/물리 ID를 연결하는 **네이티브 캡처 세션 자체 구현** 또는 벤더별 지원이 필요합니다.
3. 계속 줌을 밀 때 광각→망원으로 자동 전환하는 **무중단 렌즈 스위칭은 이번 버전에 포함되지 않았습니다.** 렌즈 버튼에서 개별 선택하며, 선택한 렌즈 안에서의 줌은 Camera2 디지털 줌입니다.
4. 35mm 환산 초점거리는 **근사값**입니다. 삼성 카메라 앱 자체의 0.6·1·3배 계산/렌즈 융합과 차이 날 수 있습니다.
5. 실제 하드웨어 렌즈를 선택해도 삼성 자체 앱의 멀티프레임 HDR, 나이트모드, 초해상도, AI 노이즈 처리 등 제조사 전용 이미지 품질은 자동으로 따라오지 않습니다.
6. 아이폰에서는 이미 노출된 AVFoundation 개별 렌즈 선택이 가능하지만, iOS 하드웨어에서 촬영·녹화·렌즈별 플래시 등의 전기종 동작 보장은 별도 실기기 시험이 필요합니다.

## 적용 방법

**중요: `lib` 폴더만 덮어쓰면 안 됩니다.** 이번 버전은 Android 네이티브 플러그인과 신규 패키지 의존성이 들어갔습니다.

1. 기존 프로젝트를 Git에 커밋하거나 전체 백업합니다.
2. 이 ZIP의 `lib` 전체, `pubspec.yaml`, `packages/physical_lens_bridge` 폴더를 프로젝트 루트에 복사합니다.
3. 프로젝트 루트에서 아래를 실행합니다.

```powershell
cd C:\KcwDev\flutter_application_1
flutter clean
flutter pub get
dart format lib test
flutter analyze
flutter test test/lens_catalog_test.dart
flutter build apk --debug
```

`flutter clean`이 `.plugin_symlinks` 파일 잠금으로 실패한다면 VS Code, 실행 중 Flutter 앱을 종료하거나 해당 폴더 잠금을 해제한 후 재실행하세요. 이전 대화에서 발생한 Windows 파일 잠금 문제와 APK 설치 오류는 별개입니다.

4. 휴대폰에서 카메라 실행 → 우측 하단 `렌즈` → 지원 카메라 목록 확인 → `초광각/광각/망원`에 해당하는 카메라 ID를 직접 열어 사진/동영상 촬영합니다. 화각이 실제로 변하는지 확인합니다.
5. 물리 렌즈가 감지되지만 잠김으로만 보이면 `렌즈 진단 결과 복사` 버튼을 누르고 이 대화에 붙여 넣습니다. 이 정보로 해당 SM-S721N의 물리 ID 접근 범위를 정확히 판별하고 Camera2 출력 세션 구현 필요 여부를 결정할 수 있습니다.

## 예상 확인 항목

- 렌즈 목록의 `Camera2 id`, `35mm 환산 초점거리`, `선택 가능 여부`
- 0.6/1/3배 렌즈 각각에서 **동일한 위치에 놓인 피사체의 화각** 비교 (1× 디지털 크롭과 물리 망원 구분)
- 광각 / 망원 전환 이후 사진 촬영, 동영상 시작·정지, 터치 포커스, 플래시/라이트
- 반복 전환 중 `CameraException` 발생 여부
- 외부 저장소에 저장된 필터본·원본의 해상도, 품질

## 데이터 경로

```
Flutter UI
 ├─ LensCatalog → Android Camera2 기기 메타데이터 (네이티브 MethodChannel)
 └─ CameraService → camera / CameraController
                    ├─ Android: camera_android(Camera2) 선택한 cameraId 직접 열기
                    └─ iOS: camera_avfoundation 개별 lensType 카메라 사용
```

이 구현은 **센서 선택 경로를 바꾼 개발/테스트용 버전**으로, 제조사 기본 카메라와 완전히 동일한 줌과 화질을 제공하는 완성본으로 표현하면 안 됩니다.
