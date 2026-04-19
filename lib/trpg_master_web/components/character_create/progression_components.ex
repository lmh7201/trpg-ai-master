defmodule TrpgMasterWeb.CharacterCreate.ProgressionComponents do
  @moduledoc false

  alias TrpgMasterWeb.CharacterCreate.ProgressionComponents.{
    AbilitiesStep,
    EquipmentStep,
    SpellsStep
  }

  defdelegate abilities_step(assigns), to: AbilitiesStep
  defdelegate equipment_step(assigns), to: EquipmentStep
  defdelegate spells_step(assigns), to: SpellsStep
end
