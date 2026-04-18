defmodule TrpgMaster.Rules.CharacterData.Store do
  @moduledoc false

  @table :character_data

  def init_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
        :ok

      _table ->
        :ok
    end
  end

  def get(key, default) do
    case :ets.whereis(@table) do
      :undefined ->
        default

      _table ->
        case :ets.lookup(@table, key) do
          [{^key, value}] -> value
          [] -> default
        end
    end
  end

  def replace(key, data) do
    init_table()
    :ets.insert(@table, {key, data})
    data
  end

  def merge(key, new_data) do
    data = merge_data(get(key, nil), new_data)
    replace(key, data)
  end

  def merge_data(nil, new_data), do: new_data

  def merge_data(existing, new_data) when is_list(existing) and is_list(new_data),
    do: existing ++ new_data

  def merge_data(existing, new_data) when is_map(existing) and is_map(new_data),
    do: Map.merge(existing, new_data)

  def merge_data(_existing, new_data), do: new_data

  def data_count(data) when is_list(data), do: length(data)
  def data_count(data) when is_map(data), do: map_size(data)
  def data_count(_), do: 0
end
