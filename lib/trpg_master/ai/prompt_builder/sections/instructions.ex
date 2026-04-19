defmodule TrpgMaster.AI.PromptBuilder.Sections.Instructions do
  @moduledoc false

  def build_summary_section(nil), do: ""

  def build_summary_section(summary) do
    """
    ## 이전 대화 요약 (참고용 맥락)
    아래는 슬라이딩 윈도우 밖의 과거 대화를 요약한 것이다. 이미 서술한 내용이므로 반복하지 말고, 맥락 파악용으로만 참고하라.

    #{summary}

    """
  end

  def build_combat_summary_section(nil), do: ""

  def build_combat_summary_section(summary) do
    """
    ## 현재 전투 요약
    아래는 현재 전투의 이전 라운드들을 요약한 것이다. 전투의 흐름을 파악하되, 이미 서술한 내용을 반복하지 마라.

    #{summary}

    """
  end

  def build_post_combat_section(nil), do: ""

  def build_post_combat_section(summary) do
    """
    ## 직전 전투 요약
    아래는 방금 끝난 전투의 요약이다. 전투는 이미 완전히 종료되었다.
    - 전투 결과를 참고하여 탐험 서술에 자연스럽게 반영하라.
    - 전투 묘사를 계속하거나 추가 전투 라운드를 진행하지 마라.
    - 전투 후 상황(부상 치료, 전리품 확인, 다음 행동 등)을 서술하라.

    #{summary}

    """
  end

  def build_combat_phase_instruction(nil) do
    """
    ## 현재 모드: 탐험
    현재 전투 중이 아닙니다. 전투 행동(공격 굴림, 피해 적용, 전투 라운드 진행)을 서술하지 마세요.
    전투가 필요한 상황이 발생하면 반드시 start_combat을 먼저 호출하세요.

    """
  end

  def build_combat_phase_instruction(:player_turn) do
    """
    ## 전투 턴 진행 — 플레이어 턴
    이번 응답에서는 플레이어의 행동만 서술하세요.
    - 플레이어가 선언한 행동을 처리합니다 (공격, 주문, 이동 등)
    - roll_dice로 공격/피해 굴림을 수행합니다
    - update_character로 HP 등 상태 변경을 기록합니다 (적의 HP 변경도 반드시 update_character로 기록)
    - 적의 반격이나 턴은 서술하지 마세요. 다음 응답에서 처리됩니다.
    - 서술 끝에 "무엇을 하시겠습니까?"를 붙이지 마세요.

    """
  end

  def build_combat_phase_instruction({:enemy_turn, enemy_name, true}) do
    """
    ## 전투 턴 진행 — #{enemy_name}의 턴 (마지막 적 그룹)
    이번 응답에서는 #{enemy_name}의 행동만 서술하세요. 다른 적의 행동은 서술하지 마세요.
    - #{enemy_name}의 공격, 이동, 특수 능력 사용을 처리합니다
    - roll_dice로 #{enemy_name}의 공격/피해 굴림을 수행합니다
    - update_character로 플레이어 캐릭터의 HP 변경을 기록합니다
    - 서술 끝에 "무엇을 하시겠습니까?"를 붙이지 마세요. 라운드 정리 단계에서 플레이어에게 묻습니다.

    """
  end

  def build_combat_phase_instruction({:enemy_turn, enemy_name, false}) do
    """
    ## 전투 턴 진행 — #{enemy_name}의 턴
    이번 응답에서는 #{enemy_name}의 행동만 서술하세요. 다른 적의 행동은 서술하지 마세요.
    - #{enemy_name}의 공격, 이동, 특수 능력 사용을 처리합니다
    - roll_dice로 #{enemy_name}의 공격/피해 굴림을 수행합니다
    - update_character로 플레이어 캐릭터의 HP 변경을 기록합니다
    - 서술 끝에 "무엇을 하시겠습니까?"를 붙이지 마세요. 아직 다른 적의 턴이 남아있습니다.

    """
  end

  def build_combat_phase_instruction(:round_summary) do
    """
    ## 전투 라운드 정리
    이번 라운드의 모든 턴이 끝났습니다. 다음을 순서대로 수행하세요:
    - 이번 라운드의 전투 결과를 간결하게 정리합니다 (각 전투원의 행동, 주사위 결과, 피해량)
    - 현재 전장 상황을 요약합니다 (생존 중인 전투원 HP, 전반적인 전황)
    - 서술 끝에 플레이어에게 다음 행동을 묻습니다: "무엇을 하시겠습니까?"

    """
  end

  def build_combat_phase_instruction(:enemy_turn) do
    build_combat_phase_instruction({:enemy_turn, "적", true})
  end

  def state_tools_instruction do
    """
    ## ⚠️ 중요: 상태 관리 도구를 반드시 사용하세요

    서버는 당신이 도구를 호출한 결과만 기억합니다. 도구를 호출하지 않으면 다음 턴에서 정보를 잃습니다.

    ### 필수 규칙 (예외 없음)

    - **새로운 NPC가 등장하면 → 반드시 register_npc를 즉시 호출**
      - 이름, 외모, 성격, 태도(friendly/neutral/hostile), 위치를 기록합니다
      - 당신이 register_npc를 호출하지 않으면 서버가 이 NPC를 전혀 기억하지 못합니다
      - 다음 턴에서 플레이어가 NPC를 언급해도 당신은 기억하지 못하게 됩니다
    - **캐릭터 HP/아이템/상태가 변하면 → 반드시 update_character를 호출**
      - 플레이어 캐릭터가 처음 소개되면 즉시 초기 스탯을 등록합니다
      - 전투 피해 → hp_current 업데이트
      - 아이템 획득/소실 → inventory_add/inventory_remove
    - **파티가 이동하면 → 반드시 set_location을 호출**
    - **새 퀘스트 발견 또는 진행 → 반드시 update_quest를 호출**
    - **전투 시작 → start_combat, 전투 종료 → end_combat**

    ### 도구 호출과 서술의 관계
    - 도구는 **서술을 대체하지 않습니다**. 도구 호출 후에도 반드시 상황묘사를 이어가세요.
    - 특히 **새 NPC 등장 시**: register_npc 호출과 함께 NPC의 외모, 분위기, 주변 상황을 생생하게 묘사한 뒤 플레이어에게 선택지를 제시하세요.
    - 도구 호출만 하고 "어떻게 하시겠습니까?"로 끝내지 마세요. 플레이어가 반응할 수 있는 장면을 먼저 그려주세요.

    ### 도구 미사용 결과
    도구를 호출하지 않고 서술만 하면: 서버가 해당 정보를 저장하지 않습니다.
    다음 턴에서 당신은 그 정보를 시스템 프롬프트에서 볼 수 없게 됩니다.
    일관성 있는 게임 진행을 위해 모든 상태 변경을 반드시 도구로 기록하세요.
    """
  end

  def mode_instruction(:adventure) do
    """
    ## 🎭 모험 모드 (현재 활성)

    - 몬스터 스탯(AC, HP, 공격 보너스 등)을 플레이어에게 직접 공개하지 않습니다.
    - 숨겨진 판정(숨겨진 DC, 몬스터의 주사위 결과)은 서술로만 처리하고 수치를 노출하지 않습니다.
    - DM 전용 정보(罠의 DC, 적의 전투 계획 등)는 플레이어 서술에 포함하지 않습니다.
    - 몰입감 있는 서술을 최우선으로 합니다.
    """
  end

  def mode_instruction(:debug) do
    """
    ## 🔧 디버그 모드 (현재 활성)

    - 모든 판정의 DC, 주사위 결과, 수정치를 명시적으로 공개합니다.
    - 몬스터 스탯(AC, HP, 공격 보너스 등)을 공개합니다.
    - 룰 판정 근거를 설명합니다 (예: "민첩 내성 DC 14, 결과 17 → 성공").
    - 도구 호출 결과를 자세히 설명합니다.
    - 학습/테스트 목적에 최적화된 모드입니다.
    """
  end

  def mode_instruction(_), do: mode_instruction(:adventure)
end
