defmodule TrpgMasterWeb.CharacterCreate.SelectionComponents.RaceStep do
  @moduledoc false

  use TrpgMasterWeb, :html

  def race_step(assigns) do
    ~H"""
    <div class="cc-step-content">
      <h2>2. 종족 선택</h2>
      <p class="cc-desc">어떤 종족의 모험자인가요?</p>

      <div class="cc-card-grid">
        <%= for race <- @races do %>
          <% race_name = get_in(race, ["name", "ko"]) || race["id"] %>
          <% race_name_en = get_in(race, ["name", "en"]) || "" %>
          <div
            class={"cc-card #{if @selected_race && @selected_race["id"] == race["id"], do: "selected"}"}
            phx-click="select_race"
            phx-value-id={race["id"]}
          >
            <div class="cc-card-name"><%= race_name %></div>
            <div class="cc-card-name-en"><%= race_name_en %></div>
            <div class="cc-card-meta">
              <% speed = get_in(race, ["basicTraits", "speed", "ko"]) || "30피트" %>
              <% size = get_in(race, ["basicTraits", "size", "ko"]) || "" %>
              속도: <%= speed %> | <%= String.slice(size, 0..20) %>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @selected_race do %>
        <% race = @selected_race %>
        <div class="cc-detail-box">
          <h3>
            <%= get_in(race, ["name", "ko"]) %>
            <span class="cc-en"><%= get_in(race, ["name", "en"]) %></span>
          </h3>

          <div class="cc-detail-desc">
            <%= for para <- (get_in(race, ["description", "ko"]) || []) do %>
              <p><%= para %></p>
            <% end %>
          </div>

          <div class="cc-detail-stats">
            <div><strong>생물 유형:</strong> <%= get_in(race, ["basicTraits", "creatureType", "ko"]) %></div>
            <div><strong>크기:</strong> <%= get_in(race, ["basicTraits", "size", "ko"]) %></div>
            <div><strong>이동속도:</strong> <%= get_in(race, ["basicTraits", "speed", "ko"]) %></div>
          </div>

          <div class="cc-traits">
            <h4>종족 특성</h4>
            <%= for trait <- (race["traits"] || []) do %>
              <div class="cc-trait">
                <strong><%= get_in(trait, ["name", "ko"]) || get_in(trait, ["name", "en"]) %></strong>
                <p><%= get_in(trait, ["description", "ko"]) || get_in(trait, ["description", "en"]) %></p>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
