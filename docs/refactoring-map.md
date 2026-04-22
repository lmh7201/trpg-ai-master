# 리팩토링 구조 가이드

이 문서는 최근 리팩토링으로 분리된 모듈들을 맥락별로 정리한 안내서다.

- 대상 범위: 최근 책임 분리로 경계가 선명해진 모듈
- 설명 기준: `public function`, `LiveView callback`, `HEEx component entry point`
- 제외 범위: 단순 private helper와 기존 도메인 내부 구현 세부사항

## 리팩토링의 공통 원칙

이번 리팩토링은 한 번에 구조를 갈아엎기보다, 기존 공개 API를 유지한 채 내부 책임을 점진적으로 분리하는 방향으로 진행했다.

1. 큰 진입점은 얇게 유지한다.
   `LiveView`, 파사드 컴포넌트, provider 진입 모듈은 “받아서 분기하고 위임하는 역할”에 집중한다.
2. 상태 전이와 화면 렌더링을 분리한다.
   이벤트 해석, 서버 호출, assign 조립, 실제 UI 렌더링을 각각 다른 모듈로 나눴다.
3. 프롬프트와 AI provider 계층은 조립 로직과 실행 로직을 분리한다.
   request body 생성, response 해석, tool loop, 재시도 정책을 독립 모듈로 쪼갰다.
4. 도메인 갱신 로직은 “일반 변경”과 “계산/재계산”을 분리한다.
   예를 들어 캐릭터 업데이트에서 일반 필드 변경, 레벨업 계산, 선택 적용을 따로 관리한다.
5. 테스트가 어려운 모듈은 순수 helper로 분리한다.
   UI step helper, presenter, prompt section builder, retry policy처럼 테스트하기 쉬운 단위가 많이 생겼다.

## 읽는 법

각 모듈에는 아래 정보를 같이 적었다.

- 파일: 실제 구현 위치
- 역할: 이 모듈이 지금 책임지는 범위
- 대표 호출 흐름: 상위 진입점과 하위 helper의 관계
- 함수 목록: 외부에서 호출하는 함수와 그 책임

## 1. 캠페인 화면 런타임

리팩토링 전에는 `CampaignLive`가 서버 호출, assign 조립, 메시지 변환, 화면 렌더링을 한곳에서 많이 처리했다. 지금은 LiveView를 transport 계층으로 두고, 서버 상호작용은 session helper, 화면용 데이터 조립은 presenter 계층으로 분리했다.

대표 호출 흐름:

```text
CampaignLive
  -> CampaignSession
    -> Campaign.Server / Campaign.Manager
    -> CampaignFlow
  -> CampaignPresenter
    -> CampaignPresenter.State
    -> CampaignPresenter.Messages
    -> CampaignPresenter.ToolMessages
```

### `TrpgMasterWeb.CampaignLive`

- 파일: [lib/trpg_master_web/live/campaign_live.ex](../lib/trpg_master_web/live/campaign_live.ex)
- 역할: 캠페인 화면의 LiveView 진입점. 이벤트를 받고, 필요한 helper를 호출하고, 최종 render를 호출한다.

| 함수 | 역할 |
| --- | --- |
| `mount/3` | `CampaignSession.mount_assigns/2`를 호출해 캠페인 시작과 초기 assign 준비를 맡긴다. |
| `handle_event("send_message", ...)` | 플레이어 입력을 `CampaignFlow.submit_message/2`로 검증하고, AI 호출을 queue에 넣는다. |
| `handle_event("retry_last", ...)` | 마지막 플레이어 메시지를 재실행하는 흐름을 시작한다. |
| `handle_event("toggle_mode", ...)` | 화면 모드를 바꾸고 `Campaign.Server.set_mode/2`로 서버 상태를 동기화한다. |
| `handle_event("toggle_model_selector", ...)` | 모델 선택 모달 열기/닫기 UI 상태만 토글한다. |
| `handle_event("select_model", ...)` | 모델 선택 검증은 `CampaignFlow`에 맡기고, 성공 시 서버 모델도 갱신한다. |
| `handle_event("end_session", ...)` | 세션 종료를 즉시 실행하지 않고 `:do_end_session` 메시지로 비동기 흐름을 연다. |
| `handle_info({:call_ai, message}, ...)` | 실제 AI 호출 결과를 받아 적 턴 재생 여부까지 분기한다. |
| `handle_info({:display_enemy_turns, ...}, ...)` | 적 턴 결과를 순차적으로 화면에 반영한다. |
| `handle_info(:do_end_session, ...)` | 세션 종료 결과를 assign으로 반영한다. |
| `render/1` | 헤더, 모델 선택 모달, 캐릭터 시트, 채팅 피드, 상태바, 입력창을 조립한다. |

### `TrpgMasterWeb.CampaignSession`

- 파일: [lib/trpg_master_web/live/campaign_session.ex](../lib/trpg_master_web/live/campaign_session.ex)
- 역할: `CampaignLive`가 직접 하던 서버 I/O를 분리한 helper. “캠페인 서버와 이야기한 뒤 화면 업데이트 형식으로 반환”하는 책임을 가진다.

| 함수 | 역할 |
| --- | --- |
| `mount_assigns/2` | 캠페인 시작 보장 후 state를 읽고 `CampaignPresenter.mount_assigns/2`로 초기 화면 assign을 만든다. |
| `call_ai/3` | `Server.player_action/2` 결과를 읽고, 플레이어 응답만 있는지 적 턴까지 이어지는지 구분해서 `CampaignFlow.apply_player_action_result/3`에 넘긴다. |
| `display_enemy_turn/4` | 적 턴 결과를 그릴 때마다 최신 state를 다시 읽어 `CampaignFlow.apply_enemy_turn/4`에 전달한다. |
| `end_session/2` | `Server.end_session/1` 결과를 받아 `CampaignFlow.apply_end_session_result/2` 형식으로 변환한다. |

### `TrpgMasterWeb.CampaignPresenter`

- 파일: [lib/trpg_master_web/live/campaign_presenter.ex](../lib/trpg_master_web/live/campaign_presenter.ex)
- 역할: 캠페인 화면용 assign 조립 파사드. 내부 구현을 `State`, `ToolMessages`로 위임한다.

| 함수 | 역할 |
| --- | --- |
| `mount_assigns/2` | 초기 화면에 필요한 전체 assign을 만든다. |
| `state_assigns/1` | state에서 바로 파생되는 assign만 다시 계산한다. |
| `append_tool_messages/3` | tool result를 화면용 메시지에 추가한다. |

### `TrpgMasterWeb.CampaignPresenter.State`

- 파일: [lib/trpg_master_web/live/campaign_presenter/state.ex](../lib/trpg_master_web/live/campaign_presenter/state.ex)
- 역할: 캠페인 state를 LiveView assign으로 변환하는 모듈.

| 함수 | 역할 |
| --- | --- |
| `mount_assigns/2` | 캠페인 이름, 메시지 히스토리, 모델 선택 상태, 로딩 플래그 등 초기 화면 전체 assign을 만든다. |
| `state_assigns/1` | 위치, phase, 현재 캐릭터, 파티 목록, 전투 상태, 모드처럼 state 기반 필드만 계산한다. |

### `TrpgMasterWeb.CampaignPresenter.Messages`

- 파일: [lib/trpg_master_web/live/campaign_presenter/messages.ex](../lib/trpg_master_web/live/campaign_presenter/messages.ex)
- 역할: exploration/combat history를 실제 채팅 피드 메시지 구조로 정규화한다.

| 함수 | 역할 |
| --- | --- |
| `display_messages/1` | `user/assistant` 히스토리를 `:player`, `:dm` 메시지로 변환하고, synthetic user 메시지는 숨긴다. |

### `TrpgMasterWeb.CampaignPresenter.ToolMessages`

- 파일: [lib/trpg_master_web/live/campaign_presenter/tool_messages.ex](../lib/trpg_master_web/live/campaign_presenter/tool_messages.ex)
- 역할: tool execution 결과를 UI에 붙일 보조 메시지로 바꾼다.

| 함수 | 역할 |
| --- | --- |
| `append/3` | 주사위 결과는 `:dice` 메시지로, 상태 변경 도구 결과는 debug 모드에서 `:tool_narration` 메시지로 붙인다. |

추가 메모:

- `register_npc`, `update_quest`, `set_location`, `start_combat`, `end_combat`, `update_character`, `write_journal`는 각각 private narrative builder가 따로 있어서 tool별 설명 포맷이 분리돼 있다.
- adventure 모드에서는 숨겨진 주사위 결과나 tool narration을 최대한 화면에 드러내지 않고, debug 모드에서는 내부 상태 변화를 더 노출한다.

## 2. 캐릭터 생성 런타임

리팩토링 전에는 `CharacterCreateLive`가 이벤트 해석, 룰 데이터 조회, 위저드 상태 변경, 저장까지 많이 직접 담당했다. 지금은 LiveView는 얇게 유지하고, 이벤트 해석은 `Actions`, 세션/서버 I/O는 `Session`, 순수 상태 전이는 `Flow`로 분리했다.

대표 호출 흐름:

```text
CharacterCreateLive
  -> CharacterCreateActions
    -> CharacterCreateFlow
    -> CharacterCreateSession
      -> Rules.CharacterData
      -> Campaign.Server
```

### `TrpgMasterWeb.CharacterCreateLive`

- 파일: [lib/trpg_master_web/live/character_create_live.ex](../lib/trpg_master_web/live/character_create_live.ex)
- 역할: 캐릭터 생성 위저드의 진입점. 현재는 이벤트 전달과 step별 본문 선택만 한다.

| 함수 | 역할 |
| --- | --- |
| `mount/3` | `CharacterCreateSession.mount_assigns/2`를 호출해 초기 assign이나 redirect 경로를 받는다. |
| `handle_event/3` | 모든 이벤트를 `CharacterCreateActions.handle/4`로 보낸 뒤 `assign`, `navigate`, `ignore`를 적용한다. |
| `render/1` | 현재 `@step`에 맞는 단계 컴포넌트만 선택하고, 공통 레이아웃은 `wizard_shell/1`에 맡긴다. |

### `TrpgMasterWeb.CharacterCreateActions`

- 파일: [lib/trpg_master_web/live/character_create_actions.ex](../lib/trpg_master_web/live/character_create_actions.ex)
- 역할: LiveView 이벤트 이름을 실제 도메인 동작으로 매핑하는 라우터.

| 함수 | 역할 |
| --- | --- |
| `handle("select_class", ...)` | 클래스 선택 이벤트를 `CharacterCreateSession.select_class/2`로 위임한다. |
| `handle("toggle_class_skill", ...)` | 클래스 기술 숙련 토글을 `CharacterCreateFlow.toggle_class_skill/2`로 위임한다. |
| `handle("select_race", ...)` | 종족 선택을 session helper에 맡긴다. |
| `handle("select_background", ...)` | 배경 선택을 session helper에 맡긴다. |
| `handle("set_bg_ability", ...)` | 배경 능력치 보너스 선택 상태를 갱신한다. |
| `handle("set_ability_method", ...)` | 능력치 산정 방식 선택을 반영한다. |
| `handle("assign_ability", ...)` | 능력치 수동 배분 입력을 검증 후 반영한다. |
| `handle("clear_ability", ...)` | 특정 능력치에 배치한 점수를 해제한다. |
| `handle("roll_abilities", ...)` | 주사위 굴림으로 능력치 배열을 생성한다. |
| `handle("set_class_equip", ...)` | 클래스 장비 선택을 반영한다. |
| `handle("set_bg_equip", ...)` | 배경 장비 선택을 반영한다. |
| `handle("toggle_cantrip", ...)` | 소마법 선택 목록을 토글한다. |
| `handle("toggle_spell", ...)` | 1레벨 주문 선택 목록을 토글한다. |
| `handle("set_name", ...)` | 이름 입력을 반영한다. |
| `handle("set_alignment", ...)` | 성향 선택을 반영한다. |
| `handle("set_appearance", ...)` | 외모 텍스트를 반영한다. |
| `handle("set_backstory", ...)` | 배경 스토리 텍스트를 반영한다. |
| `handle("show_detail", ...)` | 상세 패널을 연다. |
| `handle("close_detail", ...)` | 상세 패널을 닫는다. |
| `handle("next_step", ...)` | 현재 step 검증 후 다음 단계로 이동한다. |
| `handle("prev_step", ...)` | 이전 단계로 이동한다. |
| `handle("finish", ...)` | 최종 캐릭터 생성과 저장을 실행하고, 성공 시 플레이 화면으로 이동한다. |

핵심 포인트:

- 이 모듈 덕분에 `CharacterCreateLive`는 이벤트 이름을 거의 모르게 되었고, 테스트는 “이 이벤트가 어떤 결과 타입을 반환해야 하는가”로 더 쉽게 쓸 수 있다.
- 성향 저장 버그의 흐름도 여기서 더 읽기 쉬워졌다. `set_alignment` 이벤트가 `Flow.set_alignment/1`로 들어가고, 마지막 `finish`에서 같은 assign이 그대로 캐릭터 빌드로 이어진다.

### `TrpgMasterWeb.CharacterCreateSession`

- 파일: [lib/trpg_master_web/live/character_create_session.ex](../lib/trpg_master_web/live/character_create_session.ex)
- 역할: 위저드가 사용하는 데이터 로드와 최종 저장을 담당한다.

| 함수 | 역할 |
| --- | --- |
| `mount_assigns/2` | 캠페인 서버가 살아 있는지 확인하고, 클래스/종족/배경 데이터를 로드한 뒤 초기 위저드 assign을 만든다. |
| `select_class/2` | 클래스 ID를 실제 클래스 데이터로 lookup해서 `CharacterCreateFlow.select_class/1`에 넘긴다. |
| `select_race/2` | 종족 ID를 실제 종족 데이터로 lookup한다. |
| `select_background/2` | 배경 ID를 실제 배경 데이터로 lookup한다. |
| `finish/2` | `CharacterCreateFlow.finish/1`으로 최종 캐릭터를 만들고 `Campaign.Server.set_character/2`로 저장한다. |

### `TrpgMasterWeb.CharacterCreateFlow`

- 파일: [lib/trpg_master_web/live/character_create_flow.ex](../lib/trpg_master_web/live/character_create_flow.ex)
- 역할: 캐릭터 생성 화면의 순수 상태 전이 규칙을 담당한다.

| 함수 | 역할 |
| --- | --- |
| `mount_assigns/4` | 캐릭터 생성 초기 상태에 캠페인 ID를 합쳐 LiveView assign 형태로 만든다. |
| `select_class/1` | 클래스 선택 시 필요한 기본 업데이트를 만든다. |
| `toggle_class_skill/2` | 선택 가능한 개수 제한 안에서 기술 숙련을 토글한다. |
| `select_race/1` | 종족 선택과 상세 패널 초기화를 처리한다. |
| `select_background/1` | 배경 선택 시 필요한 기본 업데이트를 만든다. |
| `set_bg_ability/3` | 배경 보너스 능력치 선택 규칙을 반영한다. |
| `set_ability_method/1` | 포인트바이/고정값/주사위 굴림 같은 능력치 방식 선택을 반영한다. |
| `assign_ability/3` | 특정 능력치에 점수를 배치한다. |
| `clear_ability/2` | 배치한 점수를 비운다. |
| `roll_abilities/0` | 굴림 결과를 생성한다. |
| `set_class_equip/1` | 클래스 장비 선택값을 저장한다. |
| `set_bg_equip/1` | 배경 장비 선택값을 저장한다. |
| `toggle_cantrip/2` | 소마법 선택 개수 제한을 지키며 토글한다. |
| `toggle_spell/2` | 1레벨 주문 선택 제한을 계산 후 토글한다. |
| `set_name/1` | 이름을 trim해서 저장한다. |
| `set_alignment/1` | 성향을 저장한다. |
| `set_appearance/1` | 외모 메모를 저장한다. |
| `set_backstory/1` | 배경 스토리를 저장한다. |
| `show_detail/2` | 상세 정보 패널 상태를 연다. |
| `close_detail/0` | 상세 정보 패널 상태를 닫는다. |
| `next_step/1` | 현재 step을 검증하고 다음 step에서 필요한 준비 데이터를 만든다. |
| `prev_step/1` | 이전 step으로 되돌린다. |
| `finish/1` | 마지막 검증 후 `Creation.build_character/1`로 실제 캐릭터 구조를 만든다. |

## 3. 캐릭터 생성 UI 컴포넌트

리팩토링 전에는 한 파일 안에서 step별 마크업과 파생 데이터 계산이 길게 섞여 있었다. 지금은 컴포넌트 파사드, 공통 shell, 선택 단계, 진행 단계, 요약 단계로 분리되어 “어느 step을 고치려는지”가 명확하다.

대표 호출 흐름:

```text
CharacterCreateLive.render/1
  -> CharacterCreateComponents
    -> ShellComponents
    -> SelectionComponents
      -> ClassStep / RaceStep / BackgroundStep
    -> ProgressionComponents
      -> AbilitiesStep / EquipmentStep / SpellsStep
    -> SummaryComponents
      -> Preview
```

### `TrpgMasterWeb.CharacterCreateComponents`

- 파일: [lib/trpg_master_web/components/character_create_components.ex](../lib/trpg_master_web/components/character_create_components.ex)
- 역할: 캐릭터 생성 관련 공개 컴포넌트 API를 유지하는 파사드.

| 함수 | 역할 |
| --- | --- |
| `wizard_shell/1` | 공통 레이아웃 렌더를 `ShellComponents`에 위임한다. |
| `class_step/1` | 클래스 선택 단계 렌더를 위임한다. |
| `race_step/1` | 종족 선택 단계 렌더를 위임한다. |
| `background_step/1` | 배경 선택 단계 렌더를 위임한다. |
| `abilities_step/1` | 능력치 단계 렌더를 위임한다. |
| `equipment_step/1` | 장비 단계 렌더를 위임한다. |
| `spells_step/1` | 주문 단계 렌더를 위임한다. |
| `summary_step/1` | 요약 단계 렌더를 위임한다. |

### `TrpgMasterWeb.CharacterCreate.ShellComponents`

- 파일: [lib/trpg_master_web/components/character_create/shell_components.ex](../lib/trpg_master_web/components/character_create/shell_components.ex)
- 역할: 위저드 전체의 공통 골격을 담당한다.

| 함수 | 역할 |
| --- | --- |
| `wizard_shell/1` | 헤더, 단계 표시, 에러 배너, 푸터 버튼, 슬롯 기반 본문 영역을 렌더링한다. |

### `TrpgMasterWeb.CharacterCreate.SelectionComponents`

- 파일: [lib/trpg_master_web/components/character_create/selection_components.ex](../lib/trpg_master_web/components/character_create/selection_components.ex)
- 역할: 선택 단계 컴포넌트 파사드.

| 함수 | 역할 |
| --- | --- |
| `class_step/1` | 클래스 선택 step을 `ClassStep`에 위임한다. |
| `race_step/1` | 종족 선택 step을 `RaceStep`에 위임한다. |
| `background_step/1` | 배경 선택 step을 `BackgroundStep`에 위임한다. |

### `TrpgMasterWeb.CharacterCreate.SelectionComponents.ClassStep`

- 파일: [lib/trpg_master_web/components/character_create/selection_components/class_step.ex](../lib/trpg_master_web/components/character_create/selection_components/class_step.ex)
- 역할: 클래스 선택 화면 전용 렌더러.

| 함수 | 역할 |
| --- | --- |
| `class_step/1` | 클래스 카드, 클래스 상세 정보, 시작 장비, 클래스 숙련 선택 UI를 렌더링한다. |

### `TrpgMasterWeb.CharacterCreate.SelectionComponents.RaceStep`

- 파일: [lib/trpg_master_web/components/character_create/selection_components/race_step.ex](../lib/trpg_master_web/components/character_create/selection_components/race_step.ex)
- 역할: 종족 선택 화면 전용 렌더러.

| 함수 | 역할 |
| --- | --- |
| `race_step/1` | 종족 카드 목록과 선택 종족의 상세 trait 정보를 렌더링한다. |

### `TrpgMasterWeb.CharacterCreate.SelectionComponents.BackgroundStep`

- 파일: [lib/trpg_master_web/components/character_create/selection_components/background_step.ex](../lib/trpg_master_web/components/character_create/selection_components/background_step.ex)
- 역할: 배경 선택 화면 전용 렌더러.

| 함수 | 역할 |
| --- | --- |
| `background_step/1` | 배경 카드, 기술/도구/feat 정보, 능력치 보너스 선택, 배경 장비 선택 UI를 렌더링한다. |

### `TrpgMasterWeb.CharacterCreate.ProgressionComponents`

- 파일: [lib/trpg_master_web/components/character_create/progression_components.ex](../lib/trpg_master_web/components/character_create/progression_components.ex)
- 역할: 진행 단계 컴포넌트 파사드.

| 함수 | 역할 |
| --- | --- |
| `abilities_step/1` | 능력치 단계 렌더를 `AbilitiesStep`에 위임한다. |
| `equipment_step/1` | 장비 단계 렌더를 `EquipmentStep`에 위임한다. |
| `spells_step/1` | 주문 단계 렌더를 `SpellsStep`에 위임한다. |

### `TrpgMasterWeb.CharacterCreate.ProgressionComponents.AbilitiesStep`

- 파일: [lib/trpg_master_web/components/character_create/progression_components/abilities_step.ex](../lib/trpg_master_web/components/character_create/progression_components/abilities_step.ex)
- 역할: 능력치 단계 전용 렌더러.

| 함수 | 역할 |
| --- | --- |
| `abilities_step/1` | 능력치 산정 방식 선택, 굴림 결과 표시, 능력치 카드, 배경 보너스 반영 UI를 렌더링한다. |

### `TrpgMasterWeb.CharacterCreate.ProgressionComponents.EquipmentStep`

- 파일: [lib/trpg_master_web/components/character_create/progression_components/equipment_step.ex](../lib/trpg_master_web/components/character_create/progression_components/equipment_step.ex)
- 역할: 장비 선택 단계 전용 렌더러.

| 함수 | 역할 |
| --- | --- |
| `equipment_step/1` | 클래스 장비와 배경 장비 선택 UI를 렌더링한다. |

### `TrpgMasterWeb.CharacterCreate.ProgressionComponents.SpellsStep`

- 파일: [lib/trpg_master_web/components/character_create/progression_components/spells_step.ex](../lib/trpg_master_web/components/character_create/progression_components/spells_step.ex)
- 역할: 주문 선택 단계 전용 렌더러.

| 함수 | 역할 |
| --- | --- |
| `spells_step/1` | 시전 클래스 여부를 분기하고, 소마법/1레벨 주문 선택 UI를 렌더링한다. |

### `TrpgMasterWeb.CharacterCreate.SummaryComponents`

- 파일: [lib/trpg_master_web/components/character_create/summary_components.ex](../lib/trpg_master_web/components/character_create/summary_components.ex)
- 역할: 최종 요약 단계 렌더러.

| 함수 | 역할 |
| --- | --- |
| `summary_step/1` | 이름, 성향, 외모, 배경 스토리 입력과 최종 시트 미리보기를 렌더링한다. |

추가 메모:

- 이 모듈은 이제 파생 데이터 계산을 직접 하지 않고 `Preview.build/1` 결과를 assign에 합친 뒤 렌더만 수행한다.

### `TrpgMasterWeb.CharacterCreate.SummaryComponents.Preview`

- 파일: [lib/trpg_master_web/components/character_create/summary_components/preview.ex](../lib/trpg_master_web/components/character_create/summary_components/preview.ex)
- 역할: 요약 화면에서 보여 줄 파생 데이터를 계산한다.

| 함수 | 역할 |
| --- | --- |
| `build/1` | 미리보기 캐릭터, 최종 능력치, 표시용 이름/라인, 이동속도, 기술 목록, 주문 이름 목록을 계산한다. |

## 4. 공통 게임 UI 컴포넌트

캠페인 화면에서 쓰는 공통 컴포넌트도 큰 파일 하나에서 헤더, 상태바, 캐릭터 시트 모달을 모두 처리하던 구조에서, 영역별 하위 모듈로 분리했다.

대표 호출 흐름:

```text
GameComponents
  -> HeaderComponents
  -> StatusComponents
  -> CharacterSheetComponents
    -> CharacterSheetSections
```

### `TrpgMasterWeb.GameComponents`

- 파일: [lib/trpg_master_web/components/game_components.ex](../lib/trpg_master_web/components/game_components.ex)
- 역할: 캠페인 화면 공통 컴포넌트의 공개 API 파사드.

| 함수 | 역할 |
| --- | --- |
| `campaign_header/1` | 헤더 렌더를 `HeaderComponents`에 위임한다. |
| `model_selector_modal/1` | 모델 선택 모달 렌더를 위임한다. |
| `campaign_status_bars/1` | 파티 상태바 렌더를 `StatusComponents`에 위임한다. |
| `status_bar/1` | 개별 상태바 렌더를 위임한다. |
| `character_sheet_modal/1` | 캐릭터 시트 모달 렌더를 `CharacterSheetComponents`에 위임한다. |

### `TrpgMasterWeb.Game.HeaderComponents`

- 파일: [lib/trpg_master_web/components/game/header_components.ex](../lib/trpg_master_web/components/game/header_components.ex)
- 역할: 캠페인 상단 헤더와 모델 선택 모달 UI를 담당한다.

| 함수 | 역할 |
| --- | --- |
| `campaign_header/1` | 캠페인명, phase, 현재 모델, 모드, 버튼류를 포함한 상단 헤더를 렌더링한다. |
| `model_selector_modal/1` | 사용 가능한 모델 목록과 현재 모델 상태를 보여 주는 모달을 렌더링한다. |

### `TrpgMasterWeb.Game.StatusComponents`

- 파일: [lib/trpg_master_web/components/game/status_components.ex](../lib/trpg_master_web/components/game/status_components.ex)
- 역할: 캐릭터/파티 상태바 렌더링을 담당한다.

| 함수 | 역할 |
| --- | --- |
| `campaign_status_bars/1` | 파티 전체 상태, 위치, phase, 전투 상태를 화면 하단 요약으로 렌더링한다. |
| `status_bar/1` | 단일 캐릭터의 HP, AC, 상태를 렌더링한다. |

### `TrpgMasterWeb.Game.CharacterSheetComponents`

- 파일: [lib/trpg_master_web/components/game/character_sheet_components.ex](../lib/trpg_master_web/components/game/character_sheet_components.ex)
- 역할: 캐릭터 시트 모달의 shell과 섹션 조립만 담당한다.

| 함수 | 역할 |
| --- | --- |
| `character_sheet_modal/1` | 모달의 바깥 구조를 만들고, 실제 각 섹션 렌더는 `CharacterSheetSections`에 위임한다. |

### `TrpgMasterWeb.Game.CharacterSheetSections`

- 파일: [lib/trpg_master_web/components/game/character_sheet_sections.ex](../lib/trpg_master_web/components/game/character_sheet_sections.ex)
- 역할: 캐릭터 시트 모달의 세부 섹션 렌더러 모음.

| 함수 | 역할 |
| --- | --- |
| `basic_info_section/1` | 종족, 서브클래스, 배경, 성향 같은 기본 프로필을 렌더링한다. |
| `prose_section/1` | 외모, 배경 서사처럼 제목과 본문 한 쌍의 텍스트 영역을 렌더링한다. |
| `abilities_section/1` | STR/DEX/CON/INT/WIS/CHA와 수정치를 그리드로 렌더링한다. |
| `combat_section/1` | HP, AC, 이동속도 등 전투 핵심 스탯을 렌더링한다. |
| `spell_slots_section/1` | 주문 슬롯 총량, 사용량, 남은 수량을 렌더링한다. |
| `known_spells_section/1` | 알고 있는 주문을 소마법/레벨별 그룹으로 묶어 렌더링한다. |
| `inventory_section/1` | 소지품 목록을 렌더링한다. |
| `grouped_features_section/1` | 레벨별 class feature 묶음을 렌더링한다. |
| `badge_list_section/1` | 피트, 상태이상, 태그성 리스트를 badge 목록으로 렌더링한다. |

## 5. 프롬프트 조립, 요약, 도구 정의

AI 계층은 크게 세 덩어리로 정리됐다.

- 프롬프트 조립: 무엇을 시스템 프롬프트에 넣을지
- 요약 생성: 긴 히스토리를 어떻게 압축할지
- 도구 정의: 모델에게 어떤 도구를 어떤 스키마로 노출할지

대표 호출 흐름:

```text
PromptBuilder
  -> Messages
  -> Sections
    -> Context
    -> Instructions

Summarizer
  -> Request
  -> Prompts
  -> ModelPolicy
  -> Update

ToolDefinitions
  -> Phase / State
    -> leaf schema modules
```

### `TrpgMaster.AI.PromptBuilder`

- 파일: [lib/trpg_master/ai/prompt_builder.ex](../lib/trpg_master/ai/prompt_builder.ex)
- 역할: 시스템 프롬프트 전체를 조립하는 진입점.

| 함수 | 역할 |
| --- | --- |
| `build/2` | 기본 시스템 프롬프트, 캠페인 컨텍스트, 요약 섹션, 전투 지시문, 모드 지시문을 합쳐 최종 시스템 프롬프트를 만든다. |
| `system_prompt/0` | `priv/prompts/system_dm.md`를 읽고, 없으면 기본 프롬프트 문자열을 돌려준다. |
| `build_messages/1` | 토큰 예산 안에 맞게 대화 히스토리를 자른다. |
| `build_messages_with_summary/3` | 최근 메시지와 context summary를 함께 사용해 슬라이딩 윈도우를 구성한다. |
| `build_turn_messages/2` | state 기반 turn message 구성을 만든다. |
| `build_turn_messages/3` | 옵션을 포함한 turn message 구성을 만든다. |

### `TrpgMaster.AI.PromptBuilder.Messages`

- 파일: [lib/trpg_master/ai/prompt_builder/messages.ex](../lib/trpg_master/ai/prompt_builder/messages.ex)
- 역할: conversation history를 어떤 규칙으로 자를지 담당한다.

| 함수 | 역할 |
| --- | --- |
| `build_messages/1` | 히스토리를 최근 메시지 중심으로 예산 내에서 유지한다. |
| `build_messages_with_summary/3` | 오래된 부분은 요약으로 대체하고 최근 대화는 실제 메시지로 유지한다. |
| `build_turn_messages/3` | state와 현재 메시지를 합쳐 턴 단위 메시지 배열을 만든다. |

### `TrpgMaster.AI.PromptBuilder.Sections`

- 파일: [lib/trpg_master/ai/prompt_builder/sections.ex](../lib/trpg_master/ai/prompt_builder/sections.ex)
- 역할: 프롬프트 섹션 조립 파사드.

| 함수 | 역할 |
| --- | --- |
| `build_summary_section/1` | 컨텍스트 요약 섹션 렌더를 `Instructions`에 위임한다. |
| `build_combat_summary_section/1` | 전투 히스토리 요약 섹션 렌더를 위임한다. |
| `build_post_combat_section/1` | 전투 종료 요약 섹션 렌더를 위임한다. |
| `build_combat_phase_instruction/1` | 현재 전투 phase용 지시문 렌더를 위임한다. |
| `state_tools_instruction/0` | 상태 변경 도구 사용 규칙 지시문을 돌려준다. |
| `mode_instruction/1` | adventure/debug 모드별 지시문을 돌려준다. |
| `build_campaign_context/1` | 캠페인 state를 실제 컨텍스트 텍스트로 조립한다. |

### `TrpgMaster.AI.PromptBuilder.Sections.Context`

- 파일: [lib/trpg_master/ai/prompt_builder/sections/context.ex](../lib/trpg_master/ai/prompt_builder/sections/context.ex)
- 역할: 캠페인 state를 텍스트 컨텍스트로 변환한다.

| 함수 | 역할 |
| --- | --- |
| `build_campaign_context/1` | 캠페인 메타, 캐릭터, 위치, NPC, 퀘스트, 전투 상태를 하나의 컨텍스트 텍스트로 만든다. |

### `TrpgMaster.AI.PromptBuilder.Sections.Instructions`

- 파일: [lib/trpg_master/ai/prompt_builder/sections/instructions.ex](../lib/trpg_master/ai/prompt_builder/sections/instructions.ex)
- 역할: 프롬프트 안에 들어가는 지시문 템플릿을 담당한다.

| 함수 | 역할 |
| --- | --- |
| `build_summary_section/1` | 일반 컨텍스트 요약을 프롬프트 섹션으로 변환한다. |
| `build_combat_summary_section/1` | 전투 요약을 프롬프트 섹션으로 변환한다. |
| `build_post_combat_section/1` | 전투 종료 후 남겨 둔 요약을 섹션으로 변환한다. |
| `build_combat_phase_instruction/1` | 플레이어 턴, 적 턴, 라운드 요약 등 현재 전투 phase에 맞는 지시문을 만든다. |
| `state_tools_instruction/0` | 상태 변경 도구 사용 규칙을 정리한 지시문을 만든다. |
| `mode_instruction/1` | adventure/debug 모드별 DM 스타일 지시문을 만든다. |

### `TrpgMaster.Campaign.Summarizer`

- 파일: [lib/trpg_master/campaign/summarizer.ex](../lib/trpg_master/campaign/summarizer.ex)
- 역할: 요약 생성 전체 오케스트레이터.

| 함수 | 역할 |
| --- | --- |
| `generate_session_summary/1` | 세션 종료 시 전체 세션 요약을 생성한다. |
| `generate_context_summary/1` | exploration 히스토리에서 오래된 부분을 context summary로 압축한다. |
| `generate_combat_history_summary/1` | 전투 중 지난 라운드 히스토리를 요약한다. |
| `generate_post_combat_summary/1` | 전투 종료 후 전체 전투 요약을 생성한다. |
| `update_context_summary/1` | 생성한 context summary를 state에 반영한다. |
| `update_combat_history_summary/1` | 생성한 combat summary를 state에 반영한다. |
| `estimate_session_number/1` | turn count 기반으로 세션 번호를 추정한다. |
| `meaningful_summary?/1` | 요약 텍스트가 비어 있거나 무의미한지 검증한다. |
| `format_combatants_status/1` | 전투 참여자 상태를 문자열로 포맷한다. |
| `summary_model_for/1` | 요약 작업에 쓸 모델 정책을 결정한다. |

### `TrpgMaster.Campaign.Summarizer.Request`

- 파일: [lib/trpg_master/campaign/summarizer/request.ex](../lib/trpg_master/campaign/summarizer/request.ex)
- 역할: 요약 종류별 request spec 생성기.

| 함수 | 역할 |
| --- | --- |
| `session/1` | 세션 요약용 시스템 프롬프트, 메시지, 모델, 토큰 설정을 만든다. |
| `context/1` | 컨텍스트 요약용 request를 만든다. |
| `combat_history/1` | 전투 히스토리 요약용 request를 만든다. |
| `post_combat/1` | 전투 종료 요약용 request를 만든다. |

### `TrpgMaster.Campaign.Summarizer.Update`

- 파일: [lib/trpg_master/campaign/summarizer/update.ex](../lib/trpg_master/campaign/summarizer/update.ex)
- 역할: 요약 결과를 state에 적용한다.

| 함수 | 역할 |
| --- | --- |
| `context_summary/3` | 요약 생성 결과를 읽어 context summary와 로그를 갱신한다. |
| `combat_history_summary/2` | 전투 히스토리 요약 결과를 state에 반영한다. |

### `TrpgMaster.Campaign.Summarizer.Prompts`

- 파일: [lib/trpg_master/campaign/summarizer/prompts.ex](../lib/trpg_master/campaign/summarizer/prompts.ex)
- 역할: 각 요약 작업이 실제로 모델에 보내는 프롬프트 텍스트를 만든다.

| 함수 | 역할 |
| --- | --- |
| `session_summary_prompt/1` | 세션 전체를 요약하는 프롬프트를 만든다. |
| `context_summary_prompt/2` | 이전 컨텍스트 요약과 최근 AI 메시지를 통합하는 프롬프트를 만든다. |
| `combat_history_summary_prompt/3` | 이전 전투 요약과 최근 전투 히스토리를 합쳐 요약하는 프롬프트를 만든다. |
| `post_combat_summary_prompt/2` | 전투 종료 직후 전체 전투를 요약하는 프롬프트를 만든다. |
| `recent_combined_history/2` | exploration/combat 히스토리에서 최근 메시지를 합쳐 가져온다. |
| `format_combatants_status/1` | 전투 참가자들의 현재 상태를 텍스트로 포맷한다. |

### `TrpgMaster.Campaign.Summarizer.Text`

- 파일: [lib/trpg_master/campaign/summarizer/text.ex](../lib/trpg_master/campaign/summarizer/text.ex)
- 역할: 요약 텍스트의 유효성을 판별한다.

| 함수 | 역할 |
| --- | --- |
| `meaningful_summary?/1` | 빈 문자열, placeholder, 무의미한 응답을 걸러낸다. |

### `TrpgMaster.Campaign.Summarizer.ModelPolicy`

- 파일: [lib/trpg_master/campaign/summarizer/model_policy.ex](../lib/trpg_master/campaign/summarizer/model_policy.ex)
- 역할: 요약용 모델 선택 규칙을 분리한다.

| 함수 | 역할 |
| --- | --- |
| `summary_model_for/1` | 현재 모델 ID를 바탕으로 요약에 적합한 모델을 반환한다. |

### `TrpgMaster.AI.ToolDefinitions`

- 파일: [lib/trpg_master/ai/tool_definitions.ex](../lib/trpg_master/ai/tool_definitions.ex)
- 역할: 모델에 노출할 도구 정의의 파사드.

| 함수 | 역할 |
| --- | --- |
| `definitions/1` | phase별 도구 세트를 반환한다. |
| `state_tool_definitions/0` | 상태 변경용 도구 세트를 반환한다. |

### `TrpgMaster.AI.ToolDefinitions.Phase`

- 파일: [lib/trpg_master/ai/tool_definitions/phase.ex](../lib/trpg_master/ai/tool_definitions/phase.ex)
- 역할: 탐험/전투 phase에 따라 필요한 도구 묶음을 조합한다.

| 함수 | 역할 |
| --- | --- |
| `definitions(:combat)` | 전투 phase용 도구 조합을 반환한다. |
| `definitions(_phase)` | 기본 탐험 phase용 도구 조합을 반환한다. |

### `TrpgMaster.AI.ToolDefinitions.Phase.Dice`

- 파일: [lib/trpg_master/ai/tool_definitions/phase/dice.ex](../lib/trpg_master/ai/tool_definitions/phase/dice.ex)
- 역할: 주사위 굴림 도구 스키마 정의.

| 함수 | 역할 |
| --- | --- |
| `roll_dice/0` | dice tool의 JSON schema를 반환한다. |

### `TrpgMaster.AI.ToolDefinitions.Phase.Lookup`

- 파일: [lib/trpg_master/ai/tool_definitions/phase/lookup.ex](../lib/trpg_master/ai/tool_definitions/phase/lookup.ex)
- 역할: 룰/몬스터/아이템 lookup 도구 스키마 정의.

| 함수 | 역할 |
| --- | --- |
| `lookup_spell/0` | 주문 조회 도구 스키마를 반환한다. |
| `lookup_monster/0` | 몬스터 단건 조회 도구 스키마를 반환한다. |
| `search_monsters/0` | 몬스터 검색 도구 스키마를 반환한다. |
| `lookup_class/0` | 클래스 조회 도구 스키마를 반환한다. |
| `lookup_item/0` | 아이템 조회 도구 스키마를 반환한다. |
| `lookup_dc/0` | 난이도 가이드 조회 도구 스키마를 반환한다. |
| `lookup_rule/0` | 규칙 문서 조회 도구 스키마를 반환한다. |

### `TrpgMaster.AI.ToolDefinitions.Phase.Oracle`

- 파일: [lib/trpg_master/ai/tool_definitions/phase/oracle.ex](../lib/trpg_master/ai/tool_definitions/phase/oracle.ex)
- 역할: 오라클/랜덤 테이블 계열 도구 스키마 정의.

| 함수 | 역할 |
| --- | --- |
| `consult/0` | 질문형 oracle 도구 스키마를 반환한다. |
| `list/0` | 목록형 oracle 도구 스키마를 반환한다. |

### `TrpgMaster.AI.ToolDefinitions.Phase.Progression`

- 파일: [lib/trpg_master/ai/tool_definitions/phase/progression.ex](../lib/trpg_master/ai/tool_definitions/phase/progression.ex)
- 역할: 진행/성장 도구 스키마 정의.

| 함수 | 역할 |
| --- | --- |
| `level_up/0` | 레벨업 도구 스키마를 반환한다. |

### `TrpgMaster.AI.ToolDefinitions.State`

- 파일: [lib/trpg_master/ai/tool_definitions/state.ex](../lib/trpg_master/ai/tool_definitions/state.ex)
- 역할: 상태 변경 도구 조합 파사드.

| 함수 | 역할 |
| --- | --- |
| `state_tool_definitions/0` | character, combat, world 카테고리의 상태 변경 도구를 합쳐 반환한다. |

### `TrpgMaster.AI.ToolDefinitions.State.Character`

- 파일: [lib/trpg_master/ai/tool_definitions/state/character.ex](../lib/trpg_master/ai/tool_definitions/state/character.ex)
- 역할: 캐릭터 상태 조회/수정 도구 스키마 정의.

| 함수 | 역할 |
| --- | --- |
| `get_info/0` | 캐릭터 정보 조회 도구 스키마를 반환한다. |
| `update/0` | 캐릭터 수정 도구 스키마를 반환한다. |

### `TrpgMaster.AI.ToolDefinitions.State.Combat`

- 파일: [lib/trpg_master/ai/tool_definitions/state/combat.ex](../lib/trpg_master/ai/tool_definitions/state/combat.ex)
- 역할: 전투 시작/종료 도구 스키마 정의.

| 함수 | 역할 |
| --- | --- |
| `start/0` | 전투 시작 도구 스키마를 반환한다. |
| `finish/0` | 전투 종료 도구 스키마를 반환한다. |

### `TrpgMaster.AI.ToolDefinitions.State.World`

- 파일: [lib/trpg_master/ai/tool_definitions/state/world.ex](../lib/trpg_master/ai/tool_definitions/state/world.ex)
- 역할: 월드 상태 변경 도구 스키마 정의.

| 함수 | 역할 |
| --- | --- |
| `register_npc/0` | NPC 등록 도구 스키마를 반환한다. |
| `update_quest/0` | 퀘스트 상태 갱신 도구 스키마를 반환한다. |
| `set_location/0` | 현재 위치 변경 도구 스키마를 반환한다. |
| `write_journal/0` | 저널 기록 도구 스키마를 반환한다. |
| `read_journal/0` | 저널 조회 도구 스키마를 반환한다. |

## 6. AI Provider 계층

provider 계층은 이번 리팩토링에서 가장 큰 구조 변화가 있었다. 기존에는 provider별 구현 안에 request 생성, HTTP 호출, tool loop, response 해석, 재시도 정책이 함께 섞여 있었다. 지금은 공통 loop를 `StandardChat`으로 끌어올리고, provider별 차이는 request/response adapter와 retry rule로 제한했다.

대표 호출 흐름:

```text
OpenAI / Gemini / Anthropic
  -> Request.build/4
  -> StandardChat.run/1
    -> Http.post_json/4
    -> Response.tool_loop?/1
    -> ToolExecution.run/2
    -> Retry.handle/4
```

### 공통 helper

#### `TrpgMaster.AI.Providers.StandardChat`

- 파일: [lib/trpg_master/ai/providers/standard_chat.ex](../lib/trpg_master/ai/providers/standard_chat.ex)
- 역할: provider 공통 chat loop 실행기.

| 함수 | 역할 |
| --- | --- |
| `run/1` | 초기 request body, context, response module, tool executor, usage collector, retry rules를 받아 공통 tool loop를 실행한다. |

#### `TrpgMaster.AI.Providers.Http`

- 파일: [lib/trpg_master/ai/providers/http.ex](../lib/trpg_master/ai/providers/http.ex)
- 역할: JSON POST와 SSL 옵션을 공통화한다.

| 함수 | 역할 |
| --- | --- |
| `post_json/4` | JSON body를 provider API로 보내고 응답을 decode한다. |
| `ssl_options/0` | SSL/TLS 관련 공통 옵션을 제공한다. |

#### `TrpgMaster.AI.Providers.Retry`

- 파일: [lib/trpg_master/ai/providers/retry.ex](../lib/trpg_master/ai/providers/retry.ex)
- 역할: provider 공통 재시도 정책 실행기.

| 함수 | 역할 |
| --- | --- |
| `handle/4` | 현재 에러와 재시도 횟수를 보고 다음 동작을 `retry` 또는 `error`로 결정한다. |
| `rate_limit_rule/1` | rate limit 재시도 규칙을 만든다. |
| `server_error_rule/2` | 5xx 계열 서버 오류 재시도 규칙을 만든다. |
| `status_rule/3` | 특정 status 코드 또는 코드 목록에 대한 재시도 규칙을 만든다. |

#### `TrpgMaster.AI.Providers.ToolExecution`

- 파일: [lib/trpg_master/ai/providers/tool_execution.ex](../lib/trpg_master/ai/providers/tool_execution.ex)
- 역할: provider별 tool call 형식을 공통 방식으로 실행한다.

| 함수 | 역할 |
| --- | --- |
| `run/2` | raw tool call 목록을 추출 함수와 success/error formatter를 통해 공통 처리한다. |

### `TrpgMaster.AI.Providers.OpenAI`

- 파일: [lib/trpg_master/ai/providers/openai.ex](../lib/trpg_master/ai/providers/openai.ex)
- 역할: OpenAI Chat Completions provider 진입점.

| 함수 | 역할 |
| --- | --- |
| `chat/4` | API 키 확인, request body 생성, 공통 tool loop 실행, 재시도 정책 적용을 한 번에 오케스트레이션한다. |

#### `TrpgMaster.AI.Providers.OpenAI.Request`

- 파일: [lib/trpg_master/ai/providers/openai/request.ex](../lib/trpg_master/ai/providers/openai/request.ex)
- 역할: OpenAI request body 조립기.

| 함수 | 역할 |
| --- | --- |
| `build/4` | system prompt, messages, tools, 옵션을 OpenAI Chat Completions body로 변환한다. |

#### `TrpgMaster.AI.Providers.OpenAI.Response`

- 파일: [lib/trpg_master/ai/providers/openai/response.ex](../lib/trpg_master/ai/providers/openai/response.ex)
- 역할: OpenAI 응답 해석기.

| 함수 | 역할 |
| --- | --- |
| `tool_loop?/1` | 응답이 tool call을 더 요구하는지 판단한다. |
| `tool_calls/1` | tool call 목록을 추출한다. |
| `completion_text/1` | 최종 assistant 텍스트를 추출한다. |
| `append_tool_results/3` | tool 실행 결과를 다음 요청 body에 이어 붙인다. |

### `TrpgMaster.AI.Providers.Gemini`

- 파일: [lib/trpg_master/ai/providers/gemini.ex](../lib/trpg_master/ai/providers/gemini.ex)
- 역할: Google Gemini provider 진입점.

| 함수 | 역할 |
| --- | --- |
| `chat/4` | 모델 이름, API 키, request builder, response adapter를 연결해 공통 tool loop를 실행한다. |

#### `TrpgMaster.AI.Providers.Gemini.Request`

- 파일: [lib/trpg_master/ai/providers/gemini/request.ex](../lib/trpg_master/ai/providers/gemini/request.ex)
- 역할: Gemini용 request body 조립기.

| 함수 | 역할 |
| --- | --- |
| `build/4` | 공통 메시지 구조를 Gemini `generateContent` 형식으로 변환한다. |

#### `TrpgMaster.AI.Providers.Gemini.Response`

- 파일: [lib/trpg_master/ai/providers/gemini/response.ex](../lib/trpg_master/ai/providers/gemini/response.ex)
- 역할: Gemini 응답 해석기.

| 함수 | 역할 |
| --- | --- |
| `tool_loop?/1` | function call이 이어지는 응답인지 판별한다. |
| `tool_calls/1` | function call 목록을 추출한다. |
| `completion_text/1` | 최종 텍스트를 추출한다. |
| `append_tool_results/3` | function response payload를 다음 요청 body에 추가한다. |

### `TrpgMaster.AI.Providers.Anthropic`

- 파일: [lib/trpg_master/ai/providers/anthropic.ex](../lib/trpg_master/ai/providers/anthropic.ex)
- 역할: Claude provider 진입점. 공통 loop를 사용하지만 rate limiter, aggressive trim, prompt caching, tool result truncation이 추가로 붙는다.

| 함수 | 역할 |
| --- | --- |
| `chat/4` | API 키 확인 후 request 생성, rate limit 체크, 공통 tool loop 실행, Anthropic 전용 재시도 규칙을 연결한다. |

추가 메모:

- Anthropic만 `400` 응답 시 공격적 히스토리 트리밍 후 재시도하는 규칙이 따로 있다.
- `tool_result` payload가 너무 길면 잘라서 다음 turn에 넘긴다.

#### `TrpgMaster.AI.Providers.Anthropic.Request`

- 파일: [lib/trpg_master/ai/providers/anthropic/request.ex](../lib/trpg_master/ai/providers/anthropic/request.ex)
- 역할: Claude용 request body 조립기.

| 함수 | 역할 |
| --- | --- |
| `build/4` | system prompt, message history, tool 정의를 Claude messages API 형식으로 조립한다. |

#### `TrpgMaster.AI.Providers.Anthropic.Response`

- 파일: [lib/trpg_master/ai/providers/anthropic/response.ex](../lib/trpg_master/ai/providers/anthropic/response.ex)
- 역할: Claude 응답 해석기.

| 함수 | 역할 |
| --- | --- |
| `tool_loop?/1` | `tool_use` 블록이 더 있는지 판별한다. |
| `tool_calls/1` | `tool_use` 블록 목록을 추출한다. |
| `completion_text/1` | 최종 텍스트 블록을 추출한다. |
| `append_tool_results/3` | `tool_result` 블록을 다음 요청 body에 붙인다. |

## 7. 도메인 갱신, 룰 로딩, 저장소

여기는 “실제 데이터가 바뀌는 곳”들이다. 리팩토링의 핵심은 계산과 I/O를 분리하고, 큰 오케스트레이터가 구체 작업을 leaf helper에 위임하도록 만든 것이다.

### 캐릭터 업데이트

대표 호출 흐름:

```text
CharacterUpdater
  -> Changes
  -> Leveling
    -> Progression
    -> Choices
```

#### `TrpgMaster.Campaign.ToolHandler.CharacterUpdater`

- 파일: [lib/trpg_master/campaign/tool_handler/character_updater.ex](../lib/trpg_master/campaign/tool_handler/character_updater.ex)
- 역할: 캐릭터 상태 변경 오케스트레이터.

| 함수 | 역할 |
| --- | --- |
| `update_character/2` | 일반 캐릭터 변경을 적용하고, 필요하면 레벨업 관련 재계산도 수행한다. |
| `level_up/2` | 명시적인 레벨업 요청을 처리한다. |
| `apply_xp_gain/2` | XP 증가에 따른 레벨업 계산을 `Leveling`에 위임한다. |
| `apply_level_up/3` | 구레벨/신레벨 기준 레벨업 재계산을 `Leveling`에 위임한다. |

#### `TrpgMaster.Campaign.ToolHandler.CharacterUpdater.Changes`

- 파일: [lib/trpg_master/campaign/tool_handler/character_updater/changes.ex](../lib/trpg_master/campaign/tool_handler/character_updater/changes.ex)
- 역할: 일반 필드/상태 변경 적용 담당.

| 함수 | 역할 |
| --- | --- |
| `apply_character_changes/2` | HP, AC, 인벤토리, 상태이상, 주문 슬롯 같은 일반 변경을 캐릭터 맵에 적용한다. |
| `sync_enemy_hp_to_combat_state/3` | 적 HP 변경이 있으면 전투 상태에도 반영한다. |
| `find_character_index/2` | 이름 기준으로 캐릭터 목록에서 대상 인덱스를 찾는다. |

#### `TrpgMaster.Campaign.ToolHandler.CharacterUpdater.Leveling`

- 파일: [lib/trpg_master/campaign/tool_handler/character_updater/leveling.ex](../lib/trpg_master/campaign/tool_handler/character_updater/leveling.ex)
- 역할: 레벨업 관련 파사드.

| 함수 | 역할 |
| --- | --- |
| `level_up_character/2` | 입력값을 바탕으로 레벨업 전체 흐름을 실행한다. |
| `apply_xp_gain/2` | XP 증가량으로 목표 레벨을 계산하고 필요 시 레벨업을 적용한다. |

#### `TrpgMaster.Campaign.ToolHandler.CharacterUpdater.Leveling.Progression`

- 파일: [lib/trpg_master/campaign/tool_handler/character_updater/leveling/progression.ex](../lib/trpg_master/campaign/tool_handler/character_updater/leveling/progression.ex)
- 역할: 레벨업에 따른 수치 재계산 담당.

| 함수 | 역할 |
| --- | --- |
| `apply_level_up/3` | HP, 숙련 보너스, 주문 슬롯, feature 같은 레벨 기반 수치를 다시 계산한다. |
| `maybe_apply_level_up_stats/3` | 일반 변경 중 레벨과 관련된 필드가 바뀐 경우 필요한 재계산만 적용한다. |

#### `TrpgMaster.Campaign.ToolHandler.CharacterUpdater.Leveling.Choices`

- 파일: [lib/trpg_master/campaign/tool_handler/character_updater/leveling/choices.ex](../lib/trpg_master/campaign/tool_handler/character_updater/leveling/choices.ex)
- 역할: 레벨업 시 선택 사항 적용 담당.

| 함수 | 역할 |
| --- | --- |
| `apply/2` | ASI, feat, subclass, 신규 주문 같은 선택 결과를 캐릭터에 적용한다. |
| `mark_pending/4` | 아직 선택되지 않은 ASI/subclass 같은 pending 플래그를 설정한다. |

### 룰 데이터 로더

대표 호출 흐름:

```text
Rules.Loader
  -> Manifest
  -> Local / Remote
    -> Source
  -> Indexer
```

#### `TrpgMaster.Rules.Loader`

- 파일: [lib/trpg_master/rules/loader.ex](../lib/trpg_master/rules/loader.ex)
- 역할: 룰 데이터를 ETS에 적재하고 조회 API를 제공하는 GenServer.

| 함수 | 역할 |
| --- | --- |
| `lookup/2` | 정확한 이름으로 단건 조회한다. |
| `search/2` | 부분 문자열 검색으로 여러 항목을 찾는다. |
| `list/1` | 특정 타입 전체 목록을 반환한다. |
| `status/0` | 현재 적재된 타입별 개수를 보여 준다. |
| `parse_cr/1` | CR 문자열을 숫자로 변환한다. |
| `start_link/1` | loader 서버를 시작한다. |
| `init/1` | 로컬 또는 GitHub 소스에서 룰 데이터를 적재한다. |

#### `TrpgMaster.Rules.Loader.Manifest`

- 파일: [lib/trpg_master/rules/loader/manifest.ex](../lib/trpg_master/rules/loader/manifest.ex)
- 역할: 로딩 대상 파일 메타데이터 모음.

| 함수 | 역할 |
| --- | --- |
| `data_files/0` | 데이터 JSON 파일 목록을 반환한다. |
| `rule_files/0` | 규칙 문서 JSON 파일 목록을 반환한다. |
| `github_raw_base/0` | 원격 fetch 기본 URL을 반환한다. |
| `rules_dir/0` | 로컬 룰 파일 디렉터리를 반환한다. |
| `status_types/0` | `status/0`에서 집계할 타입 목록을 반환한다. |

#### `TrpgMaster.Rules.Loader.Source`

- 파일: [lib/trpg_master/rules/loader/source.ex](../lib/trpg_master/rules/loader/source.ex)
- 역할: JSON fetch/read 공통 유틸리티.

| 함수 | 역할 |
| --- | --- |
| `fetch_json/3` | 원격 URL에서 JSON을 가져온다. |
| `read_json_file/1` | 로컬 JSON 파일을 읽고 decode한다. |

#### `TrpgMaster.Rules.Loader.Local`

- 파일: [lib/trpg_master/rules/loader/local.ex](../lib/trpg_master/rules/loader/local.ex)
- 역할: 로컬 파일 기반 로더.

| 함수 | 역할 |
| --- | --- |
| `load_data_file/2` | 데이터 파일 하나를 로드해서 ETS에 넣는다. |
| `load_rule_file/2` | 규칙 문서 파일 하나를 로드해서 ETS에 넣는다. |

#### `TrpgMaster.Rules.Loader.Remote`

- 파일: [lib/trpg_master/rules/loader/remote.ex](../lib/trpg_master/rules/loader/remote.ex)
- 역할: GitHub 원격 기반 로더.

| 함수 | 역할 |
| --- | --- |
| `load_data_file/5` | 원격 데이터 파일을 가져오고 실패 시 fallback을 실행한다. |
| `load_rule_file/5` | 원격 규칙 문서를 가져오고 실패 시 fallback을 실행한다. |

#### `TrpgMaster.Rules.Loader.Indexer`

- 파일: [lib/trpg_master/rules/loader/indexer.ex](../lib/trpg_master/rules/loader/indexer.ex)
- 역할: JSON 구조를 ETS 엔트리로 정규화한다.

| 함수 | 역할 |
| --- | --- |
| `extract_list/2` | JSON 데이터에서 실제 리스트 본문을 추출한다. |
| `insert_entries/4` | 엔트리 목록을 ETS에 삽입한다. |
| `insert_rule_document/3` | 규칙 문서와 섹션을 ETS에 삽입한다. |
| `log_columns/2` | 로드된 데이터의 컬럼 상태를 로그로 남긴다. |
| `normalize/1` | lookup/search에 쓰일 이름 정규화를 수행한다. |

### 저장소 계층

대표 호출 흐름:

```text
Persistence
  -> Files
    -> Paths
    -> Collections
  -> History
```

#### `TrpgMaster.Campaign.Persistence`

- 파일: [lib/trpg_master/campaign/persistence.ex](../lib/trpg_master/campaign/persistence.ex)
- 역할: 저장/로드용 최상위 파사드.

| 함수 | 역할 |
| --- | --- |
| `save/1` | 캠페인 전체 상태를 저장한다. |
| `save_async/1` | 저장을 백그라운드 태스크로 실행한다. |
| `load/1` | 저장 파일을 읽어 `Campaign.State`로 복원한다. |
| `list_campaigns/0` | 저장된 캠페인 목록을 최근순으로 반환한다. |
| `load_campaign_history/1` | 캠페인 메타데이터와 로그를 함께 읽는다. |
| `append_session_log/3` | 세션 로그를 append한다. |
| `load_session_log/1` | 세션 로그 목록을 읽는다. |
| `load_summary_log/1` | 컨텍스트 요약 로그를 읽는다. |
| `append_summary_log/2` | 요약 로그를 append한다. |
| `delete/1` | 저장된 캠페인을 삭제한다. |

#### `TrpgMaster.Campaign.Persistence.Files`

- 파일: [lib/trpg_master/campaign/persistence/files.ex](../lib/trpg_master/campaign/persistence/files.ex)
- 역할: 실제 캠페인 파일 저장/로드 구현.

| 함수 | 역할 |
| --- | --- |
| `save_state/2` | 요약 파일, 캐릭터, NPC, 히스토리, 저널, 컨텍스트 요약을 저장한다. |
| `load_state/1` | 캠페인 디렉터리에서 각 컬렉션을 읽어 조합한다. |
| `list_campaigns/0` | 저장된 캠페인 디렉터리를 순회해 목록을 만든다. |
| `delete_campaign/1` | 캠페인 디렉터리를 삭제한다. |
| `write_json/2` | JSON 파일 쓰기를 공통화한다. |
| `read_json/1` | JSON 파일 읽기를 공통화한다. |

#### `TrpgMaster.Campaign.Persistence.Files.Paths`

- 파일: [lib/trpg_master/campaign/persistence/files/paths.ex](../lib/trpg_master/campaign/persistence/files/paths.ex)
- 역할: 저장 경로 계산기.

| 함수 | 역할 |
| --- | --- |
| `campaigns_dir/0` | 캠페인 저장 루트 디렉터리를 반환한다. |
| `campaign_dir/1` | 특정 캠페인 디렉터리 경로를 반환한다. |
| `summary_path/1` | 요약 파일 경로를 반환한다. |
| `campaign_summary_path/1` | 내부 dir 기준 campaign summary 파일 경로를 반환한다. |
| `characters_dir/1` | 캐릭터 디렉터리 경로를 반환한다. |
| `npcs_dir/1` | NPC 디렉터리 경로를 반환한다. |
| `exploration_history_path/1` | 탐험 히스토리 파일 경로를 반환한다. |
| `legacy_exploration_history_path/1` | 구버전 탐험 히스토리 경로를 반환한다. |
| `combat_history_path/1` | 전투 히스토리 파일 경로를 반환한다. |
| `journal_path/1` | 저널 파일 경로를 반환한다. |
| `context_summary_path/1` | 컨텍스트 요약 파일 경로를 반환한다. |
| `sanitize_filename/1` | 파일명 안전화를 수행한다. |

#### `TrpgMaster.Campaign.Persistence.Files.Collections`

- 파일: [lib/trpg_master/campaign/persistence/files/collections.ex](../lib/trpg_master/campaign/persistence/files/collections.ex)
- 역할: 컬렉션 단위 저장/복원 helper.

| 함수 | 역할 |
| --- | --- |
| `ensure_campaign_dirs/1` | 저장에 필요한 디렉터리를 만든다. |
| `save_characters/3` | 캐릭터 목록을 저장한다. |
| `save_npcs/3` | NPC 목록을 저장한다. |
| `load_campaign_summary/3` | 캠페인 summary 파일을 읽는다. |
| `load_characters/2` | 캐릭터 목록을 읽는다. |
| `load_npcs/2` | NPC 목록을 읽는다. |
| `load_exploration_history/2` | 탐험 히스토리를 읽는다. |
| `load_combat_history/2` | 전투 히스토리를 읽는다. |
| `save_context_summary/3` | 컨텍스트 요약을 저장한다. |
| `load_context_summary/2` | 컨텍스트 요약을 읽는다. |
| `load_journal/2` | 저널을 읽는다. |

#### `TrpgMaster.Campaign.Persistence.History`

- 파일: [lib/trpg_master/campaign/persistence/history.ex](../lib/trpg_master/campaign/persistence/history.ex)
- 역할: 사람이 읽는 로그와 요약 로그 관리 담당.

| 함수 | 역할 |
| --- | --- |
| `load_campaign_history/1` | 히스토리 화면용 메타데이터와 로그를 함께 읽는다. |
| `append_session_log/3` | 세션 요약을 마크다운 로그에 추가한다. |
| `load_session_log/1` | 마크다운 세션 로그를 세션 단위로 읽는다. |
| `load_summary_log/1` | JSONL 요약 로그를 읽는다. |
| `append_summary_log/2` | 새 요약을 JSONL 로그에 추가한다. |

## 8. 2차 리팩토링 보강

1차 리팩토링 이후 상태 변경/입력 검증/컴포넌트 분리 관점에서 남아 있던 부분을 정리한 결과다.

목표는 세 가지였다.

1. GenServer가 직접 가지고 있던 단순 상태 변경 로직을 순수 함수 모듈로 뽑아 테스트 가능하게 만든다.
2. dispatch만 하던 ToolHandler를 진짜 dispatcher로 바꾸고, 도구별 로직은 전담 모듈로 옮긴다.
3. 채팅 UI 컴포넌트도 메시지/피드/입력 역할별로 쪼개서 다른 UI 영역과 일관된 파사드 구조로 맞춘다.

대표 변경 흐름:

```text
Campaign.Server
  -> Campaign.ServerActions      # 순수 상태 전이
  -> Campaign.Persistence.save_async  # Task.Supervisor 기반

Campaign.ToolHandler             # dispatcher
  -> CharacterUpdater            # (1차에서 이미 분리)
  -> NpcHandler / QuestHandler / LocationHandler
  -> CombatHandler / JournalHandler
  -> Shared                      # 공통 helper

AI.ToolContext                   # Process dictionary 어댑터

TrpgMasterWeb.ChatComponents     # 파사드
  -> Chat.Messages
  -> Chat.Feed
  -> Chat.Input
```

### `TrpgMaster.Campaign.ServerActions`

- 파일: [lib/trpg_master/campaign/server_actions.ex](../lib/trpg_master/campaign/server_actions.ex)
- 역할: `Campaign.Server`의 단순 상태 변경 로직을 순수 함수로 뽑은 모듈. GenServer handler는 이 함수를 호출해 새 state와 로그 문구만 받고, 저장과 로깅은 한 곳에서 처리한다.

| 함수 | 역할 |
| --- | --- |
| `set_character/2` | 파티 리스트를 새 캐릭터 1명으로 교체하고 등록 로그를 만든다. |
| `set_mode/2` | `:adventure` / `:debug` 모드로 전환하고 로그를 만든다. |
| `set_model/2` | AI 모델 ID를 변경하고 로그를 만든다. |
| `clear_session_state/1` | 세션 종료 시 히스토리/요약 필드를 초기화한다. |
| `advance_turn/1` | `turn_count`를 1 증가시킨다. |

### `TrpgMaster.Campaign.ToolHandler` (dispatcher)

- 파일: [lib/trpg_master/campaign/tool_handler.ex](../lib/trpg_master/campaign/tool_handler.ex)
- 역할: AI가 호출한 도구 결과 리스트를 받아 도구 이름을 기준으로 전담 handler에 dispatch한다. 상태 변경 로직은 더 이상 이 모듈에 없다.

| 함수 | 역할 |
| --- | --- |
| `apply_all/2` | 도구 결과 리스트를 순회하며 state에 차례대로 반영한다. |
| `apply_one/2` | 단일 도구 결과를 dispatch한다. 알 수 없는 도구는 무시하고 debug 로그만 남긴다. |

dispatch 테이블:

- `update_character`, `level_up` → `CharacterUpdater`
- `register_npc` → `NpcHandler`
- `update_quest` → `QuestHandler`
- `set_location` → `LocationHandler`
- `start_combat`, `end_combat` → `CombatHandler`
- `write_journal`, `read_journal` → `JournalHandler`

#### `TrpgMaster.Campaign.ToolHandler.Shared`

- 파일: [lib/trpg_master/campaign/tool_handler/shared.ex](../lib/trpg_master/campaign/tool_handler/shared.ex)
- 역할: 도구별 handler가 공유하는 입력 정규화 helper.

| 함수 | 역할 |
| --- | --- |
| `sanitize_name/1` | 공백·비문자열을 nil로 정규화해서 비어 있는 이름 입력을 한 군데에서 거른다. |
| `maybe_put/3` | 값이 nil이면 map을 그대로 돌려주고, 아니면 해당 키에 넣는다. |

#### `TrpgMaster.Campaign.ToolHandler.NpcHandler`

- 파일: [lib/trpg_master/campaign/tool_handler/npc_handler.ex](../lib/trpg_master/campaign/tool_handler/npc_handler.ex)
- 역할: `register_npc` 결과를 `state.npcs`에 반영한다. 이름이 비어 있으면 경고 로그만 남기고 state를 보존한다.

| 함수 | 역할 |
| --- | --- |
| `apply/2` | 기존 NPC는 필드 머지(nil 덮어쓰기 금지), 없으면 새로 추가. |

#### `TrpgMaster.Campaign.ToolHandler.QuestHandler`

- 파일: [lib/trpg_master/campaign/tool_handler/quest_handler.ex](../lib/trpg_master/campaign/tool_handler/quest_handler.ex)
- 역할: `update_quest` 결과를 `state.active_quests`에 반영한다. 기존 퀘스트는 필드 머지, 없으면 새로 추가. 이름이 비어 있으면 무시.

| 함수 | 역할 |
| --- | --- |
| `apply/2` | 이름 기준으로 append 또는 in-place update를 결정한다. |

#### `TrpgMaster.Campaign.ToolHandler.LocationHandler`

- 파일: [lib/trpg_master/campaign/tool_handler/location_handler.ex](../lib/trpg_master/campaign/tool_handler/location_handler.ex)
- 역할: `set_location` 결과로 `state.current_location`을 갱신한다. 비어 있는 위치 이름은 무시.

| 함수 | 역할 |
| --- | --- |
| `apply/2` | `location_name`을 sanitize해서 현재 위치에 반영한다. |

#### `TrpgMaster.Campaign.ToolHandler.CombatHandler`

- 파일: [lib/trpg_master/campaign/tool_handler/combat_handler.ex](../lib/trpg_master/campaign/tool_handler/combat_handler.ex)
- 역할: `start_combat` / `end_combat` 결과를 state에 반영한다. 전투 종료 시 플레이어 캐릭터만 남기고, XP 지급 시 레벨업까지 재계산한다.

| 함수 | 역할 |
| --- | --- |
| `start/2` | `combat_state`를 구성하고 phase를 `:combat`으로 전환한다. |
| `finish/2` | `player_names` 기준으로 캐릭터를 필터링하고, xp가 있으면 `CharacterUpdater.apply_xp_gain/2`에 위임한다. |

#### `TrpgMaster.Campaign.ToolHandler.JournalHandler`

- 파일: [lib/trpg_master/campaign/tool_handler/journal_handler.ex](../lib/trpg_master/campaign/tool_handler/journal_handler.ex)
- 역할: `write_journal` / `read_journal` 결과를 state에 반영한다. 엔트리는 최근 100개까지만 유지한다.

| 함수 | 역할 |
| --- | --- |
| `write/2` | entry 텍스트, category, timestamp를 포함한 엔트리를 append하고 개수를 제한한다. |
| `read/2` | state를 그대로 돌려준다. 실제 응답 조립은 `Tools.execute`에서 프로세스 컨텍스트로 수행한다. |

### `TrpgMaster.AI.ToolContext`

- 파일: [lib/trpg_master/ai/tool_context.ex](../lib/trpg_master/ai/tool_context.ex)
- 역할: 도구 실행 중 필요한 캠페인 컨텍스트(캐릭터 목록, 저널)를 Process dictionary로 전달하는 얇은 어댑터. provider 체인이 깊어 인자 전달이 어려운 구간을 한 군데에서 관리한다.

| 함수 | 역할 |
| --- | --- |
| `with_context/2` | 컨텍스트를 심고 함수를 실행한 뒤, 결과와 무관하게 정리한다. `nil`이면 그대로 실행한다. |
| `put/1` | 현재 프로세스에 컨텍스트를 저장한다. `with_context/2` 바깥에서는 사용을 피한다. |
| `clear/0` | 저장된 컨텍스트를 제거한다. |
| `characters/0` | 현재 프로세스의 캐릭터 목록을 읽는다. 없으면 `[]`. |
| `journal_entries/0` | 현재 프로세스의 저널 목록을 읽는다. 없으면 `[]`. |

### `TrpgMasterWeb.ChatComponents`

- 파일: [lib/trpg_master_web/components/chat_components.ex](../lib/trpg_master_web/components/chat_components.ex)
- 역할: 캠페인 채팅 UI의 공개 API 파사드. 실제 렌더는 역할별 하위 모듈로 `defdelegate`.

| 함수 | 역할 |
| --- | --- |
| `dm_message/1`, `player_message/1`, `dice_result/1`, `tool_narration/1`, `system_message/1` | 메시지 종류별 렌더를 `Chat.Messages`에 위임한다. |
| `chat_feed/1`, `typing_indicator/1` | 피드 영역 렌더를 `Chat.Feed`에 위임한다. |
| `chat_input/1` | 입력 폼 렌더를 `Chat.Input`에 위임한다. |

#### `TrpgMasterWeb.Chat.Messages`

- 파일: [lib/trpg_master_web/components/chat/messages.ex](../lib/trpg_master_web/components/chat/messages.ex)
- 역할: 메시지 말풍선 컴포넌트 모음.

| 함수 | 역할 |
| --- | --- |
| `dm_message/1` | DM 메시지(Markdown 렌더 포함)를 그린다. |
| `player_message/1` | 플레이어 메시지를 그린다. |
| `dice_result/1` | 주사위 결과(크리티컬/펌블 배지 포함)를 그린다. |
| `tool_narration/1` | 도구 실행 알림 메시지를 그린다. |
| `system_message/1` | 시스템/안내 메시지를 그린다. |

#### `TrpgMasterWeb.Chat.Feed`

- 파일: [lib/trpg_master_web/components/chat/feed.ex](../lib/trpg_master_web/components/chat/feed.ex)
- 역할: 메시지 리스트와 상태 표시를 담당하는 피드 영역.

| 함수 | 역할 |
| --- | --- |
| `chat_feed/1` | 메시지 리스트, 로딩/세션종료/에러 상태를 조립한다. |
| `typing_indicator/1` | DM 타이핑 중 표시를 그린다. |

#### `TrpgMasterWeb.Chat.Input`

- 파일: [lib/trpg_master_web/components/chat/input.ex](../lib/trpg_master_web/components/chat/input.ex)
- 역할: 채팅 입력 폼.

| 함수 | 역할 |
| --- | --- |
| `chat_input/1` | 처리/로딩 상태에 따라 placeholder, disabled 상태를 바꾼 textarea 폼을 그린다. |

### 그 외 안정성 보강

- `Campaign.Persistence.save_async/1`이 `Task.Supervisor`(`TrpgMaster.TaskSupervisor`) 아래에서 실행된다. 저장 중 예외가 LiveView 프로세스로 전파되지 않는다.
- `Campaign.Persistence.Files.Paths.sanitize_filename/1`이 `..` 경로 순회, 예약 문자, 제어 문자를 모두 차단해 사용자 입력에서 유래한 campaign_id가 `campaigns/` 디렉터리 밖으로 나갈 수 없다.
- `Campaign.Persistence.History`가 `summary_log.jsonl`의 손상된 라인을 만나도 경고 로그를 남기고 이어서 읽는다.

## 9. 요약 관점에서 보는 구조 변화

마지막으로, 이번 리팩토링을 한 문장씩 요약하면 아래와 같다.

- `LiveView`는 “입력 받고 위임하는 곳”이 되었다.
- `Presenter`와 `Component facade`는 “공개 API를 유지하면서 구현을 분리하는 경계”가 되었다.
- `PromptBuilder`, `Summarizer`, `ToolDefinitions`는 “프롬프트/요약/도구”라는 서로 다른 AI 책임을 나눠 갖게 되었다.
- `Provider` 계층은 “request 조립, 공통 loop, response 해석, retry policy”로 깔끔하게 나뉘었다.
- `CharacterUpdater`, `Rules.Loader`, `Persistence`는 “오케스트레이션”과 “실제 세부 작업”이 분리되어 수정 포인트가 훨씬 선명해졌다.

## 10. 다음에 문서를 더 확장한다면

이 문서는 현재 “구조 지도”에 가깝다. 이후 아래 내용을 추가하면 온보딩 문서로 더 강해진다.

1. 각 대표 플로우의 시퀀스 다이어그램
2. 테스트 파일과 모듈의 대응 관계
3. 모듈별 입력/출력 데이터 예시
4. 앞으로 더 쪼갤 후보 모듈과 이유
