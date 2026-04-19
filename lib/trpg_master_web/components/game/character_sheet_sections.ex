defmodule TrpgMasterWeb.Game.CharacterSheetSections do
  @moduledoc false

  use TrpgMasterWeb, :html

  attr(:character, :map, required: true)

  def basic_info_section(assigns) do
    ~H"""
    <div class="char-section">
      <div class="char-section-title">기본 정보</div>
      <div class="char-info-row">
        <span :if={@character["race"]} class="char-info-item">
          종족 <strong><%= @character["race"] %></strong>
        </span>
        <span :if={@character["subclass"]} class="char-info-item">
          서브클래스 <strong><%= @character["subclass"] %></strong>
        </span>
        <span :if={@character["background"]} class="char-info-item">
          배경 <strong><%= @character["background"] %></strong>
        </span>
        <span :if={@character["alignment"]} class="char-info-item">
          성향 <strong><%= @character["alignment"] %></strong>
        </span>
      </div>
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:content, :string, required: true)

  def prose_section(assigns) do
    ~H"""
    <div class="char-section">
      <div class="char-section-title"><%= @title %></div>
      <p class="char-prose"><%= @content %></p>
    </div>
    """
  end

  attr(:character, :map, required: true)

  def abilities_section(assigns) do
    assigns =
      assign(assigns, :ability_rows, ability_rows(assigns.character))

    ~H"""
    <div class="char-section">
      <div class="char-section-title">능력치</div>
      <div class="char-ability-grid">
        <%= for row <- @ability_rows do %>
          <div class="char-ability-cell">
            <span class="char-ability-label"><%= row.label %></span>
            <span class="char-ability-score"><%= row.score || "—" %></span>
            <span class="char-ability-mod"><%= ability_modifier(row.score) %></span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr(:character, :map, required: true)

  def combat_section(assigns) do
    ~H"""
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
        <div :if={@character["speed"]} class="char-combat-item">
          <span class="char-combat-label">이동</span>
          <span class="char-combat-value"><%= @character["speed"] %>ft</span>
        </div>
      </div>
    </div>
    """
  end

  attr(:character, :map, required: true)

  def spell_slots_section(assigns) do
    assigns = assign(assigns, :slot_rows, spell_slot_rows(assigns.character))

    ~H"""
    <div :if={@slot_rows != []} class="char-section">
      <div class="char-section-title">주문 슬롯</div>
      <div class="char-spell-slots">
        <%= for row <- @slot_rows do %>
          <div class="char-spell-slot-row">
            <span class="char-spell-slot-level">Lv.<%= row.level %></span>
            <div class="char-spell-slot-pips">
              <%= for index <- 1..row.total do %>
                <span class={"spell-pip #{if index <= row.used_count, do: "used", else: "available"}"}></span>
              <% end %>
            </div>
            <span class="char-spell-slot-count"><%= row.remaining %>/<%= row.total %></span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr(:character, :map, required: true)

  def known_spells_section(assigns) do
    assigns = assign(assigns, :spell_groups, known_spell_groups(assigns.character))

    ~H"""
    <div :if={@spell_groups != []} class="char-section">
      <div class="char-section-title">알고 있는 주문</div>
      <div class="char-spells-known">
        <%= for group <- @spell_groups do %>
          <div class="char-spell-level-group">
            <span class="char-spell-level-label"><%= group.label %></span>
            <div class="char-spell-names">
              <%= for spell <- group.spells do %>
                <span class="char-spell-badge"><%= spell %></span>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr(:character, :map, required: true)

  def inventory_section(assigns) do
    assigns = assign(assigns, :inventory_items, inventory_items(assigns.character))

    ~H"""
    <div class="char-section">
      <div class="char-section-title">소지품</div>
      <div :if={@inventory_items != []} class="char-inventory-list">
        <%= for item <- @inventory_items do %>
          <div class="char-inventory-item"><%= item %></div>
        <% end %>
      </div>
      <span :if={@inventory_items == []} class="char-empty-note">소지품 없음</span>
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:features, :list, required: true)
  attr(:badge_class, :string, default: "char-feature-badge")

  def grouped_features_section(assigns) do
    assigns = assign(assigns, :feature_groups, feature_groups(assigns.features))

    ~H"""
    <div :if={@feature_groups != []} class="char-section">
      <div class="char-section-title"><%= @title %></div>
      <div class="char-class-features">
        <%= for {level, features} <- @feature_groups do %>
          <div class="char-feature-level-group">
            <span class="char-feature-level-label"><%= level %>레벨</span>
            <div class="char-feature-names">
              <%= for feature <- features do %>
                <span class={@badge_class}><%= feature["name"] %></span>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:items, :list, required: true)
  attr(:container_class, :string, required: true)
  attr(:badge_class, :string, required: true)

  def badge_list_section(assigns) do
    ~H"""
    <div :if={@items != []} class="char-section">
      <div class="char-section-title"><%= @title %></div>
      <div class={@container_class}>
        <%= for item <- @items do %>
          <span class={@badge_class}><%= item %></span>
        <% end %>
      </div>
    </div>
    """
  end

  defp ability_rows(character) do
    abilities = character["abilities"] || %{}

    [
      {"str", "근력"},
      {"dex", "민첩"},
      {"con", "건강"},
      {"int", "지능"},
      {"wis", "지혜"},
      {"cha", "매력"}
    ]
    |> Enum.map(fn {key, label} -> %{label: label, score: abilities[key]} end)
  end

  defp ability_modifier(nil), do: "+0"

  defp ability_modifier(score) when is_integer(score) do
    mod = Integer.floor_div(score - 10, 2)
    if mod >= 0, do: "+#{mod}", else: "#{mod}"
  end

  defp ability_modifier(_), do: "+0"

  defp spell_slot_rows(character) do
    slots = character["spell_slots"] || %{}
    used = character["spell_slots_used"] || %{}

    slots
    |> Enum.filter(fn {_level, total} -> is_integer(total) && total > 0 end)
    |> Enum.sort_by(fn {level, _total} -> spell_level_sort_key(level) end)
    |> Enum.map(fn {level, total} ->
      used_count = if is_integer(used[level]), do: used[level], else: 0

      %{
        level: level,
        total: total,
        used_count: used_count,
        remaining: max(total - used_count, 0)
      }
    end)
  end

  defp known_spell_groups(character) do
    spells_known = character["spells_known"] || %{}

    cantrip_group =
      case spells_known["cantrips"] || [] do
        [] -> []
        cantrips -> [%{label: "소마법", spells: cantrips}]
      end

    level_groups =
      1..9
      |> Enum.map(&Integer.to_string/1)
      |> Enum.reduce([], fn level_key, groups ->
        case spells_known[level_key] || [] do
          [] -> groups
          spells -> groups ++ [%{label: "#{level_key}레벨", spells: spells}]
        end
      end)

    cantrip_group ++ level_groups
  end

  defp inventory_items(character) do
    (character["inventory"] || [])
    |> Enum.map(fn item ->
      cond do
        is_binary(item) -> item
        is_map(item) -> item["name"] || "?"
        true -> inspect(item)
      end
    end)
  end

  defp feature_groups(features) do
    features
    |> Enum.group_by(& &1["level"])
    |> Enum.sort_by(fn {level, _features} -> feature_level_sort_key(level) end)
  end

  defp spell_level_sort_key(level) when is_integer(level), do: level

  defp spell_level_sort_key(level) when is_binary(level) do
    case Integer.parse(level) do
      {value, ""} -> value
      _ -> 0
    end
  end

  defp spell_level_sort_key(_level), do: 0

  defp feature_level_sort_key(level) when is_integer(level), do: level
  defp feature_level_sort_key(level) when is_binary(level), do: spell_level_sort_key(level)
  defp feature_level_sort_key(_level), do: 0
end
