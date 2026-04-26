# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Phoenix LiveView 기반 D&D 5e 솔로 TRPG 웹앱. AI 던전 마스터와 실시간 채팅으로 솔로 플레이를 진행한다. 빌드/실행/환경변수 등 운영 정보는 `README.md`를 참고한다. 이 문서는 코드베이스 구조와 개발 시 알아두면 좋은 컨벤션을 정리한다.

## 자주 쓰는 명령어

```bash
mix phx.server                                  # 개발 서버 (localhost:4000)
mix test                                        # 전체 테스트
mix test test/trpg_master_web/campaign_session_test.exs
mix test test/trpg_master_web/campaign_session_test.exs:42   # 특정 라인 테스트
mix dnd.export_srd --source <dnd_reference_ko_data_path>     # priv/data 번들 재생성
bash scripts/sync_dnd_data.sh                   # private 레포에서 priv/data 동기화
```

`mix setup`은 `deps.get` 후 `sync_dnd_data.sh`를 실행한다 (alias 정의: `mix.exs`).

## D&D 데이터 로드 우선순위

앱 기동 시 `Rules.CharacterData` / `Rules.Loader`가 다음 우선순위로 데이터를 로드한다 (자세한 환경변수는 `README.md` 참조).

1. `DATA_GITHUB_TOKEN` 있으면 → `lmh7201/dnd_reference_ko` GitHub raw URL fetch
2. 없으면 → `priv/data/srd/` (항상) + `priv/data/phb/` (`DND_SRD_ONLY=false` 일 때) + `DND_EXTRA_DATA_DIR` (지정 시) 병합

데이터 구조 변경 시 영향 받는 위치:
- `lib/trpg_master/rules/character_data.ex`, `lib/trpg_master/rules/loader/` — fetch & parsing
- `lib/trpg_master_web/live/character_create_live.ex` 와 `character_create_*` helper들 — `nameKo`, `skillProficienciesKo` 같은 한국어 필드명 직접 참조

## 아키텍처 (모듈 책임 분리)

코드베이스는 “큰 진입점은 얇게 유지하고, 책임을 helper로 분리”하는 방향으로 리팩토링되어 있다. 자세한 모듈 단위 설명은 `docs/refactoring-map.md`에 있다. 새 기능을 추가할 때 같은 패턴을 따른다.

### 캠페인 화면 (CampaignLive)

```
CampaignLive (transport)
  ├── CampaignSession    — Campaign.Server I/O 래퍼
  │     └── CampaignFlow — 비즈니스 분기 (player turn vs enemy turn 등)
  └── CampaignPresenter  — assign 조립 파사드
        ├── State        — campaign state → assign 변환
        ├── Messages     — 메시지 히스토리 변환
        └── ToolMessages — tool 결과를 화면 메시지에 추가
```

LiveView는 이벤트를 받아 분기·위임만 담당. 서버 호출은 `CampaignSession`, assign 조립은 `CampaignPresenter`로 보낸다.

### 캐릭터 생성 (CharacterCreateLive 7-step wizard)

```
CharacterCreateLive
  ├── CharacterCreateSession — assign/state 조립
  ├── CharacterCreateFlow    — step 진행/검증
  └── CharacterCreateActions — 이벤트 → state 변경 라우팅
```

도메인 로직(레벨업 계산, 선택 적용 등)은 `lib/trpg_master/characters/creation/` 에서 처리한다.

### 캠페인 도메인 (`lib/trpg_master/campaign/`)

- `Server` — 캠페인당 1 GenServer 프로세스. 상태는 메모리 + JSON 영속화.
- `ServerActions` — Server 콜백에서 호출하는 액션 helper (얇게 유지)
- `Manager` — 캠페인 CRUD
- `Persistence` — JSON 저장/로드
- `Combat`, `Exploration` — 전투/탐험 phase 전이
- `Summarizer` — 세션 요약 생성
- `ToolHandler` — AI tool call → 도메인 변경 적용

### AI 레이어 (`lib/trpg_master/ai/`)

```
AI.Client (단일 진입점, AI_MODEL/API 키로 provider 선택)
  ├── Providers (anthropic / openai / gemini)
  │     ├── http.ex          — 공통 HTTP 호출
  │     ├── retry.ex         — 재시도 정책
  │     ├── standard_chat.ex — 일반 채팅 호출
  │     └── tool_execution.ex — tool loop (multi-turn tool use)
  ├── PromptBuilder
  │     ├── Messages         — message 히스토리 변환
  │     └── Sections         — 시스템 프롬프트 섹션 조립 (게임 상태 기반)
  ├── ToolDefinitions        — phase별 노출되는 도구 목록
  ├── ToolExecutor           — dice / lookup / state 변경 실행
  └── RateLimiter
```

새 AI provider 추가 시 `Providers/` 아래 모듈 추가 + `Client`에서 라우팅 갱신. 새 tool 추가 시 `ToolDefinitions`에 정의 + `ToolExecutor`에 구현 + `ToolHandler`에서 도메인 반영.

## 위키 문서 동기화

`docs/wiki.md`는 프로젝트의 위키성 요약 문서다. 다음 변경이 발생하면 같은 PR/커밋에서 함께 갱신한다.

- 핵심 기능 추가/제거 → "무엇을 하는 프로젝트인가"
- 기술 스택 변경 (프레임워크 메이저 버전, AI provider 추가/제거, 배포 플랫폼 등) → 기술 스택 표 / 링크
- 새로운 설계 결정 (멀티 플레이어, 다른 룰셋, 인증 방식 등) → 핵심 설계 결정
- LiveView 책임 분리 패턴이 바뀜 → 구현 패턴 섹션 + `docs/refactoring-map.md` 동기화
- 외부 데이터 소스 / 배포 환경 / 알려진 제약 변경 → 현재 상태 섹션

`docs/wiki.md`의 마지막 "갱신해야 하는 시점" 섹션이 동일한 트리거 목록을 담고 있으니 그쪽도 같이 본다.

## 컨벤션

- **언어**: 모든 UI 텍스트, 메시지, 주석, 커밋 메시지는 한국어로 작성한다.
- **번역 용어**: `cantrip` → "소마법". 전체 용어 표는 부모 디렉토리 `CLAUDE.md` 또는 `dnd_reference_ko/class_translation_prompt.md` 참조. 영문 원문 번역 시 요약하지 않고 전문을 옮긴다.
- **모듈 분리 기준**: 한 파일이 “이벤트 받기 + 서버 호출 + assign 조립 + 렌더링”을 모두 하면 helper로 분리한다. `docs/refactoring-map.md`의 1~5번 원칙에 따른다.
- **테스트 위치**: LiveView 단위 테스트는 `test/trpg_master_web/`에, 도메인/AI/규칙 테스트는 `test/trpg_master/`에 둔다. `*_session_test.exs`, `*_flow_test.exs`, `*_presenter_test.exs` 처럼 helper별로 테스트 파일을 분리하는 패턴을 유지한다.

## 외부 데이터 의존성

`lmh7201/dnd_reference_ko` (private 레포)에서 D&D 5e 한국어 룰 데이터를 가져온다. trpg-ai-master와 별도 관리되며, 데이터 구조 변경 시 위 “데이터 구조 변경 영향 위치”를 확인할 것. 부모 디렉토리에 함께 클론되어 있다면 (`/Users/woong/Documents/GitHub/dnd_reference_ko/`) 직접 확인 가능하다.
