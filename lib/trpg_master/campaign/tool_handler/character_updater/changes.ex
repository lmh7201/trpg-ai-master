defmodule TrpgMaster.Campaign.ToolHandler.CharacterUpdater.Changes do
  @moduledoc false

  def apply_character_changes(char, changes) do
    char
    |> maybe_put("hp_current", changes["hp_current"])
    |> maybe_put("hp_max", changes["hp_max"])
    |> maybe_put("class", changes["class"])
    |> maybe_put("level", changes["level"])
    |> maybe_put("xp", changes["xp"])
    |> maybe_put("ac", changes["ac"])
    |> maybe_put("spell_slots", changes["spell_slots"])
    |> merge_spell_slots_used(changes["spell_slots_used"])
    |> maybe_put("race", changes["race"])
    |> maybe_put("inventory", changes["inventory"])
    |> maybe_put("proficiency_bonus", changes["proficiency_bonus"])
    |> maybe_put("abilities", changes["abilities"])
    |> maybe_put("ability_modifiers", changes["ability_modifiers"])
    |> apply_list_change("inventory", changes["inventory_add"], changes["inventory_remove"])
    |> apply_list_change("conditions", changes["conditions_add"], changes["conditions_remove"])
  end

  def sync_enemy_hp_to_combat_state(%{combat_state: nil} = state, _name, _changes), do: state

  def sync_enemy_hp_to_combat_state(state, char_name, changes) do
    enemies = get_in(state.combat_state, ["enemies"]) || []
    hp_current = changes["hp_current"]
    normalized = char_name |> String.trim() |> String.downcase()

    match? = fn enemy ->
      (enemy["name"] || "") |> String.trim() |> String.downcase() == normalized
    end

    if hp_current && Enum.any?(enemies, match?) do
      updated_enemies =
        Enum.map(enemies, fn enemy ->
          if match?.(enemy) do
            enemy
            |> Map.put("hp_current", hp_current)
            |> then(fn updated ->
              if changes["hp_max"],
                do: Map.put(updated, "hp_max", changes["hp_max"]),
                else: updated
            end)
          else
            enemy
          end
        end)

      put_in(state.combat_state["enemies"], updated_enemies)
    else
      state
    end
  end

  def find_character_index(characters, name) when is_binary(name) do
    normalized = name |> String.trim() |> String.downcase()

    Enum.find_index(characters, fn character ->
      (character["name"] || "") |> String.trim() |> String.downcase() == normalized
    end)
  end

  def find_character_index(_characters, _name), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp apply_list_change(map, key, add, remove) do
    current = Map.get(map, key, [])
    current = if is_list(add), do: current ++ add, else: current
    current = if is_list(remove), do: current -- remove, else: current
    Map.put(map, key, current)
  end

  defp merge_spell_slots_used(char, nil), do: char

  defp merge_spell_slots_used(char, new_used) when is_map(new_used) do
    current = char["spell_slots_used"] || %{}
    merged = Map.merge(current, new_used)

    char
    |> Map.put("spell_slots_used", merged)
    |> validate_spell_slots_used()
  end

  defp validate_spell_slots_used(char) do
    slots = char["spell_slots"] || %{}
    used = char["spell_slots_used"] || %{}

    validated =
      Map.new(used, fn {level, count} ->
        max_slots = slots[level] || 0
        {level, min(count, max_slots)}
      end)

    Map.put(char, "spell_slots_used", validated)
  end
end
