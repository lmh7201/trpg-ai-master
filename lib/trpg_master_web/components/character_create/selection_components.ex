defmodule TrpgMasterWeb.CharacterCreate.SelectionComponents do
  @moduledoc false

  alias TrpgMasterWeb.CharacterCreate.SelectionComponents.{
    BackgroundStep,
    ClassStep,
    RaceStep
  }

  defdelegate class_step(assigns), to: ClassStep
  defdelegate race_step(assigns), to: RaceStep
  defdelegate background_step(assigns), to: BackgroundStep
end
