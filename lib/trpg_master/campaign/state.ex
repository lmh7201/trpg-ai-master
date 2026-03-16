defmodule TrpgMaster.Campaign.State do
  @moduledoc """
  캠페인의 전체 상태를 담는 구조체.
  """

  defstruct [
    :id,
    :name,
    phase: :exploration,
    characters: [],
    npcs: %{},
    current_location: nil,
    active_quests: [],
    combat_state: nil,
    conversation_history: [],
    turn_count: 0,
    mode: :adventure,
    journal_entries: [],
    ai_model: nil
  ]

  @doc """
  State 구조체를 직렬화 가능한 맵으로 변환한다.
  character_names, npc_names 포함: 히스토리 트리밍 후에도 AI가 시스템 프롬프트에서 파악 가능.
  """
  def to_summary(%__MODULE__{} = state) do
    %{
      "id" => state.id,
      "name" => state.name,
      "phase" => to_string(state.phase),
      "current_location" => state.current_location,
      "active_quests" => state.active_quests,
      "turn_count" => state.turn_count,
      "mode" => to_string(state.mode),
      "combat_state" => state.combat_state,
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "character_names" => state.characters |> Enum.map(& &1["name"]) |> Enum.reject(&is_nil/1),
      "npc_names" => Map.keys(state.npcs),
      "journal_count" => length(state.journal_entries),
      "ai_model" => state.ai_model
    }
  end

  @doc """
  summary 맵에서 State 구조체를 복원한다.
  characters, npcs, conversation_history는 별도로 로드한다.
  """
  def from_summary(summary) do
    %__MODULE__{
      id: summary["id"],
      name: summary["name"],
      phase: safe_atom(summary["phase"], :exploration),
      current_location: summary["current_location"],
      active_quests: summary["active_quests"] || [],
      turn_count: summary["turn_count"] || 0,
      mode: safe_atom(summary["mode"], :adventure),
      combat_state: summary["combat_state"],
      ai_model: summary["ai_model"]
      # journal_entries는 Persistence.load에서 별도로 로드한다
    }
  end

  defp safe_atom(nil, default), do: default
  defp safe_atom(value, _default) when is_atom(value), do: value

  defp safe_atom(value, default) when is_binary(value) do
    case value do
      "exploration" -> :exploration
      "combat" -> :combat
      "dialogue" -> :dialogue
      "rest" -> :rest
      "adventure" -> :adventure
      "debug" -> :debug
      _ -> default
    end
  end
end
