defmodule TrpgMaster.AI.ToolDefinitionsTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.ToolDefinitions

  test "definitions/1 returns the expected exploration tools in order" do
    assert tool_names(ToolDefinitions.definitions(:exploration)) == [
             "roll_dice",
             "lookup_spell",
             "lookup_monster",
             "search_monsters",
             "lookup_class",
             "lookup_item",
             "consult_oracle",
             "list_oracles",
             "lookup_dc",
             "lookup_rule",
             "level_up"
           ]
  end

  test "definitions/1 returns the expected combat tools in order" do
    assert tool_names(ToolDefinitions.definitions(:combat)) == [
             "roll_dice",
             "lookup_monster",
             "lookup_spell",
             "lookup_item",
             "lookup_rule",
             "lookup_dc",
             "level_up"
           ]
  end

  test "state_tool_definitions/0 returns state mutation tools in order" do
    assert tool_names(ToolDefinitions.state_tool_definitions()) == [
             "get_character_info",
             "update_character",
             "register_npc",
             "update_quest",
             "set_location",
             "start_combat",
             "end_combat",
             "write_journal",
             "read_journal"
           ]
  end

  defp tool_names(definitions), do: Enum.map(definitions, & &1.name)
end
