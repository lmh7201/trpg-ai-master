defmodule TrpgMaster.Campaign.Server do
  @moduledoc """
  캠페인 하나 = GenServer 프로세스 하나.
  플레이어 메시지 처리, 상태 관리, AI 호출을 담당한다.
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

  def alive?(campaign_id) do
    case Registry.lookup(TrpgMaster.Campaign.Registry, campaign_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  # ── GenServer Callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(%State{} = state) do
    Logger.info("캠페인 서버 시작: #{state.name} [#{state.id}]")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:player_action, message}, _from, state) do
    # 1. Add player message to conversation history
    history = state.conversation_history ++ [%{"role" => "user", "content" => message}]
    state = %{state | conversation_history: history, turn_count: state.turn_count + 1}

    Logger.info(
      "플레이어 액션 처리 시작 [#{state.id}] 턴 #{state.turn_count} — 히스토리: #{length(history)}개"
    )

    # 2. Build system prompt with campaign context
    system_prompt = PromptBuilder.build(state)

    # 3. Build tools list (existing + state-change tools)
    tools = Tools.definitions() ++ Tools.state_tool_definitions()

    # 4. Call AI (trim history for token budget)
    trimmed_history = PromptBuilder.build_messages(history)

    case Client.chat(system_prompt, trimmed_history, tools) do
      {:ok, result} ->
        # 5. Process state-change tool results
        state_before = state
        state = apply_tool_results(state, result.tool_results)

        if map_size(state.npcs) != map_size(state_before.npcs) do
          Logger.info(
            "NPC 상태 변경 [#{state.id}]: #{map_size(state_before.npcs)}개 → #{map_size(state.npcs)}개 (#{Map.keys(state.npcs) |> Enum.join(", ")})"
          )
        end

        if length(state.characters) != length(state_before.characters) do
          Logger.info(
            "캐릭터 상태 변경 [#{state.id}]: #{length(state_before.characters)}개 → #{length(state.characters)}개"
          )
        end

        # 6. Add assistant response to conversation history
        state = %{
          state
          | conversation_history:
              state.conversation_history ++ [%{"role" => "assistant", "content" => result.text}]
        }

        # 7. Save async with updated state
        Persistence.save_async(state)

        Logger.info(
          "턴 #{state.turn_count} 저장 완료 [#{state.id}] — npcs: #{map_size(state.npcs)}개, characters: #{length(state.characters)}개, history: #{length(state.conversation_history)}개"
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
          # Character doesn't exist, create it
          Logger.info("새 캐릭터 생성: #{char_name}")
          [Map.merge(%{"name" => char_name}, changes) | state.characters]

        idx ->
          List.update_at(state.characters, idx, fn char ->
            char
            |> apply_character_changes(changes)
          end)
      end

    %{state | characters: characters}
  end

  defp apply_single_tool_result(state, %{tool: "register_npc", input: input}) do
    name = input["name"]

    Logger.info("NPC 등록: #{name} — #{inspect(input |> Map.drop(["name"]))}")

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

    current =
      if is_list(add), do: current ++ add, else: current

    current =
      if is_list(remove), do: current -- remove, else: current

    Map.put(map, key, current)
  end
end
