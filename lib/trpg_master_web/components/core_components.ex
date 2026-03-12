defmodule TrpgMasterWeb.CoreComponents do
  @moduledoc """
  Core UI components.
  """
  use Phoenix.Component

  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div class="flash-group">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  attr :kind, :atom, required: true
  attr :flash, :map, required: true

  def flash(assigns) do
    ~H"""
    <div :if={msg = Phoenix.Flash.get(@flash, @kind)} class={"flash flash-#{@kind}"} role="alert">
      <p><%= msg %></p>
    </div>
    """
  end
end
