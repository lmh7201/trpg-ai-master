defmodule TrpgMaster.AI.ToolsTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.Tools

  test "execute/2 rolls a die and returns formatted result" do
    assert {:ok, result} = Tools.execute("roll_dice", %{"notation" => "1d20+3", "label" => "공격"})
    assert result["notation"] == "1d20+3"
    assert result["label"] == "공격"
    assert is_integer(result["total"])
    assert is_binary(result["formatted"])
  end

  test "execute/2 reads character info from process context" do
    Process.put(:campaign_characters, [
      %{
        "name" => "엘라라",
        "class" => "위저드",
        "race" => "엘프",
        "background" => "현자",
        "alignment" => "중립 선",
        "level" => 1,
        "hp_max" => 8,
        "hp_current" => 8,
        "ac" => 12,
        "speed" => 30
      }
    ])

    on_exit(fn -> Process.delete(:campaign_characters) end)

    assert {:ok, %{"status" => "ok", "character" => summary}} =
             Tools.execute("get_character_info", %{"category" => "summary"})

    assert summary["name"] == "엘라라"
    assert summary["alignment"] == "중립 선"
  end

  test "execute/2 filters journal entries by category" do
    Process.put(:journal_entries, [
      %{"category" => "plot", "text" => "숨겨진 문양"},
      %{"category" => "combat", "text" => "고블린과의 전투"}
    ])

    on_exit(fn -> Process.delete(:journal_entries) end)

    assert {:ok, %{"status" => "ok", "entries" => entries, "total" => 1}} =
             Tools.execute("read_journal", %{"category" => "plot"})

    assert entries == [%{"category" => "plot", "text" => "숨겨진 문양"}]
  end

  test "execute/2 searches monsters through the lookup executor" do
    assert {:ok, %{"count" => count, "monsters" => monsters, "tip" => tip}} =
             Tools.execute("search_monsters", %{"limit" => 3})

    assert count <= 3
    assert is_list(monsters)
    assert count == length(monsters)
    assert tip =~ "lookup_monster"
  end

  test "execute/2 returns an error for unknown tools" do
    assert {:error, "알 수 없는 도구: nope"} = Tools.execute("nope", %{})
  end
end
