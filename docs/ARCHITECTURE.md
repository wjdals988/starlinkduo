# 아키텍처

## 경계

```text
Godot UI -> RunCoordinator -> CombatEngine
                    |              |
                    v              v
             SessionTransport   Data Resources
                    |
                    v
          Android Bluetooth Plugin
```

- `CombatEngine`: 화면과 네트워크를 모르는 순수 결정론적 규칙 계층
- `RunCoordinator`: 맵, 보상, 저장과 전투 상태 전환을 조정
- `SessionTransport`: 로컬 및 Bluetooth 전송의 공통 인터페이스
- Android 플러그인: 검색, 광고, 페어링과 RFCOMM 소켓 입출력만 담당

## 호스트 권한 모델

- 참가자는 의도 명령만 전송한다.
- 호스트는 명령을 검증하고 결과 이벤트와 상태 해시를 배포한다.
- 모든 난수는 런 시드와 명시적인 난수 호출 순서에서 생성한다.
- 양쪽 상태 해시가 다르면 호스트의 마지막 확정 스냅샷으로 복구한다.
- 모든 메시지는 프로토콜 버전과 단조 증가 순번을 가지며, 중복·역순 명령은 거부한다.
- 참가자는 슬롯 1의 계획만 제출할 수 있고 호스트만 전투 해결 및 스냅샷 배포를 수행한다.
- Bluetooth 연결과 게임 시작은 별도 상태다. 핸드셰이크가 끝나도 양쪽은 대기실에 남고, 호스트의 `game_start` 메시지를 받은 뒤에만 전투 UI로 전환한다.
- `game_start`는 선택 모드와 일치해야 하며 참가자나 핸드셰이크 전 호스트의 시작 요청은 거부한다.
- 빠른 메시지는 `ready`, `wait`, `attack`, `defend`, `nice`, `sorry`의 허용 목록만 전송한다. 호스트가 참가자 메시지를 검증해 양쪽에 중계하며 자유문자 payload는 거부한다.

## Android 전송

- Godot Android Plugin v2와 Kotlin을 사용한다.
- Android 12 이상에서 Bluetooth 스캔, 광고 및 연결 권한을 런타임에 요청한다.
- 메시지는 4바이트 길이와 최대 1MiB UTF-8 payload로 프레이밍한다.
- 블로킹 accept, connect, read는 UI 스레드가 아닌 전용 executor에서 실행한다.
- 플러그인 상태와 수신 메시지는 GDScript가 폴링하고 게임 계층의 신호로 변환한다.

## Android 접근성 브리지

- Godot UI는 Android에서 하나의 `SurfaceView`로 렌더링되므로 `AndroidAccessibilityBridge`가 현재 화면의 의미 이름·설명·활성 상태·좌표를 플러그인에 전달한다.
- 플러그인의 투명 `AccessibilityOverlayView`는 화면을 그리지 않고 Android 가상 버튼·텍스트 노드만 제공하며 일반 터치는 아래 Godot 렌더 뷰로 통과시킨다.
- 접근성 `ACTION_CLICK`은 정수 ID 큐로 Godot 메인 루프에 돌아와 현재 유효하고 활성화된 `BaseButton`만 실행한다. 화면 전환 후 폐기된 ID는 무시한다.
- 모달이 열리면 동기화 루트를 모달로 제한해 배경 전투 컨트롤이 TalkBack 탐색 순서에 남지 않도록 한다.

## 저장 지점

- 노드 진입 전
- 보상 확정 후
- 상점 구매 후
- 전투 턴 시작 시
