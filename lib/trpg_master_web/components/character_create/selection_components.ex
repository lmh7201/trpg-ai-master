defmodule TrpgMasterWeb.CharacterCreate.SelectionComponents do
  @moduledoc false

  use TrpgMasterWeb, :html

  def class_step(assigns) do
    ~H"""
    <div class="cc-step-content">
      <h2>1. 클래스 선택</h2>
      <p class="cc-desc">당신의 모험자는 어떤 직업을 가지고 있나요?</p>

      <div class="cc-card-grid">
        <%= for class <- @classes do %>
          <div
            class={"cc-card #{if @selected_class && @selected_class["id"] == class["id"], do: "selected"}"}
            phx-click="select_class"
            phx-value-id={class["id"]}
          >
            <div class="cc-card-name">
              <%= get_in(class, ["name", "ko"]) || get_in(class, ["name", "en"]) || class["id"] %>
            </div>
            <div class="cc-card-name-en"><%= get_in(class, ["name", "en"]) %></div>
            <div class="cc-card-meta">
              HP: <%= class["hitPointDie"] %> | 주 능력:
              <%= get_in(class, ["primaryAbility", "ko"]) || get_in(class, ["primaryAbility", "en"]) %>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @selected_class do %>
        <div class="cc-detail-box">
          <h3>
            <%= get_in(@selected_class, ["name", "ko"]) %>
            <span class="cc-en"><%= get_in(@selected_class, ["name", "en"]) %></span>
          </h3>
          <p class="cc-detail-desc">
            <%= String.slice(get_in(@selected_class, ["description", "ko"]) || get_in(@selected_class, ["description", "en"]) || "", 0..300) %>...
          </p>

          <div class="cc-detail-stats">
            <div><strong>HP 주사위:</strong> <%= @selected_class["hitPointDie"] %></div>
            <div>
              <strong>내성 굴림:</strong>
              <%= get_in(@selected_class, ["savingThrowProficiencies", "ko"]) || get_in(@selected_class, ["savingThrowProficiencies", "en"]) %>
            </div>
            <div>
              <strong>무기 숙련:</strong>
              <%= get_in(@selected_class, ["weaponProficiencies", "ko"]) || get_in(@selected_class, ["weaponProficiencies", "en"]) %>
            </div>
            <div>
              <strong>방어구 훈련:</strong>
              <%= get_in(@selected_class, ["armorTraining", "ko"]) || get_in(@selected_class, ["armorTraining", "en"]) %>
            </div>
          </div>

          <div class="cc-skill-select">
            <h4>기술 숙련 선택 (<%= length(@class_skills) %>/<%= @class_skill_count %>)</h4>
            <div class="cc-skill-chips">
              <%= for skill <- @available_class_skills do %>
                <button
                  class={"cc-chip #{if skill in @class_skills, do: "selected"}"}
                  phx-click="toggle_class_skill"
                  phx-value-skill={skill}
                >
                  <%= skill %>
                </button>
              <% end %>
            </div>
          </div>

          <%= if @selected_class["startingEquipment"] do %>
            <div class="cc-equip-preview">
              <h4>시작 장비 옵션</h4>
              <%= for equip_group <- (@selected_class["startingEquipment"] || []) do %>
                <%= for opt <- (equip_group["options"] || []) do %>
                  <div class="cc-equip-option">
                    <%= if is_map(opt), do: opt["ko"] || opt["en"], else: opt %>
                  </div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

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
