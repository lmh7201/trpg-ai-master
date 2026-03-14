defmodule TrpgMaster.AI.PromptBuilder do
  @moduledoc """
  시스템 프롬프트 로드 + 캠페인 상태 기반 컨텍스트 조립.
  """

  alias TrpgMaster.Campaign.State

  @system_prompt_path "priv/prompts/system_dm.md"
  @max_history_messages 20

  @doc """
  Campaign.State를 받아서 풍부한 시스템 프롬프트를 조립한다.
  """
  def build(%State{} = state) do
    base = system_prompt()
    context = build_campaign_context(state)
    tools_instruction = state_tools_instruction()

    "#{base}\n\n#{context}\n\n#{tools_instruction}"
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
  대화 히스토리에서 최근 N개만 반환한다 (토큰 예산 관리).
  """
  def trim_history(history) when length(history) <= @max_history_messages, do: history

  def trim_history(history) do
    Enum.take(history, -@max_history_messages)
  end

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
    ## 상태 관리 도구 사용 지침

    아래 도구들을 사용하여 캠페인 상태를 관리합니다. 상태 변경은 자동으로 저장됩니다.

    - **update_character**: 캐릭터가 처음 등장하거나, HP/인벤토리/상태이상 등이 변할 때 반드시 호출합니다.
      - ⚠️ 플레이어 캐릭터가 소개되면 즉시 호출하여 초기 스탯(이름, 클래스, 레벨, hp_max, hp_current, ac, 초기 장비)을 등록합니다.
      - 전투에서 피해를 입으면 hp_current를 업데이트합니다.
      - 아이템을 얻거나 잃으면 inventory_add/inventory_remove를 사용합니다.
    - **register_npc**: 새로운 NPC가 등장하거나 NPC의 태도/상태가 변할 때 호출합니다.
    - **update_quest**: 새 퀘스트를 발견하거나 진행 상황이 바뀔 때 호출합니다.
    - **set_location**: 파티가 새로운 장소로 이동할 때 호출합니다.
    - **start_combat**: 전투가 시작될 때 호출합니다. 그 후 roll_dice로 주도권을 굴립니다.
    - **end_combat**: 전투가 끝날 때 호출합니다.

    이 도구들을 적극적으로 사용하여 게임 상태를 정확하게 추적하세요.
    """
  end

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
