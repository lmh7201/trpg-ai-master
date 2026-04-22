defmodule TrpgMaster.Campaign.ToolHandler.QuestHandler do
  @moduledoc """
  `update_quest` 도구 결과를 `state.active_quests`에 반영한다.
  """

  alias TrpgMaster.Campaign.ToolHandler.Shared
  require Logger

  @doc """
  동일한 이름의 퀘스트가 있으면 필드를 머지해 갱신하고, 없으면 새로 추가한다.
  """
  def apply(state, input) when is_map(input) do
    case Shared.sanitize_name(input["quest_name"]) do
      nil ->
        Logger.warning("[Campaign #{state.id}] update_quest: 퀘스트 이름이 비어 있어 무시합니다.")
        state

      quest_name ->
        quests =
          case Enum.find_index(state.active_quests, &(&1["name"] == quest_name)) do
            nil -> append_quest(state.active_quests, quest_name, input)
            idx -> update_quest(state.active_quests, idx, input)
          end

        %{state | active_quests: quests}
    end
  end

  defp append_quest(quests, quest_name, input) do
    quests ++
      [
        %{
          "name" => quest_name,
          "status" => input["status"] || "발견",
          "description" => input["description"],
          "notes" => input["notes"]
        }
      ]
  end

  defp update_quest(quests, idx, input) do
    List.update_at(quests, idx, fn quest ->
      quest
      |> Shared.maybe_put("status", input["status"])
      |> Shared.maybe_put("description", input["description"])
      |> Shared.maybe_put("notes", input["notes"])
    end)
  end
end
