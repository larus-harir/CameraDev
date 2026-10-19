# CH.4 v1 — DIGITAL / FILM 카메라 UI 및 색감 프로파일

기준: CH.3 UI Unified v4. 기존 촬영·갤러리·동영상/사진 저장 경로를 유지하고 UI 및 스타일 선택을 추가한 업데이트입니다.

## 핵심 UX

- `DIGITAL`: 레트로 디카 스타일. 별도 창이 아닌 촬영 화면 위에 간결한 REC/STBY, 화면비, 줌, 현재 날짜 HUD가 표시됩니다.
- `FILM`: 기존 `lib/filters/my_presets.dart` 프리셋 + 35mm 필름 게이트 프레임. 프레임 번호가 촬영할 때마다 증가하며 재실행 뒤에도 유지됩니다.
- `PHOTO / VIDEO`는 DIGITAL/FILM 스타일과 독립적으로 유지됩니다.
- 기본 화면: 스타일, 필수 버튼(플래시·타이머·화면비·그리드), 색감 목록, 줌, PHOTO/VIDEO, 셔터·앨범·렌즈.
- `[기능]`: 마이크(동영상), 렌즈 변경, 앨범, 앱 설정, 그리드 등 보조 기능을 펼칩니다.
- 색감 강도 슬라이더는 선택적으로 펼칩니다.

## DIGITAL S / C / N

| UI | 자체 프로파일 이름 | 특징 |
|---|---|---|
| S | S · Crisp | 다소 차갑고 선명한 대비 중심 |
| C | C · Portrait | 조금 더 따뜻하고 부드러운 인물 중심 |
| N | N · Vivid | 자연물 대비 및 채도가 강조된 색감 |

**중요:** S/C/N은 Sony/Canon/Nikon의 **공식 색 재현 또는 제조사 LUT가 아닙니다.** 제품에서 연상되는 분위기를 참고하여 독립적으로 설계한 주관적인 색감 근사치입니다. 실제 카메라와 기종별 RAW/JPEG 색 처리가 다릅니다. 회사 로고/상표 및 공식 협업 표시를 사용하지 않았습니다.

값 변경: `lib/filters/digital_profiles.dart`. 기존 필카 프리셋은 그대로 `lib/filters/my_presets.dart`에서 수정합니다.

## 필름 프레임 저장

- FILM 스타일 미리보기에는 항상 필름 게이트를 보여줍니다.
- 설정 > **필카 프레임을 결과물에도 저장** (기본 ON) 시: 사진 JPEG에 실제 테두리를 넣고, 영상은 FFmpeg drawbox 필터로 테두리를 인코딩합니다.
- **필터+원본 동시 저장**이 활성화되면 원본에는 필름 테두리를 넣지 않습니다. 원본의 화면비 크롭은 기존 정책에 따라 적용됩니다.
- Original 프리셋을 골라도 필카 테두리 ON이면 프레임이 들어간 결과물 1개를 저장합니다.
- 디카의 HUD(날짜/ISO/줌)는 기본적으로 **미리보기 전용**이며 저장 파일에는 새기지 않습니다.
- 필름 프레임 디자인은 UI 미리보기와 저장 결과에서 **유사하지만 픽셀 단위로 동일하지 않습니다.** 사진/영상과 기기 방향에 따라 프레임 비례도 차이날 수 있습니다.
- 필카 프레임이 들어간 동영상은 Original 색감이라도 재인코딩됩니다. 영상이 길수록 저장이 늦어집니다.

## 설정과 호환성

- 스타일 및 각 스타일에서 마지막으로 선택한 프로파일/강도를 `shared_preferences`로 저장합니다.
- 기존 CH.3 `filterId/filterStrength` 값은 **FILM 프리셋으로 이전**하여 보존합니다.
- PHOTO/VIDEO 공통 인터페이스를 사용하며, 실제 마이크 버튼은 비디오 전용입니다.
- 기존 카메라 초기화 재시도 및 저장 백그라운드 처리 구조를 유지합니다.
- `pubspec.yaml` 의 기존 패키지만 이용해 **새 의존성은 추가하지 않았습니다.**

## 설치 및 실행

1. 기존 프로젝트 전체를 Git에 커밋 또는 백업하세요.
2. 이 ZIP의 `lib` 폴더를 `C:\KcwDev\flutter_application_1\lib`에 덮어쓰세요.
3. `pubspec.yaml`은 포함되어 있으나 CH.3과 같으며 새로운 패키지 설치는 필요 없습니다.
4. AndroidManifest.xml은 기존에 바로잡은 버전을 유지하세요(이 ZIP은 매니페스트를 포함하지 않음).
5. 터미널:

```powershell
cd C:\KcwDev\flutter_application_1
flutter pub get
dart format lib
flutter analyze
flutter run
```

## 실기기 QA 체크리스트

- [ ] 첫 실행 / 권한 재허용 후 초기화 성공
- [ ] 사진↔동영상 전환 5회 반복 후 화면 정상
- [ ] DIGITAL S/C/N 프로파일 선택 후 JPEG 색감 차이 확인
- [ ] FILM 기존 프리셋의 강도 조절 및 프리셋 유지
- [ ] DIGITAL↔FILM 전환 후 선택값/강도 개별 복원 확인
- [ ] 사진 비율 4:3/16:9/1:1 저장
- [ ] FILM 사진 프레임 ON/OFF 비교, 원본 동시 저장 시 프레임 미포함 확인
- [ ] FILM MP4 프레임 ON/OFF, 16:9/4:3/1:1 및 회전 재생 확인
- [ ] DIGITAL 동영상 S/C/N 필터 색감 저장 확인
- [ ] 10초 이상 촬영 후 저장 중에도 카메라 조작 반응 확인
- [ ] 세로/가로 레이아웃 및 화면이 작은 폰에서 오버플로 없음
- [ ] 그리드, 줌, 타이머, 플래시, 마이크, 촬영 미리보기, 갤러리 작동 확인

## 검증 상태

이 환경에서 Flutter/Dart SDK와 실기기 빌드는 실행할 수 없으므로 **전체 앱 빌드 및 실제 카메라 촬영 결과는 아직 검증되지 않았습니다.** 소스 파일 괄호 구조 및 ZIP 압축 구조를 점검했고, 필름 테두리 포함 FFmpeg 그래프는 별도 샘플 MP4에 대해 실행해 성공했습니다. 만일 `flutter analyze` 또는 `flutter run`에서 오류가 발생하면 로그를 그대로 전달해 주세요.

## 파일 구성 변경

- 추가: `lib/models/camera_style.dart`
- 추가: `lib/filters/digital_profiles.dart`
- 추가: `lib/widgets/camera_chrome.dart`
- 수정: `lib/models/filter_preset.dart` (디카/필카 id 검색)
- 수정: `lib/models/camera_settings.dart` (필름 프레임 저장 토글)
- 수정: `lib/services/settings_service.dart` (스타일/색감/프레임 번호 유지)
- 수정: `lib/services/filter_service.dart` (사진 필름 게이트 저장)
- 수정: `lib/services/video_filter_service.dart` (영상 필름 게이트 저장)
- 수정: `lib/screens/camera_screen.dart` (촬영 화면 UI 및 상태 연결)
- 수정: `lib/screens/settings_screen.dart` (필카 프레임 저장 옵션)
- 수정: `lib/main.dart` (전체 테마)

`docs/CH4_MOODBOARD_REFERENCE.png`는 UI 감성 참고용 시안이며 실제 앱 화면의 스크린샷은 아닙니다.
