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

    # 2. Build system prompt with campaign context
    system_prompt = PromptBuilder.build(state)

    # 3. Build tools list (existing + state-change tools)
    tools = Tools.definitions() ++ Tools.state_tool_definitions()

    # 4. Call AI (trim history for token budget)
    trimmed_history = PromptBuilder.trim_history(history)

    case Client.chat(system_prompt, trimmed_history, tools) do
      {:ok, result} ->
        # 5. Process state-change tool results
        state = apply_tool_results(state, result.tool_results)

        # 6. Add assistant response to conversation history
        state = %{
          state
          | conversation_history:
              state.conversation_history ++ [%{"role" => "assistant", "content" => result.text}]
        }

        # 7. Save async
        Persistence.save_async(state)

        {:reply, {:ok, result}, state}

      {:error, reason} ->
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

    characters =
      case Enum.find_index(state.characters, &(&1["name"] == char_name)) do
        nil ->
          # Character doesn't exist, create it
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
    %{state | current_location: input["location_name"]}
  end

  defp apply_single_tool_result(state, %{tool: "start_combat", input: input}) do
    combat = %{
      "participants" => input["participants"] || [],
      "round" => 1,
      "turn_order" => []
    }

    %{state | phase: :combat, combat_state: combat}
  end

  defp apply_single_tool_result(state, %{tool: "end_combat", input: _input}) do
    %{state | phase: :exploration, combat_state: nil}
  end

  defp apply_single_tool_result(state, _result), do: state

  defp apply_character_changes(char, changes) do
    char
    |> maybe_put("hp_current", changes["hp_current"])
    |> maybe_put("hp_max", changes["hp_max"])
    |> maybe_put("class", changes["class"])
    |> maybe_put("level", changes["level"])
    |> maybe_put("ac", changes["ac"])
    |> maybe_put("spell_slots_used", changes["spell_slots_used"])
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
