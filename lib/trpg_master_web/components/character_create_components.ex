defmodule TrpgMasterWeb.CharacterCreateComponents do
  @moduledoc """
  캐릭터 생성 위저드의 단계별 UI를 담당하는 컴포넌트 모음.
  """

  use TrpgMasterWeb, :html

  alias TrpgMaster.Characters.Creation
  alias TrpgMaster.Rules.CharacterData

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
