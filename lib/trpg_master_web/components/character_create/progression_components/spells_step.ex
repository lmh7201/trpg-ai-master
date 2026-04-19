defmodule TrpgMasterWeb.CharacterCreate.ProgressionComponents.SpellsStep do
  @moduledoc false

  use TrpgMasterWeb, :html

  alias TrpgMaster.Characters.Creation

  def spells_step(assigns) do
    ~H"""
    <div class="cc-step-content">
      <h2>6. 주문 선택</h2>

      <%= if not @is_spellcaster do %>
        <div class="cc-no-spells">
          <p>
            <%= if @selected_class,
              do: get_in(@selected_class, ["name", "ko"]) || get_in(@selected_class, ["name", "en"]),
              else: "선택한 클래스" %>은(는) 1레벨에서 주문을 사용하지 않습니다.
          </p>
          <p class="cc-hint">다음 단계로 넘어가세요.</p>
        </div>
      <% else %>
        <%= if @cantrip_limit > 0 do %>
          <div class="cc-spell-section">
            <h3>소마법 (Cantrip) 선택 (<%= length(@selected_cantrips) %>/<%= @cantrip_limit %>)</h3>
            <div class="cc-spell-grid">
              <%= for spell <- @available_cantrips do %>
                <div
                  class={"cc-spell-card #{if spell["id"] in @selected_cantrips, do: "selected"}"}
                  phx-click="toggle_cantrip"
                  phx-value-id={spell["id"]}
                >
                  <div class="cc-spell-name">
                    <%= get_in(spell, ["name", "ko"]) || get_in(spell, ["name", "en"]) %>
                  </div>
                  <div class="cc-spell-name-en"><%= get_in(spell, ["name", "en"]) %></div>
                  <div class="cc-spell-meta">
                    <%= get_in(spell, ["castingTime", "ko"]) || get_in(spell, ["castingTime", "en"]) %>
                    |
                    <%= get_in(spell, ["range", "ko"]) || get_in(spell, ["range", "en"]) %>
                  </div>
                  <div class="cc-spell-desc">
                    <%= String.slice(get_in(spell, ["description", "ko"]) || get_in(spell, ["description", "en"]) || "", 0..100) %>...
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <% spell_limit = Creation.resolved_spell_limit(assigns) %>
        <%= if spell_limit > 0 do %>
          <div class="cc-spell-section">
            <h3>1레벨 주문 선택 (<%= length(@selected_spells) %>/<%= spell_limit %>)</h3>
            <div class="cc-spell-grid">
              <%= for spell <- @available_spells do %>
                <div
                  class={"cc-spell-card #{if spell["id"] in @selected_spells, do: "selected"}"}
                  phx-click="toggle_spell"
                  phx-value-id={spell["id"]}
                >
                  <div class="cc-spell-name">
                    <%= get_in(spell, ["name", "ko"]) || get_in(spell, ["name", "en"]) %>
                  </div>
                  <div class="cc-spell-name-en"><%= get_in(spell, ["name", "en"]) %></div>
                  <div class="cc-spell-meta">
                    <%= get_in(spell, ["castingTime", "ko"]) || get_in(spell, ["castingTime", "en"]) %>
                    |
                    <%= get_in(spell, ["range", "ko"]) || get_in(spell, ["range", "en"]) %>
                    |
                    <%= if spell["concentration"],
                      do: "집중",
                      else: get_in(spell, ["duration", "ko"]) || get_in(spell, ["duration", "en"]) %>
                  </div>
                  <div class="cc-spell-desc">
                    <%= String.slice(get_in(spell, ["description", "ko"]) || get_in(spell, ["description", "en"]) || "", 0..100) %>...
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
