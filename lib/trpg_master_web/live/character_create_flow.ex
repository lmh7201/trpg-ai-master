defmodule TrpgMasterWeb.CharacterCreateFlow do
  @moduledoc """
  CharacterCreateLive의 화면 상태 전이와 위저드 입력 갱신을 담당한다.
  """

  alias TrpgMaster.Characters.Creation

  def mount_assigns(campaign_id, classes, races, backgrounds) do
    Creation.initial_state(classes, races, backgrounds)
    |> Map.put(:campaign_id, campaign_id)
  end

  def select_class(class), do: Creation.class_selection(class)

  def toggle_class_skill(assigns, skill) do
    %{class_skills: toggle_limited(assigns.class_skills, skill, assigns.class_skill_count)}
  end

  def select_race(race), do: %{selected_race: race, detail_panel: nil}

  def select_background(background), do: Creation.background_selection(background)

  def set_bg_ability(assigns, "2", key) do
    new_key = if assigns.bg_ability_2 == key, do: nil, else: key
    %{bg_ability_2: new_key, bg_ability_1: []}
  end

  def set_bg_ability(assigns, "1", key) do
    %{
      bg_ability_1: toggle_limited(assigns.bg_ability_1, key, 2),
      bg_ability_2: nil
    }
  end

  def set_bg_ability(_assigns, _rank, _key), do: %{}

  def set_ability_method(method), do: Creation.ability_method_updates(method)

  def assign_ability(assigns, key, score_str) do
    case Integer.parse(score_str) do
      {value, _} -> {:ok, Creation.assign_ability(assigns, key, value)}
      :error -> :ignore
    end
  end

  def clear_ability(assigns, key), do: Creation.clear_ability(assigns, key)

  def roll_abilities, do: Creation.roll_abilities()

  def set_class_equip(choice), do: %{class_equip_choice: choice}

  def set_bg_equip(choice), do: %{bg_equip_choice: choice}

  def toggle_cantrip(assigns, spell_id) do
    %{
      selected_cantrips:
        toggle_limited(assigns.selected_cantrips, spell_id, assigns.cantrip_limit)
    }
  end

  def toggle_spell(assigns, spell_id) do
    limit = Creation.resolved_spell_limit(assigns)
    %{selected_spells: toggle_limited(assigns.selected_spells, spell_id, limit)}
  end

  def set_name(name), do: %{character_name: String.trim(name)}

  def set_alignment(alignment), do: %{alignment: alignment}

  def set_appearance(value), do: %{appearance: value}

  def set_backstory(value), do: %{backstory: value}

  def show_detail(type, id), do: %{detail_panel: %{type: type, id: id}}

  def close_detail, do: %{detail_panel: nil}

  def next_step(assigns) do
    case Creation.validate_step(assigns) do
      :ok ->
        new_step = min(assigns.step + 1, 7)

        {:ok,
         %{step: new_step, error: nil}
         |> Map.merge(Creation.prepare_step(assigns, new_step))}

      {:error, message} ->
        {:error, %{error: message}}
    end
  end

  def prev_step(assigns) do
    %{step: max(assigns.step - 1, 1), error: nil}
  end

  def finish(assigns) do
    case Creation.validate_step(assigns) do
      :ok -> {:ok, Creation.build_character(assigns)}
      {:error, message} -> {:error, message}
    end
  end

  defp toggle_limited(current, value, limit) do
    if value in current do
      List.delete(current, value)
    else
      if length(current) < limit, do: current ++ [value], else: current
    end
  end
end
