defmodule TrpgMaster.AI.ToolExecutor.LookupCompactorTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.ToolExecutor.Lookup.Compactor

  test "compact/2 truncates nested rule section content and flattens localized text" do
    entry = %{
      "name" => %{"ko" => "집중", "en" => "Concentration"},
      "sections" => [
        %{
          "id" => "sec-1",
          "title" => %{"ko" => "개요", "en" => "Overview"},
          "content" => [
            %{
              "type" => "list",
              "content" => [
                %{"type" => "text", "text" => "첫째"},
                %{"type" => "text", "text" => "둘째"},
                %{"type" => "text", "text" => "셋째"},
                %{"type" => "text", "text" => "넷째"}
              ]
            }
          ]
        }
      ]
    }

    compacted = Compactor.compact(:rule, entry)

    assert compacted["name"] == "집중"
    assert get_in(compacted, ["sections", Access.at(0), "title"]) == "개요"

    assert get_in(compacted, ["sections", Access.at(0), "content", Access.at(0), "content"]) == [
             %{"type" => "text", "text" => "첫째"},
             %{"type" => "text", "text" => "둘째"},
             %{"type" => "text", "text" => "셋째"},
             %{"type" => "text", "text" => "...(이하 생략)"}
           ]
  end

  test "compact/2 drops spell noise fields and annotates cantrips" do
    spell = %{
      "name" => %{"ko" => "불꽃 화살", "en" => "Fire Bolt"},
      "level" => 0,
      "source" => "SRD",
      "castingTimeDetails" => %{"ko" => "", "en" => ""},
      "isRitual" => false,
      "concentration" => false
    }

    compacted = Compactor.compact(:spell, spell)

    assert compacted["name"] == "불꽃 화살"
    assert compacted["note"] =~ "소마법"
    refute Map.has_key?(compacted, "source")
    refute Map.has_key?(compacted, "castingTimeDetails")
    refute Map.has_key?(compacted, "isRitual")
    refute Map.has_key?(compacted, "concentration")
  end
end
