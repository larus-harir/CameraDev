# CH.4 v9.1 — 패키지 import 인식 오류 해결

스크린샷 오류:

- `Target of URI doesn't exist: 'package:camera_android/camera_android.dart'`
- `Target of URI doesn't exist: 'package:physical_lens_bridge/physical_lens_bridge.dart'`

원인 후보: v9는 `lib` 외에도 `pubspec.yaml`과 로컬 플러그인 `packages/physical_lens_bridge`를 추가했음. `lib`만 복사하면 import를 해결할 수 없음. 또한 `flutter pub get`이 실패했거나 Flutter 프로젝트 폴더가 다르면 동일 증상이 발생함.

## 가장 쉬운 적용

1. 이 ZIP을 원하는 폴더에 **압축 해제**한다. 프로젝트 안의 `lib`에 ZIP을 넣지 않는다.
2. VS Code에서 기존 앱을 중지하고, 압축 해제 폴더의 PowerShell에서 실행:

```powershell
.\APPLY_V9_1.ps1 -Project 'C:\KcwDev\flutter_application_1'
```

스크립트가 차단되면 직접 세 폴더/파일을 덮어쓰고 프로젝트 경로에서 `flutter pub get`을 실행한다. 실행 정책을 변경할 필요는 없다.

3. 출력에 `Resolved package: camera_android` 및 `Resolved package: physical_lens_bridge`가 보이는지 확인한다.
4. VS Code `Ctrl+Shift+P` → `Dart: Restart Analysis Server`.

## 수동 적용

- ZIP `lib/` 내용 → 프로젝트 `lib/`
- ZIP `packages/physical_lens_bridge/` → 프로젝트 `packages/physical_lens_bridge/`
- ZIP `pubspec.yaml` → 프로젝트 루트 `pubspec.yaml`

프로젝트 구조:

```text
C:\KcwDev\flutter_application_1\
  pubspec.yaml
  lib\main.dart
  lib\services\lens_catalog.dart
  packages\physical_lens_bridge\pubspec.yaml
  packages\physical_lens_bridge\lib\physical_lens_bridge.dart
  packages\physical_lens_bridge\android\src\main\java\dev\kcw\physical_lens_bridge\PhysicalLensBridgePlugin.java
```

그리고 프로젝트 루트 PowerShell에서:

```powershell
flutter pub get
flutter analyze
```

확인 명령:

```powershell
Test-Path .\packages\physical_lens_bridge\pubspec.yaml
Select-String -Path .\pubspec.yaml -Pattern 'camera_android|physical_lens_bridge'
Select-String -Path .\.dart_tool\package_config.json -Pattern 'camera_android|physical_lens_bridge'
```

`flutter pub get`에서 네트워크나 버전 충돌 오류가 나오면 빨간 import 밑줄 자체가 아니라 **pub get 전체 오류**를 확인해야 한다.

## 검증 한계

이번 패키지의 코드 자체는 v9와 동일하며 ZIP에 **일괄 적용 및 패키지 확인 스크립트**를 추가했다. 현재 제작 환경에는 Flutter/Android SDK가 없어 `flutter pub get`, `flutter analyze`, 삼성 실기기 빌드 성공은 직접 검증하지 않았다.

이 버전에서 실제 물리 렌즈 직접 선택 가능 범위는 휴대폰의 Camera2 카메라 공개 정책에 따라 달라진다.
