defmodule TrpgMaster.Campaign.ToolHandler.NpcHandler do
  @moduledoc """
  `register_npc` 도구 결과를 캠페인 상태에 반영한다.
  """

  alias TrpgMaster.Campaign.ToolHandler.Shared
  require Logger

  @doc """
  NPC 이름을 키로 기존 값과 병합해 `state.npcs`에 저장한다.
  이름이 비어 있으면 state를 그대로 돌려준다.
  """
  def apply(state, input) when is_map(input) do
    case Shared.sanitize_name(input["name"]) do
      nil ->
        Logger.warning("[Campaign #{state.id}] register_npc: 이름이 비어 있어 무시합니다.")
        state

      name ->
        Logger.info("NPC 등록: #{name}")

        npc_data =
          Map.merge(
            Map.get(state.npcs, name, %{}),
            input |> Map.drop(["name"]) |> Map.reject(fn {_k, v} -> is_nil(v) end)
          )
          |> Map.put("name", name)

        %{state | npcs: Map.put(state.npcs, name, npc_data)}
    end
  end
end
