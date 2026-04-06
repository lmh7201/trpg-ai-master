defmodule TrpgMaster.Campaign.Summarizer do
  @moduledoc """
  AI를 사용한 캠페인 요약 생성.
  세션 요약, 컨텍스트 요약, 전투 히스토리 요약, 전투 종료 요약을 담당한다.
  Campaign.Server에서 분리된 모듈.
  """

  alias TrpgMaster.AI.{Client, Models}

  require Logger

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  세션 종료 시 전체 세션 요약을 생성한다.
  """
  def generate_session_summary(state) do
    haiku_model = summary_model_for(state.ai_model)

    summary_prompt = """
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

    # 최근 대화 히스토리만 포함 (마지막 20개, 탐험+전투 통합)
    all_history = state.exploration_history ++ state.combat_history
    recent_history = Enum.take(all_history, -20)

    summarize("You are a D&D session scribe.", summary_prompt, recent_history, haiku_model, 1024)
  end

  @doc """
  탐험 중 슬라이딩 윈도우 밖의 히스토리를 요약한다.
  AI 응답만 요약 대상이며, 이전 요약과 통합한다.
  """
  def generate_context_summary(state) do
    history = state.exploration_history

    ai_messages =
      Enum.filter(history, fn %{"role" => role} -> role == "assistant" end)

    if ai_messages == [] do
      :skip
    else
      haiku_model = summary_model_for(state.ai_model)
      previous = state.context_summary || "(첫 번째 턴 — 이전 요약 없음)"

      recent_ai = Enum.take(ai_messages, -5)

      new_exchange =
        recent_ai
        |> Enum.map(fn %{"content" => content} ->
          "DM: #{String.slice(content, 0, 1000)}"
        end)
        |> Enum.join("\n")

      summary_prompt = """
      당신은 TRPG 세션 기록 요약 도우미입니다.
      [중요] 반드시 이전 요약의 핵심 정보를 보존하면서 최근 AI 응답 내용을 통합하세요.

      ## 이전 요약
      #{previous}

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

      summary_messages = [%{"role" => "user", "content" => summary_prompt}]
      summarize("You are a TRPG session summarizer.", nil, summary_messages, haiku_model, 800)
    end
  end

  @doc """
  전투 중 이전 라운드 히스토리를 요약한다.
  누적 방식으로 이전 요약 + 최근 전투 내용을 통합한다.
  """
  def generate_combat_history_summary(state) do
    ai_messages =
      Enum.filter(state.combat_history, fn %{"role" => role} -> role == "assistant" end)

    if ai_messages == [] do
      {:ok, nil}
    else
      haiku_model = summary_model_for(state.ai_model)
      previous = state.combat_history_summary || "(전투 시작 — 이전 요약 없음)"

      recent_ai = Enum.take(ai_messages, -3)

      new_exchange =
        recent_ai
        |> Enum.map(fn %{"content" => content} ->
          "DM: #{String.slice(content, 0, 800)}"
        end)
        |> Enum.join("\n")

      combatants_status = format_combatants_status(state)

      summary_prompt = """
      당신은 TRPG 전투 기록 요약 도우미입니다.
      [중요] 반드시 이전 요약의 핵심 정보를 보존하면서 최근 전투 내용을 통합하세요.

      ## 이전 전투 요약
      #{previous}

      ## 최근 전투 진행 (최대 3건)
      #{new_exchange}

      ## 현재 참가자 상태
      #{combatants_status}

      ## 지시사항
      위 정보를 하나의 간결한 전투 요약으로 통합하세요 (최대 400자).
      반드시 포함할 내용:
      - 각 라운드의 주요 공격/피해
      - 현재 적의 상태 (HP 변화, 사망 여부)
      - 현재 아군의 상태 (HP 변화)
      - 사용된 주요 능력이나 주문
      마크다운 서식을 사용하지 마세요. 순수 텍스트로만 작성하세요.
      """

      summary_messages = [%{"role" => "user", "content" => summary_prompt}]
      summarize("You are a TRPG combat summarizer.", nil, summary_messages, haiku_model, 600)
    end
  end

  @doc """
  전투 종료 후 전체 전투를 요약한다.
  """
  def generate_post_combat_summary(state) do
    ai_messages =
      Enum.filter(state.combat_history, fn %{"role" => role} -> role == "assistant" end)

    if ai_messages == [] do
      {:ok, nil}
    else
      haiku_model = summary_model_for(state.ai_model)

      combat_exchanges =
        ai_messages
        |> Enum.map(fn %{"content" => content} ->
          "DM: #{String.slice(content, 0, 800)}"
        end)
        |> Enum.join("\n")

      combatants_status = format_combatants_status(state)

      summary_prompt = """
      당신은 TRPG 전투 기록 요약 도우미입니다. 전투가 끝났습니다.

      ## 전투 전체 기록
      #{combat_exchanges}

      ## 전투 종료 시 참가자 상태
      #{combatants_status}

      ## 지시사항
      위 전투 전체를 간결하게 요약하세요 (최대 500자).
      반드시 포함할 내용:
      - 전투 참가자 (아군, 적)와 최종 상태 (HP, 사망 여부)
      - 전투의 전개 과정 (주요 전환점)
      - 전투 결과 (승패, 사상자)
      - 획득한 전리품이나 경험치 (언급된 경우)
      마크다운 서식을 사용하지 마세요. 순수 텍스트로만 작성하세요.
      """

      summary_messages = [%{"role" => "user", "content" => summary_prompt}]
      summarize("You are a TRPG combat summarizer.", nil, summary_messages, haiku_model, 800)
    end
  end

  @doc """
  컨텍스트 요약을 갱신한다. state를 받아 갱신된 state를 반환.
  """
  def update_context_summary(state) do
    case generate_context_summary(state) do
      {:ok, new_summary} ->
        if state.context_summary && meaningful_summary?(state.context_summary) do
          TrpgMaster.Campaign.Persistence.append_summary_log(state.id, state.context_summary)
        end

        Logger.info("컨텍스트 요약 갱신 [#{state.id}]")
        %{state | context_summary: new_summary}

      :skip ->
        Logger.info("컨텍스트 요약 스킵 [#{state.id}] — AI 응답 없음")
        state

      {:error, reason} ->
        Logger.warning("컨텍스트 요약 생성 실패 [#{state.id}]: #{inspect(reason)}")
        state
    end
  end

  @doc """
  전투 히스토리 요약을 갱신한다. state를 받아 갱신된 state를 반환.
  """
  def update_combat_history_summary(state) do
    case generate_combat_history_summary(state) do
      {:ok, summary} ->
        Logger.info("전투 히스토리 요약 갱신 [#{state.id}]")
        %{state | combat_history_summary: summary}

      {:error, reason} ->
        Logger.warning("전투 히스토리 요약 생성 실패 [#{state.id}]: #{inspect(reason)}")
        state
    end
  end

  @doc """
  세션 번호를 추정한다 (turn_count 기반).
  """
  def estimate_session_number(state) do
    max(1, div(state.turn_count, 5))
  end

  @doc """
  요약이 의미 있는 내용을 포함하는지 검증한다.
  """
  def meaningful_summary?(text) when is_binary(text) do
    stripped =
      text
      |> String.replace(~r/\d{4}[-\/]\d{1,2}[-\/]\d{1,2}/, "")
      |> String.replace(~r/\d{1,2}:\d{2}(:\d{2})?/, "")
      |> String.replace(~r/[T\-\/:\s.,()]+/, "")
      |> String.replace(~r/첫\s*번째\s*턴/, "")
      |> String.replace("이전 요약 없음", "")
      |> String.trim()

    String.length(stripped) >= 10
  end

  def meaningful_summary?(_), do: false

  # ── Private helpers ────────────────────────────────────────────────────────

  # 공통 AI 요약 호출 패턴
  defp summarize(system_msg, user_prompt, messages, model, max_tokens) do
    messages =
      if user_prompt do
        [%{"role" => "user", "content" => user_prompt} | messages]
      else
        messages
      end

    case Client.chat(system_msg, messages, [], model: model, max_tokens: max_tokens) do
      {:ok, result} -> {:ok, result.text}
      {:error, reason} -> {:error, reason}
    end
  end

  def summary_model_for(nil), do: "claude-haiku-4-5-20251001"
  def summary_model_for(model_id) do
    case Models.provider_for(model_id) do
      :anthropic -> "claude-haiku-4-5-20251001"
      :openai -> "gpt-5.4-mini"
      :gemini -> "gemini-2.5-flash"
      _ -> "claude-haiku-4-5-20251001"
    end
  end

  def format_combatants_status(state) do
    player_names = get_in(state.combat_state, ["player_names"]) || []
    enemies = get_in(state.combat_state, ["enemies"]) || []

    player_lines =
      state.characters
      |> Enum.filter(fn c -> c["name"] in player_names end)
      |> Enum.map(fn c ->
        hp = if c["hp_current"] && c["hp_max"], do: " HP #{c["hp_current"]}/#{c["hp_max"]}", else: ""
        status = if is_number(c["hp_current"]) and c["hp_current"] <= 0, do: " [쓰러짐]", else: ""
        conditions = case c["conditions"] do
          list when is_list(list) and list != [] -> " 상태: #{Enum.join(list, ", ")}"
          _ -> ""
        end
        "- [아군] #{c["name"]}#{hp}#{status}#{conditions}"
      end)

    enemy_lines =
      Enum.map(enemies, fn e ->
        hp = if e["hp_current"] && e["hp_max"], do: " HP #{e["hp_current"]}/#{e["hp_max"]}", else: ""
        status = if is_number(e["hp_current"]) and e["hp_current"] <= 0, do: " [사망]", else: ""
        "- [적] #{e["name"]}#{hp}#{status}"
      end)

    Enum.join(player_lines ++ enemy_lines, "\n")
  end

  def format_characters([]), do: "(없음)"

  def format_characters(characters) do
    characters
    |> Enum.map(fn c ->
      hp = if c["hp_current"] && c["hp_max"], do: " HP #{c["hp_current"]}/#{c["hp_max"]}", else: ""
      "- #{c["name"]}#{hp}"
    end)
    |> Enum.join("\n")
  end

  def format_npcs(npcs) when map_size(npcs) == 0, do: "(없음)"

  def format_npcs(npcs) do
    npcs
    |> Enum.map(fn {name, data} ->
      desc = if data["description"], do: " — #{data["description"]}", else: ""
      "- #{name}#{desc}"
    end)
    |> Enum.join("\n")
  end

  def format_quests([]), do: "(없음)"

  def format_quests(quests) do
    quests
    |> Enum.map(fn q ->
      status = if q["status"], do: " [#{q["status"]}]", else: ""
      "- #{q["name"]}#{status}"
    end)
    |> Enum.join("\n")
  end
end
