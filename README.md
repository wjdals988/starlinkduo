# Starlink Duo

두 대의 Android 기기를 Bluetooth Classic으로 연결해 협동 원정 또는 2인 결투를 플레이하는 덱빌딩 게임입니다.

## 현재 상태

전투·런 진행 수직 슬라이스와 Android Bluetooth 플러그인 패키징을 구현했습니다. 게임 규칙은 UI 및 전송 계층과 분리된 결정론적 상태 머신으로 구성합니다.

## 기술 구성

- Godot 4 / GDScript: 게임 코어, 콘텐츠, UI
- Kotlin / Android Gradle Plugin: Bluetooth Classic RFCOMM 플러그인
- GUT 없이 실행 가능한 헤드리스 테스트 러너

## 개발 실행

Godot 4가 설치된 환경에서 다음 명령을 사용합니다.

```bash
godot --path . --editor
godot --headless --path . --script res://tests/run_all.gd
```

Android Bluetooth 플러그인과 APK는 다음과 같이 빌드합니다. Godot 4.7.2 export template의 `android_source.zip`이 설치되어 있어야 합니다.

```bash
gradle -p android-plugin :plugin:assembleDebug :plugin:assembleRelease
cp android-plugin/plugin/build/outputs/aar/plugin-debug.aar addons/starlink_bluetooth/StarlinkBluetooth.debug.aar
cp android-plugin/plugin/build/outputs/aar/plugin-release.aar addons/starlink_bluetooth/StarlinkBluetooth.release.aar
godot --headless --path . --install-android-build-template --export-debug "Android Debug" builds/starlink-duo-debug.apk
```

플러그인은 Android에서만 로드되며 데스크톱 개발 중에는 `LoopbackTransport`로 동일한 메시지 흐름을 검증합니다. 앱과 플러그인의 최소 지원 버전은 모두 Android 12(API 31)입니다.

실제 갤럭시 2대의 기내모드 검증 범위와 증적 양식은 [실기기 E2E 절차](docs/DEVICE_E2E_TEST.md)를 따릅니다.

## 설계 원칙

- 호스트 권한 기반 결정론적 상태 동기화
- 협동의 공유 팀 체력과 결투의 플레이어별 36 내구도를 분리
- 결투에서는 캐릭터별 표준 8장 덱과 비공개 동시 계획 사용
- 캐릭터 전용 카드 96장과 공용 카드 48장을 동일 스키마로 관리
- 일반, 매직, 레어, 전설 등급을 색상뿐 아니라 형태와 문자로 구분
- 비행기 모드에서 Wi-Fi와 모바일 데이터 없이 Bluetooth만으로 완주 가능
