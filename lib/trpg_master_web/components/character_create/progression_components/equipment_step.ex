defmodule TrpgMasterWeb.CharacterCreate.ProgressionComponents.EquipmentStep do
  @moduledoc false

  use TrpgMasterWeb, :html

  def equipment_step(assigns) do
    ~H"""
    <div class="cc-step-content">
      <h2>5. 장비 선택</h2>

      <%= if @selected_class do %>
        <div class="cc-equip-section">
          <h3>클래스 시작 장비</h3>
          <div class="cc-equip-choices">
            <%= for equip_group <- (@selected_class["startingEquipment"] || []) do %>
              <%= for raw_opt <- (equip_group["options"] || []) do %>
                <% opt_text =
                  if is_map(raw_opt), do: raw_opt["ko"] || raw_opt["en"] || "", else: raw_opt || "" %>
                <% choice =
                  case Regex.run(~r/^\(([A-Z])\)/, opt_text) do
                    [_, letter] -> letter
                    _ -> opt_text
                  end %>
                <button
                  class={"cc-equip-btn #{if @class_equip_choice == choice, do: "selected"}"}
                  phx-click="set_class_equip"
                  phx-value-choice={choice}
                >
                  <%= opt_text %>
                </button>
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @selected_background do %>
        <div class="cc-equip-section">
          <h3>배경 장비</h3>
          <div class="cc-equip-choices">
            <button
              class={"cc-equip-btn #{if @bg_equip_choice == "A", do: "selected"}"}
              phx-click="set_bg_equip"
              phx-value-choice="A"
            >
              A: <%= get_in(@selected_background, ["equipment", "optionA", "ko"]) %>
            </button>
            <button
              class={"cc-equip-btn #{if @bg_equip_choice == "B", do: "selected"}"}
              phx-click="set_bg_equip"
              phx-value-choice="B"
            >
              B: <%= get_in(@selected_background, ["equipment", "optionB", "ko"]) %>
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
