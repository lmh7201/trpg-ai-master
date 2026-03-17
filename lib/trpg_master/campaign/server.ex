defmodule TrpgMaster.Campaign.Server do
  @moduledoc """
  캠페인 하나 = GenServer 프로세스 하나.
  플레이어 메시지 처리, 상태 관리, AI 호출을 담당한다.
  크래시 후 재시작 시 Persistence.load로 자동 복원한다.
  """

  use GenServer

  alias TrpgMaster.Campaign.{State, Persistence}
  alias TrpgMaster.AI.{Client, Models, PromptBuilder, Tools}

  require Logger

  @player_action_timeout 180_000

  # ── Public API ──────────────────────────────────────────────────────────────

  def start_link(%State{} = state) do
    GenServer.start_link(__MODULE__, state, name: via(state.id))
  end

  def player_action(campaign_id, message) do
    GenServer.call(via(campaign_id), {:player_action, message}, @player_action_timeout)
  end

  def get_state(campaign_id) do
    GenServer.call(via(campaign_id), :get_state)
  end

  def set_mode(campaign_id, mode) when mode in [:adventure, :debug] do
    GenServer.call(via(campaign_id), {:set_mode, mode})
  end

  def set_model(campaign_id, model_id) do
    GenServer.call(via(campaign_id), {:set_model, model_id})
  end

  def end_session(campaign_id) do
    GenServer.call(via(campaign_id), :end_session, 120_000)
  end

  def alive?(campaign_id) do
    case Registry.lookup(TrpgMaster.Campaign.Registry, campaign_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  # ── GenServer Callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(%State{id: campaign_id} = initial_state) do
    # 크래시 후 재시작 시 Persistence.load로 최신 상태 복원
    case Persistence.load(campaign_id) do
      {:ok, loaded_state} ->
        Logger.info("캠페인 복원: #{loaded_state.name} [#{loaded_state.id}]")
        {:ok, loaded_state}

      {:error, _} ->
        Logger.info("캠페인 서버 시작: #{initial_state.name} [#{initial_state.id}]")
        {:ok, initial_state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:set_mode, mode}, _from, state) do
    new_state = %{state | mode: mode}
    Persistence.save_async(new_state)
    Logger.info("모드 변경 [#{state.id}]: #{state.mode} → #{mode}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_model, model_id}, _from, state) do
    new_state = %{state | ai_model: model_id}
    Persistence.save_async(new_state)
    Logger.info("AI 모델 변경 [#{state.id}]: #{state.ai_model} → #{model_id}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:end_session, _from, state) do
    Logger.info("세션 종료 처리 시작 [#{state.id}] 턴 #{state.turn_count}")

    case generate_session_summary(state) do
      {:ok, summary_text} ->
        # 세션 로그 저장
        session_number = estimate_session_number(state)
        Persistence.append_session_log(state, session_number, summary_text)

        # 대화 히스토리 및 컨텍스트 요약 리셋 (캐릭터/NPC/퀘스트는 유지)
        new_state = %{state | conversation_history: [], context_summary: nil}
        Persistence.save_async(new_state)

        {:reply, {:ok, summary_text}, new_state}

      {:error, reason} ->
        Logger.error("세션 요약 생성 실패 [#{state.id}]: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:player_action, message}, _from, state) do
    history = state.conversation_history ++ [%{"role" => "user", "content" => message}]
    state = %{state | conversation_history: history, turn_count: state.turn_count + 1}

    Logger.info(
      "플레이어 액션 처리 시작 [#{state.id}] 턴 #{state.turn_count} — 히스토리: #{length(history)}개"
    )

    system_prompt = PromptBuilder.build(state)
    tools = Tools.definitions(state.phase) ++ Tools.state_tool_definitions()
    trimmed_history =
      PromptBuilder.build_messages_with_summary(
        message,
        state.context_summary,
        state.conversation_history
      )

    # read_journal 도구가 현재 저널 데이터에 접근할 수 있도록 프로세스 딕셔너리에 저장
    Process.put(:journal_entries, state.journal_entries)

    model_opts =
      case state.ai_model do
        nil -> []
        model_id -> [model: model_id]
      end

    result =
      try do
        Client.chat(system_prompt, trimmed_history, tools, model_opts)
      after
        Process.delete(:journal_entries)
      end

    case result do
      {:ok, result} ->
        state_before = state
        state = apply_tool_results(state, result.tool_results)

        if map_size(state.npcs) != map_size(state_before.npcs) do
          Logger.info(
            "NPC 상태 변경 [#{state.id}]: #{map_size(state_before.npcs)}개 → #{map_size(state.npcs)}개"
          )
        end

        state = %{
          state
          | conversation_history:
              state.conversation_history ++ [%{"role" => "assistant", "content" => result.text}]
        }

        # 컨텍스트 요약 생성 — 매 턴 강제 갱신 (이전 요약 + 최근 AI 응답 5개)
        state =
          case generate_context_summary(state) do
            {:ok, new_summary} ->
              if state.context_summary && meaningful_summary?(state.context_summary) do
                Persistence.append_summary_log(state.id, state.context_summary)
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

        Persistence.save_async(state)

        Logger.info(
          "턴 #{state.turn_count} 저장 완료 [#{state.id}] — npcs: #{map_size(state.npcs)}개, history: #{length(state.conversation_history)}개"
        )

        {:reply, {:ok, result}, state}

      {:error, reason} ->
        Logger.error("AI 호출 실패 [#{state.id}]: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  # ── Private helpers ─────────────────────────────────────────────────────────

  defp via(campaign_id) do
    {:via, Registry, {TrpgMaster.Campaign.Registry, campaign_id}}
  end

  defp estimate_session_number(state) do
    # 기존 로그 파일에서 세션 번호를 추정 (간단하게 turn_count 기반)
    max(1, div(state.turn_count, 5))
  end

  defp generate_session_summary(state) do
    # 현재 캠페인의 프로바이더와 동일한 저비용 모델 사용
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

    # 최근 대화 히스토리만 포함 (마지막 20개)
    recent_history = Enum.take(state.conversation_history, -20)

    case Client.chat(summary_prompt, recent_history, [], model: haiku_model, max_tokens: 1024) do
      {:ok, result} -> {:ok, result.text}
      {:error, reason} -> {:error, reason}
    end
  end

  # 슬라이딩 윈도우 크기 (PromptBuilder와 동일)
  @recent_window_size 5

  defp generate_context_summary(state) do
    history = state.conversation_history

    # AI(assistant) 응답만 필터링 — 유저 채팅은 요약에 포함하지 않음
    ai_messages =
      Enum.filter(history, fn %{"role" => role} -> role == "assistant" end)

    if ai_messages == [] do
      :skip
    else
      haiku_model = summary_model_for(state.ai_model)
      previous = state.context_summary || "(첫 번째 턴 — 이전 요약 없음)"

      # 최근 AI 응답 5개를 이전 요약과 통합
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
      """

      case Client.chat(summary_prompt, [], [], model: haiku_model, max_tokens: 512) do
        {:ok, result} -> {:ok, result.text}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # 시간/날짜 정보만 있고 실제 내용이 없는 요약을 필터링
  defp meaningful_summary?(text) when is_binary(text) do
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

  defp meaningful_summary?(_), do: false

  defp format_characters([]), do: "(없음)"

  defp format_characters(characters) do
    characters
    |> Enum.map(fn c ->
      hp = if c["hp_current"] && c["hp_max"], do: " HP #{c["hp_current"]}/#{c["hp_max"]}", else: ""
      "- #{c["name"]}#{hp}"
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
    |> Enum.map(fn q ->
      status = if q["status"], do: " [#{q["status"]}]", else: ""
      "- #{q["name"]}#{status}"
    end)
    |> Enum.join("\n")
  end

  # 현재 선택된 모델의 프로바이더에 맞는 요약 모델 반환
  defp summary_model_for(nil), do: "claude-haiku-4-5-20251001"
  defp summary_model_for(model_id) do
    case Models.provider_for(model_id) do
      :anthropic -> "claude-haiku-4-5-20251001"
      :openai -> "gpt-5-mini"
      :gemini -> "gemini-2.5-flash"
      _ -> "claude-haiku-4-5-20251001"
    end
  end

  # 도구 결과 리스트를 순회하며 캠페인 상태에 반영한다.
  # 각 도구별로 apply_single_tool_result/2를 호출하여 캐릭터, NPC, 퀘스트, 위치, 전투 상태를 갱신.
  defp apply_tool_results(state, tool_results) do
    Enum.reduce(tool_results, state, fn result, acc ->
      apply_single_tool_result(acc, result)
    end)
  end

  defp apply_single_tool_result(state, %{tool: "update_character", input: input}) do
    char_name = input["character_name"]
    changes = input["changes"] || %{}

    Logger.info("캐릭터 업데이트: #{char_name} — #{inspect(changes)}")

    characters =
      case Enum.find_index(state.characters, &(&1["name"] == char_name)) do
        nil ->
          Logger.info("새 캐릭터 생성: #{char_name}")
          [Map.merge(%{"name" => char_name}, changes) | state.characters]

        idx ->
          List.update_at(state.characters, idx, fn char ->
            apply_character_changes(char, changes)
          end)
      end

    %{state | characters: characters}
  end

  defp apply_single_tool_result(state, %{tool: "register_npc", input: input}) do
    name = input["name"]
    Logger.info("NPC 등록: #{name}")

    npc_data =
      Map.merge(
        Map.get(state.npcs, name, %{}),
        input |> Map.drop(["name"]) |> Map.reject(fn {_k, v} -> is_nil(v) end)
      )
      |> Map.put("name", name)

    %{state | npcs: Map.put(state.npcs, name, npc_data)}
  end

  defp apply_single_tool_result(state, %{tool: "update_quest", input: input}) do
    quest_name = input["quest_name"]

    quests =
      case Enum.find_index(state.active_quests, &(&1["name"] == quest_name)) do
        nil ->
          state.active_quests ++
            [
              %{
                "name" => quest_name,
                "status" => input["status"] || "발견",
                "description" => input["description"],
                "notes" => input["notes"]
              }
            ]

        idx ->
          List.update_at(state.active_quests, idx, fn quest ->
            quest
            |> maybe_put("status", input["status"])
            |> maybe_put("description", input["description"])
            |> maybe_put("notes", input["notes"])
          end)
      end

    %{state | active_quests: quests}
  end

  defp apply_single_tool_result(state, %{tool: "set_location", input: input}) do
    Logger.info("위치 변경: #{state.current_location} → #{input["location_name"]}")
    %{state | current_location: input["location_name"]}
  end

  defp apply_single_tool_result(state, %{tool: "start_combat", input: input}) do
    if state.combat_state do
      Logger.warning("[Campaign #{state.id}] 기존 전투가 진행 중인데 새 전투가 시작됨. 기존 전투를 덮어씁니다.")
    end

    participants = input["participants"] || []
    enemies = input["enemies"]
    Logger.info("전투 시작: #{Enum.join(participants, ", ")}")

    combat = %{
      "participants" => participants,
      "round" => 1,
      "turn_order" => []
    }

    combat =
      if is_list(enemies) && enemies != [] do
        Map.put(combat, "enemies", enemies)
      else
        combat
      end

    %{state | phase: :combat, combat_state: combat}
  end

  defp apply_single_tool_result(state, %{tool: "end_combat", input: _input}) do
    Logger.info("전투 종료")
    %{state | phase: :exploration, combat_state: nil}
  end

  @max_journal_entries 100

  defp apply_single_tool_result(state, %{tool: "write_journal", input: input}) do
    entry_text = input["entry"]
    category = input["category"] || "note"

    entry = %{
      "text" => entry_text,
      "category" => category,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Logger.info("저널 기록 [#{state.id}] [#{category}]: #{String.slice(entry_text, 0, 50)}...")

    entries = (state.journal_entries ++ [entry]) |> Enum.take(-@max_journal_entries)
    %{state | journal_entries: entries}
  end

  defp apply_single_tool_result(state, %{tool: "read_journal", input: _input}) do
    # read_journal은 Tools.execute에서 프로세스 딕셔너리로 처리하므로 상태 변경 없음
    state
  end

  defp apply_single_tool_result(state, result) do
    Logger.debug("알 수 없는 도구 결과 무시: #{inspect(result.tool)}")
    state
  end

  # 캐릭터 맵에 변경사항을 적용한다.
  # 지원 필드: hp_current, hp_max, class, level, ac, spell_slots_used, race, inventory
  # 리스트 필드: inventory_add/remove, conditions_add/remove
  defp apply_character_changes(char, changes) do
    char
    |> maybe_put("hp_current", changes["hp_current"])
    |> maybe_put("hp_max", changes["hp_max"])
    |> maybe_put("class", changes["class"])
    |> maybe_put("level", changes["level"])
    |> maybe_put("ac", changes["ac"])
    |> maybe_put("spell_slots_used", changes["spell_slots_used"])
    |> maybe_put("race", changes["race"])
    |> maybe_put("inventory", changes["inventory"])
    |> apply_list_change("inventory", changes["inventory_add"], changes["inventory_remove"])
    |> apply_list_change("conditions", changes["conditions_add"], changes["conditions_remove"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp apply_list_change(map, key, add, remove) do
    current = Map.get(map, key, [])
    current = if is_list(add), do: current ++ add, else: current
    current = if is_list(remove), do: current -- remove, else: current
    Map.put(map, key, current)
  end
end
