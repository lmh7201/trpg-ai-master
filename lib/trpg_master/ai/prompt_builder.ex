defmodule TrpgMaster.AI.PromptBuilder do
  @moduledoc """
  시스템 프롬프트 로드 + 캠페인 상태 기반 컨텍스트 조립.
  """

  alias TrpgMaster.Campaign.State

  @system_prompt_path "priv/prompts/system_dm.md"

  # 토큰 예산 (한국어 위주: ~1토큰/2문자 보수적 추정)
  # 분당 30K 토큰 rate limit 기준: 시스템 프롬프트(3K) + 도구(8K) + 히스토리 = ~23K 이내 유지
  # prompt caching 적용 시 시스템+도구는 캐시되므로 추후 상향 가능
  @max_history_tokens 12_000

  require Logger

  @doc """
  Campaign.State를 받아서 풍부한 시스템 프롬프트를 조립한다.
  mode에 따라 디버그/모험 분기를 추가한다.
  """
  def build(%State{} = state) do
    base = system_prompt()
    context = build_campaign_context(state)
    tools_instruction = state_tools_instruction()
    mode_instruction = mode_instruction(state.mode)

    "#{base}\n\n#{context}\n\n#{tools_instruction}\n\n#{mode_instruction}"
  end

  @doc """
  기본 시스템 프롬프트를 로드한다 (하위 호환).
  """
  def system_prompt do
    case File.read(@system_prompt_path) do
      {:ok, content} -> content
      {:error, _} -> default_system_prompt()
    end
  end

  @doc """
  토큰 예산 기반으로 대화 히스토리를 트리밍한다.
  최근 메시지를 최대한 많이 포함하되 @max_history_tokens 예산 초과 시 오래된 것부터 제거.
  """
  def build_messages(history) when is_list(history) do
    total = estimate_tokens(history)

    if total <= @max_history_tokens do
      history
    else
      # 최근 메시지부터 역순으로 누적하여 예산 내 메시지만 선택
      {recent, _remaining} =
        history
        |> Enum.reverse()
        |> Enum.reduce_while({[], @max_history_tokens}, fn msg, {acc, remaining} ->
          tokens = estimate_tokens_msg(msg) + 10
          if tokens <= remaining do
            {:cont, {[msg | acc], remaining - tokens}}
          else
            {:halt, {acc, 0}}
          end
        end)

      trimmed_count = length(history) - length(recent)

      if trimmed_count > 0 do
        Logger.info(
          "히스토리 트리밍: #{length(history)}개 → #{length(recent)}개 (#{trimmed_count}개 제거, 추정 토큰: #{total})"
        )
      end

      recent
    end
  end

  @doc """
  하위 호환: trim_history/1은 build_messages/1로 대체됨.
  """
  def trim_history(history), do: build_messages(history)

  # ── Token estimation ────────────────────────────────────────────────────────

  # 한국어와 영어 비율을 고려한 토큰 추정.
  # 한글: ~1토큰/2글자, 영어/숫자/기호: ~1토큰/4글자.
  # 보수적 방향으로 유지 (과소 추정보다 과대 추정이 안전).
  defp estimate_tokens(text) when is_binary(text) do
    total_chars = String.length(text)

    if total_chars == 0 do
      0
    else
      # 성능을 위해 바이트 기준 간이 판별: 한글은 UTF-8에서 3바이트
      byte_size = byte_size(text)
      # 멀티바이트 문자 비율로 한글 비중 추정 (정확하진 않지만 Regex.scan보다 빠름)
      multibyte_chars = byte_size - total_chars
      korean_ratio = min(multibyte_chars / max(byte_size, 1), 1.0)

      # 가중 평균: 한글 비율만큼 2글자/토큰, 나머지는 4글자/토큰
      chars_per_token = 2.0 * korean_ratio + 4.0 * (1.0 - korean_ratio)
      tokens = ceil(total_chars / chars_per_token)

      # 메시지 오버헤드 (role, content 키 등)
      tokens + 4
    end
  end

  defp estimate_tokens(messages) when is_list(messages) do
    Enum.sum(Enum.map(messages, &(estimate_tokens_msg(&1) + 10)))
  end

  defp estimate_tokens_msg(%{"content" => content}) when is_binary(content) do
    estimate_tokens(content)
  end

  defp estimate_tokens_msg(_), do: 10

  # ── Private ─────────────────────────────────────────────────────────────────

  defp build_campaign_context(%State{} = state) do
    sections = [
      campaign_section(state),
      characters_section(state),
      npcs_section(state),
      quests_section(state),
      combat_section(state)
    ]

    sections
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp campaign_section(state) do
    location = state.current_location || "미정"

    """
    ## 현재 캠페인 상황
    - 캠페인: #{state.name}
    - 위치: #{location}
    - 페이즈: #{state.phase}
    - 턴: #{state.turn_count}
    - 모드: #{state.mode}
    """
  end

  defp characters_section(%{characters: []}), do: nil

  defp characters_section(state) do
    chars =
      state.characters
      |> Enum.map(fn c ->
        hp =
          if c["hp_current"] && c["hp_max"],
            do: " | HP #{c["hp_current"]}/#{c["hp_max"]}",
            else: ""

        ac = if c["ac"], do: " | AC #{c["ac"]}", else: ""
        level = if c["level"], do: " Lv.#{c["level"]}", else: ""
        class = if c["class"], do: " #{c["class"]}", else: ""

        conditions =
          case c["conditions"] do
            list when is_list(list) and list != [] -> " | 상태: #{Enum.join(list, ", ")}"
            _ -> ""
          end

        "- #{c["name"]}#{class}#{level}#{hp}#{ac}#{conditions}"
      end)
      |> Enum.join("\n")

    "## 캐릭터 정보\n#{chars}"
  end

  defp npcs_section(%{npcs: npcs}) when map_size(npcs) == 0, do: nil

  defp npcs_section(state) do
    npcs =
      state.npcs
      |> Enum.map(fn {name, data} ->
        desc = if data["description"], do: " — #{data["description"]}", else: ""
        disp = if data["disposition"], do: " (#{data["disposition"]})", else: ""
        loc = if data["location"], do: " @ #{data["location"]}", else: ""
        "- #{name}#{desc}#{disp}#{loc}"
      end)
      |> Enum.join("\n")

    "## 주요 NPC\n#{npcs}"
  end

  defp quests_section(%{active_quests: []}), do: nil

  defp quests_section(state) do
    quests =
      state.active_quests
      |> Enum.map(fn q ->
        status = if q["status"], do: " [#{q["status"]}]", else: ""
        desc = if q["description"], do: " — #{q["description"]}", else: ""
        "- #{q["name"]}#{status}#{desc}"
      end)
      |> Enum.join("\n")

    "## 진행 중인 퀘스트\n#{quests}"
  end

  defp combat_section(%{combat_state: nil}), do: nil

  defp combat_section(state) do
    cs = state.combat_state
    participants = (cs["participants"] || []) |> Enum.join(", ")

    """
    ## 전투 진행 중
    - 라운드: #{cs["round"] || 1}
    - 참가자: #{participants}
    """
  end

  defp state_tools_instruction do
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

    ### 도구 미사용 결과
    도구를 호출하지 않고 서술만 하면: 서버가 해당 정보를 저장하지 않습니다.
    다음 턴에서 당신은 그 정보를 시스템 프롬프트에서 볼 수 없게 됩니다.
    일관성 있는 게임 진행을 위해 모든 상태 변경을 반드시 도구로 기록하세요.
    """
  end

  defp mode_instruction(:adventure) do
    """
    ## 🎭 모험 모드 (현재 활성)

    - 몬스터 스탯(AC, HP, 공격 보너스 등)을 플레이어에게 직접 공개하지 않습니다.
    - 숨겨진 판정(숨겨진 DC, 몬스터의 주사위 결과)은 서술로만 처리하고 수치를 노출하지 않습니다.
    - DM 전용 정보(罠의 DC, 적의 전투 계획 등)는 플레이어 서술에 포함하지 않습니다.
    - 몰입감 있는 서술을 최우선으로 합니다.
    """
  end

  defp mode_instruction(:debug) do
    """
    ## 🔧 디버그 모드 (현재 활성)

    - 모든 판정의 DC, 주사위 결과, 수정치를 명시적으로 공개합니다.
    - 몬스터 스탯(AC, HP, 공격 보너스 등)을 공개합니다.
    - 룰 판정 근거를 설명합니다 (예: "민첩 내성 DC 14, 결과 17 → 성공").
    - 도구 호출 결과를 자세히 설명합니다.
    - 학습/테스트 목적에 최적화된 모드입니다.
    """
  end

  defp mode_instruction(_), do: mode_instruction(:adventure)

  defp default_system_prompt do
    """
    당신은 D&D 5e 솔로 플레이 던전 마스터입니다. 한국어로 진행합니다.

    ## 기본 원칙
    - 모든 서술, 대화, 룰 설명은 한국어로 합니다.
    - 감각적 묘사를 적극 활용합니다.
    - 플레이어 행동에 의미 있는 분기를 제공합니다.

    ## 주사위 규칙
    - 모든 판정은 반드시 roll_dice 도구를 사용합니다.
    - 숫자를 임의로 지어내지 않습니다.

    ## 중요
    - 항상 서술 끝에 행동 유도를 제시합니다.
    - tool use 결과를 자연스러운 서술에 녹여냅니다.
    """
  end
end
