# trpg-ai-master 위키

## 한 줄 요약

AI 던전 마스터와 실시간 채팅으로 진행하는 D&D 5e 솔로 TRPG 웹앱.

## 무엇을 하는 프로젝트인가

플레이어가 캐릭터를 만들고 AI와 1:1로 D&D 5e 솔로 캠페인을 플레이하는 Phoenix LiveView 웹앱이다. 핵심 기능은 다음과 같다.

- **캐릭터 생성**: 종족·클래스·배경·능력치·기술·장비·주문까지 7단계 위저드로 D&D 5e 룰에 맞는 캐릭터를 만든다.
- **AI 던전 마스터 채팅**: Claude / GPT / Gemini 중 하나를 골라 던전 마스터로 사용한다. 게임 상태를 시스템 프롬프트로 주입하고, AI는 tool call로 주사위 굴림·전투 처리·상태 변경을 호출한다.
- **TRPG 페이즈 루프**: 탐험 / 전투 / 대화 페이즈를 구분해 각 페이즈에서만 사용 가능한 도구를 노출한다.
- **캠페인 영속성**: 캠페인 하나당 GenServer 1 프로세스로 메모리 상태를 유지하고, 이벤트 발생 시 JSON으로 디스크에 저장한다. 세션 로그·요약·캐릭터 시트 모두 보존된다.
- **D&D 데이터 통합**: `lmh7201/dnd_reference_ko` 한국어 룰북 데이터를 fetch / 번들 로드해 ETS 캐시에 올리고, 캐릭터 생성과 AI 프롬프트에서 참조한다.

## 링크

- GitHub: https://github.com/lmh7201/trpg-ai-master
- 배포: https://trpg-ai-master.fly.dev (Fly.io, region `sin`)
- 외부 데이터 레포: https://github.com/lmh7201/dnd_reference_ko (private)
- 내부 문서:
  - [README.md](../README.md) — 빌드/실행/환경변수
  - [CLAUDE.md](../CLAUDE.md) — 코드 탐색용 가이드
  - [docs/refactoring-map.md](./refactoring-map.md) — 모듈 책임 분리 상세

## 기술 스택

| 영역 | 기술 |
|------|------|
| 언어 | Elixir 1.14+ (배포 빌드 1.17.3 / OTP 26) |
| 웹 프레임워크 | Phoenix 1.7 + Phoenix LiveView 0.20 |
| HTTP 서버 | Bandit 1.6 |
| 상태 관리 | GenServer (캠페인당 1 프로세스) + JSON 파일 영속성 |
| 캐시 | ETS (D&D 룰 데이터) |
| 프론트엔드 | Phoenix LiveView (서버 렌더링 + WebSocket), 커스텀 다크 판타지 CSS |
| AI 제공자 | Anthropic Claude / OpenAI GPT / Google Gemini |
| 마크다운 | Earmark |
| 배포 | Docker + Fly.io |
| 외부 데이터 | `lmh7201/dnd_reference_ko` (GitHub raw fetch 또는 로컬 번들) |

## 핵심 설계 결정

1. **캠페인당 GenServer 1 프로세스**
   캠페인 상태를 메모리에 유지하고 이벤트 시점에만 디스크로 직렬화한다. LiveView는 PID 또는 캠페인 ID로 server를 호출하는 transport 계층이다. 동시에 여러 캠페인이 떠 있어도 격리되며, 각 캠페인의 상태 전이가 단일 직렬 흐름으로 단순해진다.

2. **AI는 tool call로 게임 상태에 개입한다**
   서술형 텍스트를 파싱하지 않는다. AI가 주사위·전투·상태 변경을 하려면 `AI.ToolDefinitions`에 정의된 도구를 호출해야 하고, 결과는 `AI.ToolExecutor` → `Campaign.ToolHandler`를 거쳐 도메인에 반영된다. 페이즈별로 노출되는 도구가 달라서 (전투 중에만 공격 도구 노출 등) AI의 행동 범위를 룰로 제한할 수 있다.

3. **D&D 데이터는 외부 레포 + 다단 폴백**
   룰 데이터를 코드와 분리해 `lmh7201/dnd_reference_ko`에서 가져온다. 우선순위는 `DATA_GITHUB_TOKEN` fetch → `priv/data/srd/` 번들(CC BY 4.0, 항상 포함) → `priv/data/phb/` 병합(`DND_SRD_ONLY=false`) → `DND_EXTRA_DATA_DIR` 외부 디렉토리. 라이선스 분리(SRD vs PHB)와 오프라인 빌드를 동시에 만족한다.

4. **얇은 LiveView + helper 분리**
   `*Live` 모듈은 mount/handle_event/render만 담당한다. 서버 I/O는 `*Session`, 비즈니스 분기는 `*Flow`, assign 조립은 `*Presenter`로 분리한다 (`docs/refactoring-map.md` 1번 원칙). 테스트 가능한 순수 함수가 늘어나고 LiveView는 거의 전기 배선만 남는다.

5. **Provider 어댑터 + 공통 helper**
   AI provider 3종(`anthropic`, `openai`, `gemini`)은 같은 디렉토리 패턴을 따른다 — 각 provider의 `*.ex` 진입점 + 공유 `http.ex` / `retry.ex` / `standard_chat.ex` / `tool_execution.ex`. 새 provider를 추가할 때 인터페이스를 맞추기만 하면 된다.

## 참고할 만한 구현 패턴

### LiveView 책임 4분할 (Live → Session → Flow → Presenter)

LiveView가 비대해지는 흔한 문제를 다음 패턴으로 푼다. `CampaignLive` / `CharacterCreateLive` 모두 같은 패턴이다.

```
*Live          : transport (이벤트 수신, 분기 위임, render 호출)
  -> *Session  : GenServer/Manager I/O 래퍼 — 호출하고 결과를 표준 형태로 반환
  -> *Flow     : 비즈니스 분기 — player turn vs enemy turn, step 진행/검증 등
  -> *Presenter: assign 조립 — state → 화면용 데이터 변환 (State/Messages/ToolMessages 하위 분리)
```

장점: 각 helper가 순수 함수에 가까워 단위 테스트 가능 (`*_session_test.exs`, `*_flow_test.exs`, `*_presenter_test.exs`). LiveView 자체는 콜백 시그니처에 묶여 테스트가 어렵지만 본문이 거의 비어 있으므로 통합 테스트 1~2개로 충분하다.

### 시스템 프롬프트 = 섹션 조립

`AI.PromptBuilder.Sections`가 게임 상태를 섹션 단위로 마크다운으로 직렬화한다 (현재 페이즈, 파티 정보, 위치 설명, 최근 메시지 요약 등). 새 정보를 AI에 주입하려면 섹션 함수를 추가하고 `PromptBuilder`에서 조합한다. 프롬프트 길이가 길어졌을 때 어떤 섹션이 토큰을 많이 먹는지 한눈에 보인다.

### Tool 정의/실행/도메인 반영의 3단 분리

```
ToolDefinitions  : 어떤 도구가 어떤 phase에서 노출되는지 (스키마 + 메타)
ToolExecutor     : 도구 호출의 실제 부수 효과 (주사위 굴림, 룰 lookup, state 패치)
Campaign.ToolHandler : 도구 결과를 캠페인 도메인 상태에 반영
```

새 tool을 추가할 때 세 곳을 같이 건드리는 것이 강제된다. 정의만 있고 실행 안 되거나, 실행은 되는데 도메인에 반영 안 되는 경우를 컴파일/테스트 단계에서 잡기 쉽다.

### Mix task로 외부 데이터 → 라이선스 분리 번들 생성

`mix dnd.export_srd --source <path>` 가 단일 JSON 파일에서 `source: "SRD 5.2"` / `source: "PHB 2024"` 항목을 분리해 `priv/data/srd/` 와 `priv/data/phb/` 두 번들로 출력한다. 외부 데이터가 라이선스 혼재 상태일 때 빌드 시점에 분리해 배포본에 들어갈 데이터를 명시적으로 선택할 수 있다.

## 현재 상태

- **운영**: Fly.io에 배포됨 (`trpg-ai-master.fly.dev`, `sin` region). 캠페인 데이터는 `/data` 볼륨에 영속화.
- **AI 기본 모델**: `claude-sonnet-4-6` (`AI_MODEL` env로 변경 가능).
- **테스트**: LiveView helper / 도메인 / AI provider 단위 테스트가 `test/trpg_master*/` 에 존재.
- **최근 작업 흐름**: 책임 분리 리팩토링이 진행 중 — 캠페인 화면, 캐릭터 생성, AI provider, prompt builder, character_data 모두 helper 분리 완료. `docs/refactoring-map.md` 가 현재 상태의 기준 문서.
- **알려진 제약**: `dnd_reference_ko` 가 private 레포라 외부 기여자는 `DATA_GITHUB_TOKEN` 없이는 번들 데이터(SRD/PHB)로만 실행 가능.

## 갱신해야 하는 시점

다음 변경이 일어나면 이 문서를 함께 업데이트한다.

- **새로운 핵심 기능 추가/제거** → "무엇을 하는 프로젝트인가" 섹션 갱신
- **기술 스택 변경** (프레임워크 버전 메이저 변경, AI provider 추가/제거, 배포 플랫폼 변경 등) → 기술 스택 표, 링크
- **새로운 설계 결정** (예: 멀티 플레이어 지원, 다른 룰셋 추가, 인증 방식 변경) → 핵심 설계 결정 섹션
- **모듈 책임 분리 패턴 변경** (예: Session/Flow/Presenter 외 새로운 계층 도입) → 구현 패턴 섹션 + `docs/refactoring-map.md` 동기화
- **외부 데이터 소스 변경** (`dnd_reference_ko` 구조/위치 변경, 새 데이터 타입 추가) → 핵심 설계 결정 3번, 링크 섹션
- **배포 환경 변경** (region, 호스트, 볼륨 경로 등) → 현재 상태 섹션
- **알려진 제약 해소 또는 새 제약 등장** → 현재 상태 섹션
