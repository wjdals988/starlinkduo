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

## Android 전송

- Godot Android Plugin v2와 Kotlin을 사용한다.
- Android 12 이상에서 Bluetooth 스캔, 광고 및 연결 권한을 런타임에 요청한다.
- 메시지는 4바이트 길이와 최대 1MiB UTF-8 payload로 프레이밍한다.
- 블로킹 accept, connect, read는 UI 스레드가 아닌 전용 executor에서 실행한다.
- 플러그인 상태와 수신 메시지는 GDScript가 폴링하고 게임 계층의 신호로 변환한다.

## 저장 지점

- 노드 진입 전
- 보상 확정 후
- 상점 구매 후
- 전투 턴 시작 시
