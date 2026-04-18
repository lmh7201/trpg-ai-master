defmodule TrpgMasterWeb.CharacterCreate.SummaryComponents do
  @moduledoc false

  use TrpgMasterWeb, :html

  alias TrpgMaster.Characters.Creation
  alias TrpgMaster.Rules.CharacterData

  def summary_step(assigns) do
    preview_character = Creation.build_character(assigns)

    assigns =
      assigns
      |> assign(:preview_character, preview_character)
      |> assign(:final_abilities, preview_character["abilities"])

    ~H"""
    <div class="cc-step-content">
      <h2>7. 캐릭터 완성</h2>

      <div class="cc-name-input">
        <label>캐릭터 이름</label>
        <input
          type="text"
          value={@character_name}
          placeholder="이름을 입력하세요"
          phx-keyup="set_name"
          phx-debounce="300"
        />
      </div>

      <div class="cc-alignment-select">
        <label>성향</label>
        <select phx-change="set_alignment" name="alignment">
          <%= for alignment <- ["질서 선", "중립 선", "혼돈 선", "질서 중립", "순수 중립", "혼돈 중립", "질서 악", "중립 악", "혼돈 악"] do %>
            <option value={alignment} selected={alignment == @alignment}><%= alignment %></option>
          <% end %>
        </select>
      </div>

      <div class="cc-textarea-field">
        <label>외모 <span class="cc-optional">(선택)</span></label>
        <textarea
          placeholder="키, 체형, 머리카락 색, 눈 색, 눈에 띄는 특징 등을 자유롭게 적어주세요."
          phx-keyup="set_appearance"
          phx-debounce="400"
          rows="3"
        ><%= @appearance %></textarea>
      </div>

      <div class="cc-textarea-field">
        <label>배경 스토리 <span class="cc-optional">(선택)</span></label>
        <textarea
          placeholder="모험을 떠나게 된 계기, 과거 이야기, 목표, 두려움 등을 자유롭게 적어주세요."
          phx-keyup="set_backstory"
          phx-debounce="400"
          rows="5"
        ><%= @backstory %></textarea>
      </div>

      <div class="cc-summary-sheet">
        <div class="cc-summary-header">
          <h3><%= if @character_name != "", do: @character_name, else: "???" %></h3>
          <p>
            <%= if @selected_race, do: get_in(@selected_race, ["name", "ko"]), else: "?" %>
            <%= if @selected_class,
              do: get_in(@selected_class, ["name", "ko"]) || get_in(@selected_class, ["name", "en"]),
              else: "?" %>
            Lv.1 | 배경:
            <%= if @selected_background,
              do: get_in(@selected_background, ["name", "ko"]) || get_in(@selected_background, ["name", "en"]),
              else: "?" %>
          </p>
        </div>

        <div class="cc-summary-abilities">
          <%= for key <- @ability_keys do %>
            <% value = @final_abilities[key] %>
            <% mod = CharacterData.ability_modifier(value) %>
            <div class="cc-summary-ability">
              <div class="cc-summary-ab-name"><%= @ability_names[key] %></div>
              <div class="cc-summary-ab-val"><%= value %></div>
              <div class="cc-summary-ab-mod"><%= if mod >= 0, do: "+#{mod}", else: mod %></div>
            </div>
          <% end %>
        </div>

        <div class="cc-summary-stats">
          <div class="cc-summary-stat">
            <span class="cc-stat-label">HP</span>
            <span class="cc-stat-value"><%= @preview_character["hp_max"] %></span>
          </div>
          <div class="cc-summary-stat">
            <span class="cc-stat-label">AC</span>
            <span class="cc-stat-value"><%= @preview_character["ac"] %></span>
          </div>
          <div class="cc-summary-stat">
            <span class="cc-stat-label">이동속도</span>
            <span class="cc-stat-value">
              <%= if @selected_race,
                do: get_in(@selected_race, ["basicTraits", "speed", "ko"]) || "30피트",
                else: "30피트" %>
            </span>
          </div>
          <div class="cc-summary-stat">
            <span class="cc-stat-label">숙련 보너스</span>
            <span class="cc-stat-value">+2</span>
          </div>
        </div>

        <div class="cc-summary-details">
          <div class="cc-summary-block">
            <h4>기술 숙련</h4>
            <p><%= Enum.join(@class_skills ++ extract_bg_skills(@selected_background), ", ") %></p>
          </div>

          <%= if @is_spellcaster and @selected_cantrips != [] do %>
            <div class="cc-summary-block">
              <h4>소마법</h4>
              <p>
                <%= @selected_cantrips
                |> Enum.map(fn id -> find_spell_name(@available_cantrips, id) end)
                |> Enum.join(", ") %>
              </p>
            </div>
          <% end %>

          <%= if @is_spellcaster and @selected_spells != [] do %>
            <div class="cc-summary-block">
              <h4>1레벨 주문</h4>
              <p>
                <%= @selected_spells
                |> Enum.map(fn id -> find_spell_name(@available_spells, id) end)
                |> Enum.join(", ") %>
              </p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp extract_bg_skills(nil), do: []
  defp extract_bg_skills(%{"skillProficiencies" => %{"ko" => skills}}), do: skills
  defp extract_bg_skills(_), do: []

  defp find_spell_name(spells, id) do
    case Enum.find(spells, &(&1["id"] == id)) do
      nil -> id
      spell -> get_in(spell, ["name", "ko"]) || get_in(spell, ["name", "en"])
    end
  end
end
