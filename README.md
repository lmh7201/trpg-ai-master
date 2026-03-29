# trpg-ai-master

Phoenix LiveView 기반 D&D 5e 솔로 TRPG 웹앱. AI 던전 마스터와 실시간 채팅으로 솔로 플레이를 진행하며, 캐릭터 생성부터 전투/탐험/대화 페이즈까지 전체 TRPG 루프를 지원한다.

## 기술 스택

- **언어/프레임워크**: Elixir 1.14+ / Phoenix 1.7 + LiveView 0.20
- **AI**: Anthropic Claude / OpenAI GPT / Google Gemini
- **상태 관리**: GenServer (캠페인당 1 프로세스) + JSON 파일 영속성
- **프론트엔드**: Phoenix LiveView (서버 렌더링 + WebSocket), 커스텀 다크 판타지 테마

## 빠른 시작

```bash
mix deps.get
mix phx.server   # http://localhost:4000
```

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `ANTHROPIC_API_KEY` | — | Claude API 키 (기본 AI 제공자) |
| `OPENAI_API_KEY` | — | GPT API 키 |
| `GOOGLE_API_KEY` | — | Gemini API 키 |
| `AI_MODEL` | `claude-sonnet-4-6` | 사용할 모델 ID |
| `AUTH_PASSWORD` | — | 로그인 패스워드 |
| `DATA_DIR` | `data` | 캠페인 저장 경로 |
| `SECRET_KEY_BASE` | — | Phoenix 세션 시크릿 (프로덕션 필수) |
| `DND_SRD_ONLY` | `true` | `false`로 설정 시 PHB 2024 데이터도 함께 로드 |
| `DND_EXTRA_DATA_DIR` | — | 외부 추가 D&D 데이터 디렉토리 경로 (선택) |
| `DATA_GITHUB_TOKEN` | — | GitHub private 레포 접근 토큰 (미설정 시 로컬 번들 사용) |

## D&D 데이터 로드 방식

앱 기동 시 다음 순서로 D&D 규칙 데이터를 로드한다.

```
1. DATA_GITHUB_TOKEN 있음 → GitHub lmh7201/dnd_reference_ko 에서 fetch (전체 데이터)
2. DATA_GITHUB_TOKEN 없음 → 로컬 번들 사용:
   a. priv/data/srd/   — SRD 5.2 데이터 (항상 로드, CC BY 4.0)
   b. priv/data/phb/   — PHB 2024 데이터 (DND_SRD_ONLY=false 시 병합)
   c. DND_EXTRA_DATA_DIR — 외부 경로 지정 시 추가 병합
```

### 외부 데이터 경로 (`DND_EXTRA_DATA_DIR`)

커스텀 룰북 데이터를 추가하려면 `priv/data/srd/`와 동일한 파일명 구조로 디렉토리를 준비하고 경로를 지정한다.

```bash
# 예시: /opt/my_dnd_data/spells.json, classes.json 등을 준비 후
DND_EXTRA_DATA_DIR=/opt/my_dnd_data mix phx.server
```

지원 파일명: `classes.json`, `races.json`, `backgrounds.json`, `feats.json`, `spells.json`, `classFeatures.json`, `subclasses.json`, `subclassFeatures.json`, `weapons.json`, `armor.json`, `adventuringGear.json`, `tools.json`, `monsters.json`

### 번들 데이터 재생성

`dnd_reference_ko` 데이터가 업데이트된 경우 아래 Mix task로 번들을 다시 생성한다.

```bash
mix dnd.export_srd --source /path/to/dnd_reference_ko/dnd_korean/dnd-reference/src/data
```

실행 결과:
- `priv/data/srd/` — `source: "SRD 5.2"` 항목만 추출
- `priv/data/phb/` — `source: "PHB 2024"` 항목만 추출 (혼재 파일)

## 개발 명령어

```bash
mix deps.get          # 의존성 설치
mix phx.server        # 개발 서버 (localhost:4000)
mix test              # 전체 테스트
mix dnd.export_srd --source <경로>   # D&D 데이터 번들 재생성
```

## 프로젝트 구조

```
lib/trpg_master/
  campaign/
    state.ex          # 캠페인 상태 구조체
    server.ex         # GenServer (캠페인 프로세스)
    manager.ex        # 캠페인 CRUD
    persistence.ex    # 파일 I/O (JSON 저장/로드)
  rules/
    character_data.ex # D&D 데이터 로더 (ETS 캐시)
  ai/
    client.ex         # AI API 래퍼
    prompt_builder.ex # 시스템 프롬프트 생성
    tools.ex          # AI 도구 정의

lib/trpg_master_web/
  live/
    campaign_live.ex          # 메인 채팅/게임 화면
    character_create_live.ex  # 캐릭터 생성 7단계 위저드
    lobby_live.ex             # 캠페인 목록
    history_live.ex           # 세션 로그

lib/mix/tasks/dnd/
  export_srd.ex       # D&D 데이터 SRD/PHB 분리 번들링 task

priv/data/
  srd/                # SRD 5.2 번들 데이터 (CC BY 4.0, git 포함)
  phb/                # PHB 2024 번들 데이터 (git 포함)
```
