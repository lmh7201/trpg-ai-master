defmodule TrpgMasterWeb.Game.StatusComponents do
  @moduledoc false

  use TrpgMasterWeb, :html

  alias Phoenix.LiveView.JS

  @doc false
  attr(:characters, :list, required: true)
  attr(:character, :map, default: nil)
  attr(:location, :string, default: nil)
  attr(:phase, :atom, default: :exploration)
  attr(:combat_state, :map, default: nil)
  attr(:mode, :atom, default: :adventure)

  def campaign_status_bars(assigns) do
    display_characters =
      if length(assigns.characters) > 1 do
        assigns.characters
      else
        [assigns.character]
      end

    assigns = assign(assigns, :display_characters, display_characters)

    ~H"""
    <%= for char <- @display_characters do %>
      <.status_bar
        character={char}
        location={@location}
        phase={@phase}
        combat_state={@combat_state}
        mode={@mode}
      />
    <% end %>
    """
  end

  @doc false
  attr(:character, :map, default: nil)
  attr(:location, :string, default: nil)
  attr(:phase, :atom, default: :exploration)
  attr(:combat_state, :map, default: nil)
  attr(:mode, :atom, default: :adventure)

  def status_bar(assigns) do
    ~H"""
    <div class="status-bar">
      <%= if @character do %>
        <button phx-click={JS.show(to: "#character-modal")} class="char-sheet-btn" title="캐릭터 시트 열기">
          📜 <strong><%= @character["name"] || "캐릭터" %></strong>
        </button>
        <span class="status-item">
          ❤️ <strong><%= @character["hp_current"] || "?" %>/<%= @character["hp_max"] || "?" %></strong>
        </span>
        <%= if @character["ac"] do %>
          <span class="status-item">🛡️ AC <strong><%= @character["ac"] %></strong></span>
        <% end %>
        <%= if spell_slot_total(@character) > 0 do %>
          <span class="status-item">⚡ <strong><%= spell_slots_display(@character) %></strong></span>
        <% end %>
      <% end %>
      <span class="status-item">📍 <%= @location || "미정" %></span>
      <%= if @phase == :combat && @combat_state do %>
        <span class="status-item combat-badge">
          ⚔️ <strong><%= @combat_state["round"] || 1 %>라운드</strong>
          <%= if @combat_state["participants"] do %>
            — <%= Enum.join(@combat_state["participants"], " vs ") %>
          <% end %>
        </span>
      <% end %>
      <%= if @mode == :debug do %>
        <span class="status-item debug-badge">🔧 디버그</span>
      <% end %>
    </div>
    """
  end

  defp spell_slots_display(character) do
    slots = character["spell_slots"] || %{}
    used = character["spell_slots_used"] || %{}
    total = spell_slot_total(character)

    used_count =
      used
      |> Enum.map(fn {_key, value} -> if is_integer(value), do: value, else: 0 end)
      |> Enum.sum()

    total_count =
      slots
      |> Enum.map(fn {_key, value} -> if is_integer(value), do: value, else: 0 end)
      |> Enum.sum()

    if total > 0 do
      "주문 슬롯 #{total_count - used_count}/#{total_count}"
    else
      ""
    end
  end

  defp spell_slot_total(character) do
    slots = character["spell_slots"] || %{}

    slots
    |> Enum.map(fn {_key, value} -> if is_integer(value), do: value, else: 0 end)
    |> Enum.sum()
  end
end
