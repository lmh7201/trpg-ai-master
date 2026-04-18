defmodule TrpgMaster.Campaign.Summarizer.Prompts do
  @moduledoc false

  def session_summary_prompt(state) do
    """
    당신은 D&D 세션 서기입니다. 아래 세션 정보를 바탕으로 간결한 세션 요약을 작성해주세요.

    ## 캠페인: #{state.name}
    ## 위치: #{state.current_location || "미정"}
    ## 진행 턴: #{state.turn_count}

    ## 캐릭터
    #{format_characters(state.characters)}

    ## NPC
    #{format_npcs(state.npcs)}

    ## 퀘스트
    #{format_quests(state.active_quests)}

    위 정보를 바탕으로 다음 형식으로 요약을 작성해주세요:

    ## 세션 요약
    (이번 세션의 주요 사건을 2~3문단으로 요약)

    ## 파티 현황
    (캐릭터 HP, 현재 위치, 활성 퀘스트)

    ## 등장 NPC
    (이번 세션에 등장한 NPC 목록)

    ## 다음 세션 예고
    (다음 세션에서 할 일이나 남은 미스터리를 1~2문장으로)
    """
  end

  def context_summary_prompt(previous_summary, ai_messages) do
    new_exchange =
      ai_messages
      |> Enum.take(-5)
      |> Enum.map(fn %{"content" => content} ->
        "DM: #{String.slice(content, 0, 1000)}"
      end)
      |> Enum.join("\n")

    """
    당신은 TRPG 세션 기록 요약 도우미입니다.
    [중요] 반드시 이전 요약의 핵심 정보를 보존하면서 최근 AI 응답 내용을 통합하세요.

    ## 이전 요약
    #{previous_summary}

    ## 최근 AI(DM) 응답 히스토리 (최대 5개)
    #{new_exchange}

    ## 지시사항
    위 정보를 하나의 간결한 요약으로 통합하세요 (최대 500자).
    반드시 포함할 내용:
    - 등장한 NPC들 (이름과 태도)
    - 현재 진행 중인 퀘스트와 상태
    - 현재 위치
    - 최근 주요 사건이나 결정
    불필요한 세부사항은 생략하고, 다음 턴에서 DM이 맥락을 파악하는 데 필요한 정보만 남기세요.
    마크다운 서식을 사용하지 마세요. ##, **, *, ` 같은 서식 기호 없이 순수 텍스트로만 작성하세요.
    """
  end

  def combat_history_summary_prompt(previous_summary, ai_messages, state) do
    new_exchange =
      ai_messages
      |> Enum.take(-3)
      |> Enum.map(fn %{"content" => content} ->
        "DM: #{String.slice(content, 0, 800)}"
      end)
      |> Enum.join("\n")

    """
    당신은 TRPG 전투 기록 요약 도우미입니다.
    [중요] 반드시 이전 요약의 핵심 정보를 보존하면서 최근 전투 내용을 통합하세요.

    ## 이전 전투 요약
    #{previous_summary}

    ## 최근 전투 진행 (최대 3건)
    #{new_exchange}

    ## 현재 참가자 상태
    #{format_combatants_status(state)}

    ## 지시사항
    위 정보를 하나의 간결한 전투 요약으로 통합하세요 (최대 400자).
    반드시 포함할 내용:
    - 각 라운드의 주요 공격/피해
    - 현재 적의 상태 (HP 변화, 사망 여부)
    - 현재 아군의 상태 (HP 변화)
    - 사용된 주요 능력이나 주문
    마크다운 서식을 사용하지 마세요. 순수 텍스트로만 작성하세요.
    """
  end

  def post_combat_summary_prompt(ai_messages, state) do
    combat_exchanges =
      ai_messages
      |> Enum.map(fn %{"content" => content} ->
        "DM: #{String.slice(content, 0, 800)}"
      end)
      |> Enum.join("\n")

    """
    당신은 TRPG 전투 기록 요약 도우미입니다. 전투가 끝났습니다.

    ## 전투 전체 기록
    #{combat_exchanges}

    ## 전투 종료 시 참가자 상태
    #{format_combatants_status(state)}

    ## 지시사항
    위 전투 전체를 간결하게 요약하세요 (최대 500자).
    반드시 포함할 내용:
    - 전투 참가자 (아군, 적)와 최종 상태 (HP, 사망 여부)
    - 전투의 전개 과정 (주요 전환점)
    - 전투 결과 (승패, 사상자)
    - 획득한 전리품이나 경험치 (언급된 경우)
    마크다운 서식을 사용하지 마세요. 순수 텍스트로만 작성하세요.
    """
  end

  def recent_combined_history(state, limit \\ 20) do
    state.exploration_history
    |> Kernel.++(state.combat_history)
    |> Enum.take(-limit)
  end

  def format_combatants_status(state) do
    player_names = get_in(state.combat_state, ["player_names"]) || []
    enemies = get_in(state.combat_state, ["enemies"]) || []

    player_lines =
      state.characters
      |> Enum.filter(fn character -> character["name"] in player_names end)
      |> Enum.map(fn character ->
        hp =
          if character["hp_current"] && character["hp_max"] do
            " HP #{character["hp_current"]}/#{character["hp_max"]}"
          else
            ""
          end

        status =
          if is_number(character["hp_current"]) and character["hp_current"] <= 0,
            do: " [쓰러짐]",
            else: ""

        conditions =
          case character["conditions"] do
            list when is_list(list) and list != [] -> " 상태: #{Enum.join(list, ", ")}"
            _ -> ""
          end

        "- [아군] #{character["name"]}#{hp}#{status}#{conditions}"
      end)

    enemy_lines =
      Enum.map(enemies, fn enemy ->
        hp =
          if enemy["hp_current"] && enemy["hp_max"] do
            " HP #{enemy["hp_current"]}/#{enemy["hp_max"]}"
          else
            ""
          end

        status =
          if is_number(enemy["hp_current"]) and enemy["hp_current"] <= 0,
            do: " [사망]",
            else: ""

        "- [적] #{enemy["name"]}#{hp}#{status}"
      end)

    Enum.join(player_lines ++ enemy_lines, "\n")
  end

  defp format_characters([]), do: "(없음)"

  defp format_characters(characters) do
    characters
    |> Enum.map(fn character ->
      hp =
        if character["hp_current"] && character["hp_max"] do
          " HP #{character["hp_current"]}/#{character["hp_max"]}"
        else
          ""
        end

      "- #{character["name"]}#{hp}"
    end)
    |> Enum.join("\n")
  end

  defp format_npcs(npcs) when map_size(npcs) == 0, do: "(없음)"

  defp format_npcs(npcs) do
    npcs
    |> Enum.map(fn {name, data} ->
      desc = if data["description"], do: " — #{data["description"]}", else: ""
      "- #{name}#{desc}"
    end)
    |> Enum.join("\n")
  end

  defp format_quests([]), do: "(없음)"

  defp format_quests(quests) do
    quests
    |> Enum.map(fn quest ->
      status = if quest["status"], do: " [#{quest["status"]}]", else: ""
      "- #{quest["name"]}#{status}"
    end)
    |> Enum.join("\n")
  end
end
