defmodule TrpgMasterWeb.Game.CharacterSheetComponents do
  @moduledoc false

  use TrpgMasterWeb, :html

  alias Phoenix.LiveView.JS

  @doc false
  attr(:character, :map, required: true)

  def character_sheet_modal(assigns) do
    ~H"""
    <div id="character-modal" style="display:none">
      <div class="character-modal-overlay" phx-click={JS.hide(to: "#character-modal")}></div>
      <div class="character-modal">
        <div class="char-modal-header">
          <div class="char-modal-title">
            <span class="char-modal-name"><%= @character["name"] || "캐릭터" %></span>
            <span class="char-modal-subtitle">
              <%= @character["class"] || "" %><%= if @character["subclass"], do: " (#{@character["subclass"]})", else: "" %><%= if @character["level"], do: " · #{@character["level"]}레벨", else: "" %>
            </span>
          </div>
          <button phx-click={JS.hide(to: "#character-modal")} class="modal-close-btn">✕</button>
        </div>

        <div class="char-modal-body">
          <div class="char-section">
            <div class="char-section-title">기본 정보</div>
            <div class="char-info-row">
              <%= if @character["race"] do %>
                <span class="char-info-item">종족 <strong><%= @character["race"] %></strong></span>
              <% end %>
              <%= if @character["subclass"] do %>
                <span class="char-info-item">서브클래스 <strong><%= @character["subclass"] %></strong></span>
              <% end %>
              <%= if @character["background"] do %>
                <span class="char-info-item">배경 <strong><%= @character["background"] %></strong></span>
              <% end %>
              <%= if @character["alignment"] do %>
                <span class="char-info-item">성향 <strong><%= @character["alignment"] %></strong></span>
              <% end %>
            </div>
          </div>

          <%= if @character["appearance"] && @character["appearance"] != "" do %>
            <div class="char-section">
              <div class="char-section-title">외모</div>
              <p class="char-prose"><%= @character["appearance"] %></p>
            </div>
          <% end %>

          <%= if @character["backstory"] && @character["backstory"] != "" do %>
            <div class="char-section">
              <div class="char-section-title">배경 스토리</div>
              <p class="char-prose"><%= @character["backstory"] %></p>
            </div>
          <% end %>

          <% abilities = @character["abilities"] || %{} %>
          <div class="char-section">
            <div class="char-section-title">능력치</div>
            <div class="char-ability-grid">
              <%= for {key, label} <- [{"str", "근력"}, {"dex", "민첩"}, {"con", "건강"}, {"int", "지능"}, {"wis", "지혜"}, {"cha", "매력"}] do %>
                <% score = abilities[key] %>
                <div class="char-ability-cell">
                  <span class="char-ability-label"><%= label %></span>
                  <span class="char-ability-score"><%= score || "—" %></span>
                  <span class="char-ability-mod"><%= ability_modifier(score) %></span>
                </div>
              <% end %>
            </div>
          </div>

          <div class="char-section">
            <div class="char-section-title">전투</div>
            <div class="char-combat-grid">
              <div class="char-combat-item">
                <span class="char-combat-label">HP</span>
                <span class="char-combat-value char-combat-hp">
                  <%= @character["hp_current"] || "?" %>/<%= @character["hp_max"] || "?" %>
                </span>
              </div>
              <div class="char-combat-item">
                <span class="char-combat-label">AC</span>
                <span class="char-combat-value char-combat-ac"><%= @character["ac"] || "?" %></span>
              </div>
              <%= if @character["speed"] do %>
                <div class="char-combat-item">
                  <span class="char-combat-label">이동</span>
                  <span class="char-combat-value"><%= @character["speed"] %>ft</span>
                </div>
              <% end %>
            </div>
          </div>

          <% slots = @character["spell_slots"] || %{} %>
          <% has_spells = Enum.any?(slots, fn {_key, value} -> is_integer(value) && value > 0 end) %>
          <%= if has_spells do %>
            <% used = @character["spell_slots_used"] || %{} %>
            <div class="char-section">
              <div class="char-section-title">주문 슬롯</div>
              <div class="char-spell-slots">
                <%= for {level, total} <- Enum.sort(slots), is_integer(total) && total > 0 do %>
                  <% raw_used = used[level] %>
                  <% used_count = if is_integer(raw_used), do: raw_used, else: 0 %>
                  <div class="char-spell-slot-row">
                    <span class="char-spell-slot-level">Lv.<%= level %></span>
                    <div class="char-spell-slot-pips">
                      <%= for index <- 1..total do %>
                        <span class={"spell-pip #{if index <= used_count, do: "used", else: "available"}"}></span>
                      <% end %>
                    </div>
                    <span class="char-spell-slot-count"><%= total - used_count %>/<%= total %></span>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <% spells_known = @character["spells_known"] || %{} %>
          <% has_known_spells = Enum.any?(spells_known, fn {_key, value} -> is_list(value) && value != [] end) %>
          <%= if has_known_spells do %>
            <div class="char-section">
              <div class="char-section-title">알고 있는 주문</div>
              <div class="char-spells-known">
                <% cantrips = spells_known["cantrips"] || [] %>
                <%= if cantrips != [] do %>
                  <div class="char-spell-level-group">
                    <span class="char-spell-level-label">소마법</span>
                    <div class="char-spell-names">
                      <%= for spell <- cantrips do %>
                        <span class="char-spell-badge"><%= spell %></span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
                <%= for level_key <- ["1", "2", "3", "4", "5", "6", "7", "8", "9"] do %>
                  <% level_spells = spells_known[level_key] || [] %>
                  <%= if level_spells != [] do %>
                    <div class="char-spell-level-group">
                      <span class="char-spell-level-label"><%= level_key %>레벨</span>
                      <div class="char-spell-names">
                        <%= for spell <- level_spells do %>
                          <span class="char-spell-badge"><%= spell %></span>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>

          <% inventory = @character["inventory"] || [] %>
          <div class="char-section">
            <div class="char-section-title">소지품</div>
            <%= if inventory != [] do %>
              <div class="char-inventory-list">
                <%= for item <- inventory do %>
                  <div class="char-inventory-item">
                    <%= cond do
                      is_binary(item) -> item
                      is_map(item) -> item["name"] || "?"
                      true -> inspect(item)
                    end %>
                  </div>
                <% end %>
              </div>
            <% else %>
              <span class="char-empty-note">소지품 없음</span>
            <% end %>
          </div>

          <% class_features = @character["class_features"] || [] %>
          <%= if class_features != [] do %>
            <div class="char-section">
              <div class="char-section-title">클래스 피처</div>
              <div class="char-class-features">
                <%= for {level, features} <- class_features |> Enum.group_by(& &1["level"]) |> Enum.sort() do %>
                  <div class="char-feature-level-group">
                    <span class="char-feature-level-label"><%= level %>레벨</span>
                    <div class="char-feature-names">
                      <%= for feature <- features do %>
                        <span class="char-feature-badge"><%= feature["name"] %></span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <% subclass_features = @character["subclass_features"] || [] %>
          <%= if subclass_features != [] do %>
            <div class="char-section">
              <div class="char-section-title">서브클래스 피처 (<%= @character["subclass"] %>)</div>
              <div class="char-class-features">
                <%= for {level, features} <- subclass_features |> Enum.group_by(& &1["level"]) |> Enum.sort() do %>
                  <div class="char-feature-level-group">
                    <span class="char-feature-level-label"><%= level %>레벨</span>
                    <div class="char-feature-names">
                      <%= for feature <- features do %>
                        <span class="char-feature-badge char-subclass-feature-badge"><%= feature["name"] %></span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <% feats = (@character["feats"] || []) ++ (if @character["background_feat"], do: [@character["background_feat"]], else: []) %>
          <%= if feats != [] do %>
            <div class="char-section">
              <div class="char-section-title">특기</div>
              <div class="char-features-list">
                <%= for feat_name <- feats do %>
                  <span class="char-feature-badge"><%= feat_name %></span>
                <% end %>
              </div>
            </div>
          <% end %>

          <% conditions = @character["conditions"] || [] %>
          <%= if conditions != [] do %>
            <div class="char-section">
              <div class="char-section-title">상태이상</div>
              <div class="char-conditions">
                <%= for condition_name <- conditions do %>
                  <span class="char-condition-badge"><%= condition_name %></span>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp ability_modifier(nil), do: "+0"

  defp ability_modifier(score) when is_integer(score) do
    mod = Integer.floor_div(score - 10, 2)
    if mod >= 0, do: "+#{mod}", else: "#{mod}"
  end

  defp ability_modifier(_), do: "+0"
end
