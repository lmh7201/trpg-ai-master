defmodule TrpgMaster.Rules.Loader.IndexerTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Rules.Loader.Indexer

  test "extract_list/2 supports list and keyed map payloads" do
    assert Indexer.extract_list([%{"id" => "a"}], nil) == [%{"id" => "a"}]
    assert Indexer.extract_list(%{"gear" => [%{"id" => "rope"}]}, "gear") == [%{"id" => "rope"}]
    assert Indexer.extract_list(%{"gear" => %{}}, "gear") == []
  end

  test "insert_entries/4 indexes korean and english names" do
    table = :ets.new(:loader_entries_test, [:set, :public])

    entry = %{"id" => "fireball", "name" => %{"ko" => "화염구", "en" => "Fireball"}}

    assert Indexer.insert_entries(table, :spell, :name_object, [entry]) == 1

    assert :ets.lookup(table, {:spell, Indexer.normalize("화염구")}) ==
             [{{:spell, "화염구"}, entry}]

    assert :ets.lookup(table, {:spell, Indexer.normalize("Fireball")}) ==
             [{{:spell, "fireball"}, entry}]
  end

  test "insert_rule_document/2 indexes document, section, and subsection titles" do
    table = :ets.new(:loader_rules_test, [:set, :public])

    document = %{
      "id" => "combat",
      "title" => %{"ko" => "전투", "en" => "Combat"},
      "sections" => [
        %{
          "id" => "turn-order",
          "title" => %{"ko" => "순서", "en" => "Turn Order"},
          "content" => [
            %{
              "type" => "subsection",
              "id" => "initiative",
              "title" => %{"ko" => "주도권", "en" => "Initiative"},
              "content" => []
            }
          ]
        }
      ]
    }

    assert Indexer.insert_rule_document(table, document) == 7

    assert :ets.lookup(table, {:rule, "combat"}) != []
    assert :ets.lookup(table, {:rule, "전투"}) != []
    assert :ets.lookup(table, {:rule, "turn-order"}) != []
    assert :ets.lookup(table, {:rule, "turn order"}) != []
    assert :ets.lookup(table, {:rule, "initiative"}) != []
    assert :ets.lookup(table, {:rule, "주도권"}) != []
  end
end
