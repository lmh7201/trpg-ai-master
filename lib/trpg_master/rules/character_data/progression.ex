defmodule TrpgMaster.Rules.CharacterData.Progression do
  @moduledoc false

  alias TrpgMaster.Rules.CharacterData.Progression.{
    Ability,
    Features,
    Levels,
    Spellcasting,
    Subclasses
  }

  defdelegate class_features_for_level(class_id, level), to: Features
  defdelegate class_features_for_levels(class_id, from_level, to_level), to: Features
  defdelegate level_for_xp(xp), to: Levels
  defdelegate xp_for_level(level), to: Levels
  defdelegate proficiency_bonus_for_level(level), to: Levels
  defdelegate parse_hit_die(value), to: Ability
  defdelegate asi_level?(level, class_id), to: Levels
  defdelegate subclass_level?(level, class_id), to: Levels
  defdelegate subclasses_for_class(class_id), to: Subclasses
  defdelegate resolve_subclass_name(class_id, subclass_name), to: Subclasses
  defdelegate resolve_subclass_id(class_id, subclass_name), to: Subclasses
  defdelegate subclass_features_for_level(subclass_id, level), to: Features
  defdelegate subclass_features_for_levels(subclass_id, from_level, to_level), to: Features
  defdelegate spell_slots_for_class_level(class_id, level), to: Spellcasting
  defdelegate cantrips_known_for_class_level(class_id, level), to: Spellcasting
  defdelegate spells_known_for_class_level(class_id, level), to: Spellcasting
  defdelegate ability_modifier(score), to: Ability
end
