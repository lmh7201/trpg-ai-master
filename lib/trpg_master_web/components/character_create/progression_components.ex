defmodule TrpgMasterWeb.CharacterCreate.ProgressionComponents do
  @moduledoc false

  use TrpgMasterWeb, :html

  alias TrpgMaster.Characters.Creation
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
