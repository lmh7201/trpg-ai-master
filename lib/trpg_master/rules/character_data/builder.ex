defmodule TrpgMaster.Rules.CharacterData.Builder do
  @moduledoc false

  alias TrpgMaster.Rules.CharacterData.Builder.{Creation, Info}

  def build_character_map(params), do: Creation.build_character_map(params)
  def get_character_info(character, category), do: Info.get_character_info(character, category)
end
