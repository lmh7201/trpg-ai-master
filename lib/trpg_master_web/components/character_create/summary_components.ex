defmodule TrpgMasterWeb.CharacterCreate.SummaryComponents do
  @moduledoc false

  use TrpgMasterWeb, :html

  alias TrpgMaster.Rules.CharacterData
  alias TrpgMasterWeb.CharacterCreate.SummaryComponents.Preview

  def summary_step(assigns) do
    assigns =
      assign(assigns, Preview.build(assigns))

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
        <form phx-change="set_alignment">
          <select name="alignment">
            <%= for alignment <- ["질서 선", "중립 선", "혼돈 선", "질서 중립", "순수 중립", "혼돈 중립", "질서 악", "중립 악", "혼돈 악"] do %>
              <option value={alignment} selected={alignment == @alignment}><%= alignment %></option>
            <% end %>
          </select>
        </form>
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
          <h3><%= @preview_name %></h3>
          <p><%= @preview_line %></p>
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
            <span class="cc-stat-value"><%= @speed_display %></span>
          </div>
          <div class="cc-summary-stat">
            <span class="cc-stat-label">숙련 보너스</span>
            <span class="cc-stat-value">+2</span>
          </div>
        </div>

        <div class="cc-summary-details">
          <div class="cc-summary-block">
            <h4>기술 숙련</h4>
            <p><%= Enum.join(@skill_names, ", ") %></p>
          </div>

          <%= if @cantrip_names != [] do %>
            <div class="cc-summary-block">
              <h4>소마법</h4>
              <p><%= Enum.join(@cantrip_names, ", ") %></p>
            </div>
          <% end %>

          <%= if @spell_names != [] do %>
            <div class="cc-summary-block">
              <h4>1레벨 주문</h4>
              <p><%= Enum.join(@spell_names, ", ") %></p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
