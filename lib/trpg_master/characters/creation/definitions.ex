defmodule TrpgMaster.Characters.Creation.Definitions do
  @moduledoc false

  @steps [
    {1, "클래스", "class"},
    {2, "종족", "race"},
    {3, "배경", "background"},
    {4, "능력치", "abilities"},
    {5, "장비", "equipment"},
    {6, "주문", "spells"},
    {7, "완성", "summary"}
  ]

  @standard_array [15, 14, 13, 12, 10, 8]

  @ability_keys ["str", "dex", "con", "int", "wis", "cha"]
  @ability_names %{
    "str" => "근력",
    "dex" => "민첩",
    "con" => "건강",
    "int" => "지능",
    "wis" => "지혜",
    "cha" => "매력"
  }

  @spellcasting_classes %{
    "bard" => %{cantrips: 2, spells: 4},
    "cleric" => %{cantrips: 3, spells: :wis_mod_plus_level},
    "druid" => %{cantrips: 2, spells: :wis_mod_plus_level},
    "ranger" => %{cantrips: 0, spells: 2},
    "sorcerer" => %{cantrips: 4, spells: 2},
    "warlock" => %{cantrips: 2, spells: 2},
    "wizard" => %{cantrips: 3, spells: 6}
  }

  def steps, do: @steps
  def standard_array, do: @standard_array
  def ability_keys, do: @ability_keys
  def ability_names, do: @ability_names
  def spellcasting_classes, do: @spellcasting_classes

  def spellcasting_info(class_id) do
    Map.get(@spellcasting_classes, class_id, %{cantrips: 0, spells: 0})
  end

  def spellcasting_class?(class_id) do
    Map.has_key?(@spellcasting_classes, class_id)
  end
end
