defmodule TrpgMaster.AI.PromptBuilder.Sections.Context do
  @moduledoc false

  alias TrpgMaster.Campaign.State

  def build_campaign_context(%State{} = state) do
    [
      campaign_section(state),
      characters_section(state),
      npcs_section(state),
      quests_section(state),
      combat_section(state)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp campaign_section(state) do
    location = state.current_location || "미정"

    player_name_line =
      case state.characters do
        [first | _] when is_map(first) ->
          name = first["name"] || "(이름 없음)"
          "\n- **플레이어 캐릭터 이름: #{name}** ← update_character/level_up 호출 시 반드시 이 이름을 그대로 사용하세요."

        _ ->
          ""
      end

    """
    ## 현재 캠페인 상황
    - 캠페인: #{state.name}
    - 위치: #{location}
    - 페이즈: #{state.phase}
    - 턴: #{state.turn_count}
    - 모드: #{state.mode}#{player_name_line}
    """
  end

  defp characters_section(%{characters: []}), do: nil

  defp characters_section(state) do
    chars =
      state.characters
      |> Enum.map(fn character ->
        hp =
          if character["hp_current"] && character["hp_max"],
            do: " | HP #{character["hp_current"]}/#{character["hp_max"]}",
            else: ""

        ac = if character["ac"], do: " | AC #{character["ac"]}", else: ""
        level = if character["level"], do: " Lv.#{character["level"]}", else: ""
        class = if character["class"], do: " #{character["class"]}", else: ""
        race = if character["race"], do: " #{character["race"]}", else: ""

        conditions =
          case character["conditions"] do
            list when is_list(list) and list != [] -> " | 상태: #{Enum.join(list, ", ")}"
            _ -> ""
          end

        spell_info = format_spell_slots(character["spell_slots"], character["spell_slots_used"])

        "- #{character["name"]}#{race}#{class}#{level}#{hp}#{ac}#{conditions}#{spell_info}"
      end)
      |> Enum.join("\n")

    """
    ## 캐릭터 정보
    #{chars}

    캐릭터의 능력치, 장비, 주문, 특성 등 상세 정보가 필요하면 반드시 get_character_info 도구를 사용하세요.
    판정(능력치 확인, 내성 굴림 등)이나 전투 시작 전에 항상 먼저 캐릭터 정보를 조회하세요.
    카테고리: abilities(능력치), combat(전투), spells(주문), equipment(장비), features(특성), proficiencies(숙련), summary(요약), full(전체)
    """
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
      |> Enum.map(fn quest ->
        status = if quest["status"], do: " [#{quest["status"]}]", else: ""
        desc = if quest["description"], do: " — #{quest["description"]}", else: ""
        "- #{quest["name"]}#{status}#{desc}"
      end)
      |> Enum.join("\n")

    "## 진행 중인 퀘스트\n#{quests}"
  end

  defp combat_section(%{combat_state: nil}), do: nil

  defp combat_section(state) do
    combat_state = state.combat_state
    participants = (combat_state["participants"] || []) |> Enum.join(", ")
    player_names = combat_state["player_names"] || []

    enemies_section =
      case combat_state["enemies"] do
        enemies when is_list(enemies) and enemies != [] ->
          enemy_lines =
            Enum.map(enemies, fn enemy ->
              hp =
                if enemy["hp_current"] && enemy["hp_max"],
                  do: " HP #{enemy["hp_current"]}/#{enemy["hp_max"]}",
                  else: ""

              ac = if enemy["ac"], do: " AC #{enemy["ac"]}", else: ""
              count = if enemy["count"] && enemy["count"] > 1, do: " x#{enemy["count"]}", else: ""
              "  - #{enemy["name"]}#{count}#{hp}#{ac}"
            end)
            |> Enum.join("\n")

          "\n- 적 현황:\n#{enemy_lines}"

        _ ->
          ""
      end

    solo_note =
      if length(player_names) <= 1 do
        "\n- ⚠️ 솔로 플레이: 아군이 1명뿐입니다. 플레이어 HP가 0 이하가 되면 죽음 내성 굴림 없이 즉시 기절 또는 사망 처리 후 end_combat을 호출하세요."
      else
        ""
      end

    """
    ## 전투 진행 중
    - 라운드: #{combat_state["round"] || 1}
    - 참가자: #{participants}#{enemies_section}#{solo_note}
    """
  end

  defp format_spell_slots(slots, _used) when not is_map(slots) or map_size(slots) == 0, do: ""

  defp format_spell_slots(slots, used) do
    slot_parts =
      slots
      |> Enum.sort_by(fn {level, _} -> String.to_integer(level) end)
      |> Enum.map(fn {level, total} ->
        used_count = (used || %{})[level] || 0
        remaining = max(total - used_count, 0)
        "Lv.#{level}: #{remaining}/#{total}"
      end)
      |> Enum.join(", ")

    " | 주문 슬롯: #{slot_parts}"
  end
end
