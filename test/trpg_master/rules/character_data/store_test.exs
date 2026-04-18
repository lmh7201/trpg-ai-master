defmodule TrpgMaster.Rules.CharacterData.StoreTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Rules.CharacterData.Store

  test "merge_data/2 appends list data" do
    assert Store.merge_data([1, 2], [3, 4]) == [1, 2, 3, 4]
  end

  test "merge_data/2 merges map data" do
    assert Store.merge_data(%{"a" => 1}, %{"b" => 2}) == %{"a" => 1, "b" => 2}
  end

  test "data_count/1 returns counts for lists and maps" do
    assert Store.data_count([1, 2, 3]) == 3
    assert Store.data_count(%{"a" => 1, "b" => 2}) == 2
    assert Store.data_count("nope") == 0
  end
end
