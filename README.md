# Starlink Duo

두 대의 Android 기기를 Bluetooth Classic으로 연결해 플레이하는 2인 협동 덱빌딩 로그라이트입니다.

## 현재 상태

초기 수직 슬라이스를 구현 중입니다. 게임 규칙은 UI 및 전송 계층과 분리된 결정론적 상태 머신으로 구성합니다.

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

Android Bluetooth 플러그인은 다음과 같이 독립 컴파일합니다.

```bash
gradle -p android-plugin :plugin:assembleDebug
```

플러그인은 Android에서만 로드되며 데스크톱 개발 중에는 `LoopbackTransport`로 동일한 메시지 흐름을 검증합니다.

## 설계 원칙

- 호스트 권한 기반 결정론적 상태 동기화
- 공유 팀 체력과 플레이어별 덱·손패·에너지
- 캐릭터 전용 카드 96장과 공용 카드 48장을 동일 스키마로 관리
- 일반, 매직, 레어, 전설 등급을 색상뿐 아니라 형태와 문자로 구분
- 비행기 모드에서 Wi-Fi와 모바일 데이터 없이 Bluetooth만으로 완주 가능
