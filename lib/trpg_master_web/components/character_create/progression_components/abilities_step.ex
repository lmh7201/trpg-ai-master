defmodule TrpgMasterWeb.CharacterCreate.ProgressionComponents.AbilitiesStep do
  @moduledoc false

  use TrpgMasterWeb, :html

  alias TrpgMaster.Rules.CharacterData

  def abilities_step(assigns) do
    ~H"""
    <div class="cc-step-content">
      <h2>4. 능력치 결정</h2>

      <div class="cc-method-select">
        <button
          class={"cc-chip #{if @ability_method == "standard_array", do: "selected"}"}
          phx-click="set_ability_method"
          phx-value-method="standard_array"
        >표준 배열</button>
        <button
          class={"cc-chip #{if @ability_method == "roll", do: "selected"}"}
          phx-click="set_ability_method"
          phx-value-method="roll"
        >주사위 굴림 (4d6)</button>
      </div>

      <%= if @ability_method == "roll" do %>
        <div class="cc-roll-section">
          <button class="cc-btn cc-btn-secondary" phx-click="roll_abilities">주사위 굴리기</button>
          <%= if @rolled_scores do %>
            <span class="cc-rolled-values">굴림 결과: <%= Enum.join(@rolled_scores, ", ") %></span>
          <% end %>
        </div>
      <% end %>

      <div class="cc-ability-grid">
        <%= for key <- @ability_keys do %>
          <% name = @ability_names[key] %>
          <% base_val = @abilities[key] %>
          <% bg_bonus =
            cond do
              @bg_ability_2 == key -> 2
              key in @bg_ability_1 -> 1
              true -> 0
            end %>
          <% final_val = if base_val, do: base_val + bg_bonus, else: nil %>
          <% mod = if final_val, do: CharacterData.ability_modifier(final_val), else: nil %>

          <div class="cc-ability-card">
            <div class="cc-ability-name"><%= name %></div>

            <%= if base_val do %>
              <div
                class="cc-ability-value"
                phx-click="clear_ability"
                phx-value-key={key}
                title="클릭하여 초기화"
              >
                <span class="cc-ability-final"><%= final_val %></span>
                <%= if bg_bonus > 0 do %>
                  <span class="cc-ability-bonus">(기본 <%= base_val %> + <%= bg_bonus %>)</span>
                <% end %>
                <span class="cc-ability-mod">
                  수정치: <%= if mod && mod >= 0, do: "+#{mod}", else: mod %>
                </span>
              </div>
            <% else %>
              <div class="cc-ability-empty">
                <div class="cc-score-options">
                  <%= for score <- @available_scores |> Enum.uniq() do %>
                    <button
                      class="cc-score-btn"
                      phx-click="assign_ability"
                      phx-value-key={key}
                      phx-value-score={score}
                    >
                      <%= score %>
                    </button>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <%= if @ability_method == "standard_array" do %>
        <p class="cc-hint">
          표준 배열: 15, 14, 13, 12, 10, 8 — 각 능력치에 하나씩 배정하세요. 배정된 값을 클릭하면
          초기화됩니다.
        </p>
      <% end %>
    </div>
    """
  end
end
