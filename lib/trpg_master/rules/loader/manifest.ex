defmodule TrpgMaster.Rules.Loader.Manifest do
  @moduledoc false

  @data_files [
    %{filename: "spells.json", type: :spell, name_style: :name_object, list_key: nil},
    %{filename: "monsters.json", type: :monster, name_style: :name_object, list_key: nil},
    %{filename: "classes.json", type: :class, name_style: :name_object, list_key: nil},
    %{filename: "feats.json", type: :feat, name_style: :name_object, list_key: nil},
    %{filename: "items.json", type: :item, name_style: :name_object, list_key: nil},
    %{filename: "weapons.json", type: :item, name_style: :name_object, list_key: nil},
    %{filename: "armor.json", type: :item, name_style: :name_object, list_key: nil},
    %{filename: "adventuringGear.json", type: :item, name_style: :name_object, list_key: "gear"}
  ]

  @rule_files [
    "rules/combat.json",
    "rules/conditions.json",
    "rules/actions.json",
    "rules/damage-and-healing.json",
    "rules/d20-tests.json",
    "rules/abilities.json",
    "rules/exploration.json",
    "rules/proficiency.json",
    "rules/social-interaction.json",
    "rules/spellcasting.json"
  ]

  @github_raw_base "https://raw.githubusercontent.com/lmh7201/dnd_reference_ko/main/dnd_korean/dnd-reference/src/data"

  def data_files, do: @data_files
  def rule_files, do: @rule_files
  def github_raw_base, do: @github_raw_base
  def rules_dir, do: Application.app_dir(:trpg_master, "priv/rules")

  def status_types do
    @data_files
    |> Enum.map(& &1.type)
    |> Enum.uniq()
  end
end
