defmodule TrpgMasterWeb.CharacterCreate.SelectionComponents.BackgroundStep do
  @moduledoc false

  use TrpgMasterWeb, :html

  def background_step(assigns) do
    ~H"""
    <div class="cc-step-content">
      <h2>3. 배경 선택</h2>
      <p class="cc-desc">모험을 떠나기 전, 당신은 어떤 삶을 살았나요?</p>

      <div class="cc-card-grid">
        <%= for background <- @backgrounds do %>
          <div
            class={"cc-card #{if @selected_background && @selected_background["id"] == background["id"], do: "selected"}"}
            phx-click="select_background"
            phx-value-id={background["id"]}
          >
            <div class="cc-card-name">
              <%= get_in(background, ["name", "ko"]) || get_in(background, ["name", "en"]) || background["id"] %>
            </div>
            <div class="cc-card-name-en"><%= get_in(background, ["name", "en"]) %></div>
            <div class="cc-card-meta">
              특기: <%= get_in(background, ["feat", "name", "ko"]) || "" %>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @selected_background do %>
        <% background = @selected_background %>
        <div class="cc-detail-box">
          <h3>
            <%= get_in(background, ["name", "ko"]) || get_in(background, ["name", "en"]) %>
            <span class="cc-en"><%= get_in(background, ["name", "en"]) %></span>
          </h3>
          <p class="cc-detail-desc"><%= get_in(background, ["description", "ko"]) %></p>

          <div class="cc-detail-stats">
            <div>
              <strong>기술 숙련:</strong>
              <%= Enum.join(get_in(background, ["skillProficiencies", "ko"]) || [], ", ") %>
            </div>
            <div><strong>도구 숙련:</strong> <%= get_in(background, ["toolProficiency", "ko"]) %></div>
            <div><strong>출신 특기:</strong> <%= get_in(background, ["feat", "name", "ko"]) %></div>
          </div>

          <div class="cc-bg-abilities">
            <h4>능력치 보너스 배분</h4>
            <p class="cc-hint">하나에 +2만 넣거나, 두 곳에 +1씩 배정하세요. (총합 +2)</p>
            <div class="cc-ability-assign">
              <%= for key <- @bg_abilities do %>
                <% name = @ability_names[key] || key %>
                <div class="cc-bg-ability-row">
                  <span class="cc-bg-ability-name"><%= name %></span>
                  <button
                    class={"cc-chip #{if @bg_ability_2 == key, do: "selected"}"}
                    phx-click="set_bg_ability"
                    phx-value-rank="2"
                    phx-value-key={key}
                  >+2</button>
                  <button
                    class={"cc-chip #{if key in @bg_ability_1, do: "selected"}"}
                    phx-click="set_bg_ability"
                    phx-value-rank="1"
                    phx-value-key={key}
                  >+1</button>
                </div>
              <% end %>
            </div>
          </div>

          <div class="cc-bg-equip-preview">
            <h4>장비 옵션</h4>
            <div class="cc-equip-option">
              <strong>A:</strong> <%= get_in(background, ["equipment", "optionA", "ko"]) %>
            </div>
            <div class="cc-equip-option">
              <strong>B:</strong> <%= get_in(background, ["equipment", "optionB", "ko"]) %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
