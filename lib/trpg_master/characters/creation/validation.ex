defmodule TrpgMaster.Characters.Creation.Validation do
  @moduledoc false

  alias TrpgMaster.Characters.Creation.Definitions
  alias TrpgMaster.Characters.Creation.Spellcasting

  def validate_step(%{step: 1} = assigns) do
    cond do
      is_nil(assigns.selected_class) ->
        {:error, "클래스를 선택하세요."}

      length(assigns.class_skills) < assigns.class_skill_count ->
        {:error, "기술 숙련 #{assigns.class_skill_count}개를 선택하세요."}

      true ->
        :ok
    end
  end

  def validate_step(%{step: 2} = assigns) do
    if is_nil(assigns.selected_race), do: {:error, "종족을 선택하세요."}, else: :ok
  end

  def validate_step(%{step: 3} = assigns) do
    cond do
      is_nil(assigns.selected_background) ->
        {:error, "배경을 선택하세요."}

      is_nil(assigns.bg_ability_2) and assigns.bg_ability_1 == [] ->
        {:error, "능력치 보너스를 배정하세요. (+2 하나 또는 +1 둘)"}

      assigns.bg_ability_1 != [] and length(assigns.bg_ability_1) < 2 ->
        {:error, "+1을 하나 더 배정하세요. (총 2곳)"}

      true ->
        :ok
    end
  end

  def validate_step(%{step: 4} = assigns) do
    all_assigned =
      Enum.all?(Definitions.ability_keys(), fn key -> not is_nil(assigns.abilities[key]) end)

    cond do
      assigns.ability_method == "roll" and is_nil(assigns.rolled_scores) ->
        {:error, "주사위를 굴려주세요."}

      not all_assigned ->
        {:error, "모든 능력치에 값을 배정하세요."}

      true ->
        :ok
    end
  end

  def validate_step(%{step: 5}), do: :ok

  def validate_step(%{step: 6} = assigns) do
    if assigns.is_spellcaster do
      spell_limit = Spellcasting.resolved_spell_limit(assigns)

      cond do
        length(assigns.selected_cantrips) < assigns.cantrip_limit and assigns.cantrip_limit > 0 ->
          {:error, "소마법 #{assigns.cantrip_limit}개를 선택하세요."}

        length(assigns.selected_spells) < spell_limit and spell_limit > 0 ->
          {:error, "1레벨 주문 #{spell_limit}개를 선택하세요."}

        true ->
          :ok
      end
    else
      :ok
    end
  end

  def validate_step(%{step: 7} = assigns) do
    if assigns.character_name == "", do: {:error, "캐릭터 이름을 입력하세요."}, else: :ok
  end

  def validate_step(_), do: :ok
end
