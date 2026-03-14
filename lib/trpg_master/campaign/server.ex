defmodule TrpgMaster.Campaign.Server do
  @moduledoc """
  캠페인 하나 = GenServer 프로세스 하나.
  플레이어 메시지 처리, 상태 관리, AI 호출을 담당한다.
  크래시 후 재시작 시 Persistence.load로 자동 복원한다.
  """

  use GenServer

  alias TrpgMaster.Campaign.{State, Persistence}
  alias TrpgMaster.AI.{Client, PromptBuilder, Tools}

  require Logger

  # ── Public API ──────────────────────────────────────────────────────────────

  def start_link(%State{} = state) do
    GenServer.start_link(__MODULE__, state, name: via(state.id))
  end

  def player_action(campaign_id, message) do
    GenServer.call(via(campaign_id), {:player_action, message}, 180_000)
  end

  def get_state(campaign_id) do
    GenServer.call(via(campaign_id), :get_state)
  end

  def set_mode(campaign_id, mode) when mode in [:adventure, :debug] do
    GenServer.call(via(campaign_id), {:set_mode, mode})
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
  def handle_call(:end_session, _from, state) do
    Logger.info("세션 종료 처리 시작 [#{state.id}] 턴 #{state.turn_count}")

    case generate_session_summary(state) do
      {:ok, summary_text} ->
        # 세션 로그 저장
        session_number = div(state.turn_count, 1) |> then(fn _ -> estimate_session_number(state) end)
        Persistence.append_session_log(state, session_number, summary_text)

        # 대화 히스토리 리셋 (캐릭터/NPC/퀘스트는 유지)
        new_state = %{state | conversation_history: []}
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
    tools = Tools.definitions() ++ Tools.state_tool_definitions()
    trimmed_history = PromptBuilder.build_messages(history)

    # read_journal 도구가 현재 저널 데이터에 접근할 수 있도록 프로세스 딕셔너리에 저장
    Process.put(:journal_entries, state.journal_entries)

    case Client.chat(system_prompt, trimmed_history, tools) do
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
    # 비용 절약을 위해 Haiku 모델 사용
    haiku_model = "claude-haiku-4-5-20251001"

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
    participants = input["participants"] || []
    Logger.info("전투 시작: #{Enum.join(participants, ", ")}")

    combat = %{
      "participants" => participants,
      "round" => 1,
      "turn_order" => []
    }

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
