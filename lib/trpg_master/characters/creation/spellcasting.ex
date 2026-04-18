defmodule TrpgMaster.Characters.Creation.Spellcasting do
  @moduledoc false

  alias TrpgMaster.Characters.Creation.Abilities
  alias TrpgMaster.Characters.Creation.Definitions
  alias TrpgMaster.Rules.CharacterData

  def prepare_step(assigns, 6) do
    if assigns.is_spellcaster do
      class_id = assigns.selected_class["id"]
      class_en = get_in(assigns.selected_class, ["name", "en"]) || class_id

      %{
        available_cantrips: CharacterData.cantrips_for_class(class_en),
        available_spells: CharacterData.level1_spells_for_class(class_en),
        spell_limit: resolved_spell_limit(assigns),
        selected_cantrips: [],
        selected_spells: []
      }
    else
      %{}
    end
  end

  def prepare_step(_assigns, _step), do: %{}

  def resolved_spell_limit(assigns) do
    class_id = if assigns.selected_class, do: assigns.selected_class["id"], else: nil

    case Definitions.spellcasting_classes()[class_id] do
      %{spells: :wis_mod_plus_level} ->
        wis = Abilities.final_ability_score(assigns, "wis")
        max(1, CharacterData.ability_modifier(wis) + 1)

      %{spells: :int_mod_plus_level} ->
        int = Abilities.final_ability_score(assigns, "int")
        max(1, CharacterData.ability_modifier(int) + 1)

      %{spells: n} when is_integer(n) ->
        n

      _ ->
        assigns.spell_limit
    end
  end
end
