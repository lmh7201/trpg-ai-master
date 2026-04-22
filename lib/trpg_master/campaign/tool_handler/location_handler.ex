defmodule TrpgMaster.Campaign.ToolHandler.LocationHandler do
  @moduledoc """
  `set_location` 도구 결과로 `state.current_location`을 갱신한다.
  """

  alias TrpgMaster.Campaign.ToolHandler.Shared
  require Logger

  def apply(state, input) when is_map(input) do
    case Shared.sanitize_name(input["location_name"]) do
      nil ->
        Logger.warning("[Campaign #{state.id}] set_location: 위치 이름이 비어 있어 무시합니다.")
        state

      location_name ->
        Logger.info("위치 변경: #{state.current_location} → #{location_name}")
        %{state | current_location: location_name}
    end
  end
end
