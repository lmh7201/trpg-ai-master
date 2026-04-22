defmodule TrpgMaster.Campaign.ToolHandler.Shared do
  @moduledoc """
  도구별 handler에서 공통으로 쓰는 작은 helper 모음.
  """

  @doc """
  nil, 비문자열, 공백만 있는 문자열은 모두 `nil`로 정규화한다.
  """
  @spec sanitize_name(term()) :: String.t() | nil
  def sanitize_name(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def sanitize_name(_), do: nil

  @doc """
  값이 `nil`이 아니면 `map`에 `key`로 넣는다.
  """
  @spec maybe_put(map(), String.t() | atom(), term()) :: map()
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)
end
