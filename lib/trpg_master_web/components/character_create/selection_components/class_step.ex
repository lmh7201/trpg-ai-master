defmodule TrpgMasterWeb.CharacterCreate.SelectionComponents.ClassStep do
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
end
