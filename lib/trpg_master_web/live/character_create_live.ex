defmodule TrpgMasterWeb.CharacterCreateLive do
  use TrpgMasterWeb, :live_view

  require Logger

  alias TrpgMaster.Campaign.{Manager, Server}
  alias TrpgMaster.Rules.CharacterData

  @steps [
    {1, "클래스", "class"},
    {2, "종족", "race"},
    {3, "배경", "background"},
    {4, "능력치", "abilities"},
    {5, "장비", "equipment"},
    {6, "주문", "spells"},
    {7, "완성", "summary"}
  ]

  @standard_array [15, 14, 13, 12, 10, 8]

  @ability_keys ["str", "dex", "con", "int", "wis", "cha"]
  @ability_names %{
    "str" => "근력",
    "dex" => "민첩",
    "con" => "건강",
    "int" => "지능",
    "wis" => "지혜",
    "cha" => "매력"
  }

  # 주문시전 클래스와 소마법/1레벨 주문 수
  @spellcasting_classes %{
    "bard" => %{cantrips: 2, spells: 4},
    "cleric" => %{cantrips: 3, spells: :wis_mod_plus_level},
    "druid" => %{cantrips: 2, spells: :wis_mod_plus_level},
    "ranger" => %{cantrips: 0, spells: 2},
    "sorcerer" => %{cantrips: 4, spells: 2},
    "warlock" => %{cantrips: 2, spells: 2},
    "wizard" => %{cantrips: 3, spells: 6}
  }

  # ── Mount ──────────────────────────────────────────────────────────────────

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # 캠페인 서버가 떠 있는지 확인
    unless Server.alive?(id) do
      case Manager.start_campaign(id) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end

    # 데이터가 로드되지 않았으면 AI 캐릭터 생성으로 바로 이동
    classes = CharacterData.classes()

    if classes == [] do
      Logger.warning("CharacterCreateLive: 캐릭터 데이터 없음 → AI 캐릭터 생성으로 이동")
      {:ok, push_navigate(socket, to: "/play/#{id}")}
    else
      mount_with_data(id, classes, socket)
    end
  end

  defp mount_with_data(id, classes, socket) do
    socket =
      socket
      |> assign(:campaign_id, id)
      |> assign(:step, 1)
      |> assign(:steps, @steps)
      |> assign(:ability_keys, @ability_keys)
      |> assign(:ability_names, @ability_names)
      # 선택 데이터
      |> assign(:classes, classes)
      |> assign(:races, CharacterData.races())
      |> assign(:backgrounds, CharacterData.backgrounds())
      # 선택 상태
      |> assign(:selected_class, nil)
      |> assign(:selected_race, nil)
      |> assign(:selected_background, nil)
      |> assign(:class_skills, [])
      |> assign(:available_class_skills, [])
      |> assign(:class_skill_count, 0)
      # 배경 능력치 배분
      |> assign(:bg_ability_2, nil)
      |> assign(:bg_ability_1, [])
      |> assign(:bg_abilities, [])
      # 능력치
      |> assign(:ability_method, "standard_array")
      |> assign(:abilities, %{"str" => nil, "dex" => nil, "con" => nil, "int" => nil, "wis" => nil, "cha" => nil})
      |> assign(:available_scores, @standard_array)
      |> assign(:rolled_scores, nil)
      # 장비
      |> assign(:class_equip_choice, "A")
      |> assign(:bg_equip_choice, "A")
      # 주문
      |> assign(:is_spellcaster, false)
      |> assign(:cantrip_limit, 0)
      |> assign(:spell_limit, 0)
      |> assign(:selected_cantrips, [])
      |> assign(:selected_spells, [])
      |> assign(:available_cantrips, [])
      |> assign(:available_spells, [])
      # 캐릭터 이름
      |> assign(:character_name, "")
      |> assign(:alignment, "중립")
      |> assign(:error, nil)
      # 상세 패널
      |> assign(:detail_panel, nil)

    {:ok, socket}
  end

  # ── Events ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("select_class", %{"id" => class_id}, socket) do
    class = CharacterData.get_class(class_id)

    skill_opts = get_in(class, ["skillProficienciesKo", "options"]) || get_in(class, ["skillProficiencies", "options"]) || []
    skill_count = get_in(class, ["skillProficiencies", "choose"]) || 2

    # 주문시전 여부 확인
    is_spellcaster = Map.has_key?(@spellcasting_classes, class_id)
    spell_info = Map.get(@spellcasting_classes, class_id, %{cantrips: 0, spells: 0})

    socket =
      socket
      |> assign(:selected_class, class)
      |> assign(:available_class_skills, skill_opts)
      |> assign(:class_skill_count, skill_count)
      |> assign(:class_skills, [])
      |> assign(:is_spellcaster, is_spellcaster)
      |> assign(:cantrip_limit, Map.get(spell_info, :cantrips, 0))
      |> assign(:spell_limit, Map.get(spell_info, :spells, 0))
      |> assign(:selected_cantrips, [])
      |> assign(:selected_spells, [])
      |> assign(:detail_panel, nil)

    {:noreply, socket}
  end

  def handle_event("toggle_class_skill", %{"skill" => skill}, socket) do
    current = socket.assigns.class_skills
    max_count = socket.assigns.class_skill_count

    new_skills =
      if skill in current do
        List.delete(current, skill)
      else
        if length(current) < max_count, do: current ++ [skill], else: current
      end

    {:noreply, assign(socket, :class_skills, new_skills)}
  end

  def handle_event("select_race", %{"id" => race_id}, socket) do
    race = CharacterData.get_race(race_id)
    {:noreply, assign(socket, :selected_race, race) |> assign(:detail_panel, nil)}
  end

  def handle_event("select_background", %{"id" => bg_id}, socket) do
    bg = CharacterData.get_background(bg_id)

    # 배경의 능력치 3개 추출
    bg_abilities =
      case get_in(bg, ["abilityScores", "en"]) do
        list when is_list(list) ->
          Enum.map(list, fn name -> ability_en_to_key(name) end)
        _ -> []
      end

    socket =
      socket
      |> assign(:selected_background, bg)
      |> assign(:bg_abilities, bg_abilities)
      |> assign(:bg_ability_2, nil)
      |> assign(:bg_ability_1, [])
      |> assign(:detail_panel, nil)

    {:noreply, socket}
  end

  def handle_event("set_bg_ability", %{"rank" => rank, "key" => key}, socket) do
    case rank do
      "2" ->
        # +2 하나만 배정 (기존 +1 모두 해제)
        # 같은 곳 다시 누르면 해제
        new_2 = if socket.assigns.bg_ability_2 == key, do: nil, else: key
        {:noreply, socket |> assign(:bg_ability_2, new_2) |> assign(:bg_ability_1, [])}

      "1" ->
        # +1 토글 (최대 2개, +2는 해제)
        current = socket.assigns.bg_ability_1

        new_1 =
          if key in current do
            List.delete(current, key)
          else
            if length(current) < 2, do: current ++ [key], else: current
          end

        {:noreply, socket |> assign(:bg_ability_1, new_1) |> assign(:bg_ability_2, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("set_ability_method", %{"method" => method}, socket) do
    socket =
      socket
      |> assign(:ability_method, method)
      |> assign(:abilities, %{"str" => nil, "dex" => nil, "con" => nil, "int" => nil, "wis" => nil, "cha" => nil})
      |> assign(:available_scores, if(method == "standard_array", do: @standard_array, else: []))
      |> assign(:rolled_scores, nil)

    {:noreply, socket}
  end

  def handle_event("assign_ability", %{"key" => key, "score" => score_str}, socket) do
    case Integer.parse(score_str) do
      {value, _} -> do_assign_ability(key, value, socket)
      :error -> {:noreply, socket}
    end
  end

  defp do_assign_ability(key, value, socket) do
    abilities = socket.assigns.abilities

    # 이미 다른 능력치에 같은 값이 배정되어 있으면 그쪽을 해제
    # (표준 배열/롤 방식에서 같은 값을 중복 배정 방지)
    old_key = Enum.find(@ability_keys, fn k -> abilities[k] == value && k != key end)

    abilities =
      if old_key do
        Map.put(abilities, old_key, nil)
      else
        abilities
      end

    abilities = Map.put(abilities, key, value)

    # 사용 가능한 점수 업데이트
    all_scores =
      case socket.assigns.ability_method do
        "standard_array" -> @standard_array
        "roll" -> socket.assigns.rolled_scores || []
        _ -> []
      end

    used = abilities |> Map.values() |> Enum.reject(&is_nil/1)

    available =
      Enum.reduce(used, all_scores, fn val, acc ->
        case Enum.find_index(acc, &(&1 == val)) do
          nil -> acc
          idx -> List.delete_at(acc, idx)
        end
      end)

    {:noreply, socket |> assign(:abilities, abilities) |> assign(:available_scores, available)}
  end

  def handle_event("clear_ability", %{"key" => key}, socket) do
    abilities = Map.put(socket.assigns.abilities, key, nil)

    all_scores =
      case socket.assigns.ability_method do
        "standard_array" -> @standard_array
        "roll" -> socket.assigns.rolled_scores || []
        _ -> []
      end

    used = abilities |> Map.values() |> Enum.reject(&is_nil/1)

    available =
      Enum.reduce(used, all_scores, fn val, acc ->
        case Enum.find_index(acc, &(&1 == val)) do
          nil -> acc
          idx -> List.delete_at(acc, idx)
        end
      end)

    {:noreply, socket |> assign(:abilities, abilities) |> assign(:available_scores, available)}
  end

  def handle_event("roll_abilities", _params, socket) do
    # 4d6 drop lowest, 6회
    scores =
      for _ <- 1..6 do
        rolls = for _ <- 1..4, do: Enum.random(1..6)
        rolls |> Enum.sort(:desc) |> Enum.take(3) |> Enum.sum()
      end
      |> Enum.sort(:desc)

    socket =
      socket
      |> assign(:rolled_scores, scores)
      |> assign(:available_scores, scores)
      |> assign(:abilities, %{"str" => nil, "dex" => nil, "con" => nil, "int" => nil, "wis" => nil, "cha" => nil})

    {:noreply, socket}
  end

  def handle_event("set_class_equip", %{"choice" => choice}, socket) do
    {:noreply, assign(socket, :class_equip_choice, choice)}
  end

  def handle_event("set_bg_equip", %{"choice" => choice}, socket) do
    {:noreply, assign(socket, :bg_equip_choice, choice)}
  end

  def handle_event("toggle_cantrip", %{"id" => spell_id}, socket) do
    current = socket.assigns.selected_cantrips
    limit = socket.assigns.cantrip_limit

    new =
      if spell_id in current do
        List.delete(current, spell_id)
      else
        if length(current) < limit, do: current ++ [spell_id], else: current
      end

    {:noreply, assign(socket, :selected_cantrips, new)}
  end

  def handle_event("toggle_spell", %{"id" => spell_id}, socket) do
    current = socket.assigns.selected_spells
    limit = resolved_spell_limit(socket.assigns)

    new =
      if spell_id in current do
        List.delete(current, spell_id)
      else
        if length(current) < limit, do: current ++ [spell_id], else: current
      end

    {:noreply, assign(socket, :selected_spells, new)}
  end

  def handle_event("set_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :character_name, String.trim(name))}
  end

  def handle_event("set_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, :character_name, String.trim(name))}
  end

  def handle_event("set_alignment", %{"alignment" => alignment}, socket) do
    {:noreply, assign(socket, :alignment, alignment)}
  end

  def handle_event("show_detail", %{"type" => type, "id" => id}, socket) do
    {:noreply, assign(socket, :detail_panel, %{type: type, id: id})}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, :detail_panel, nil)}
  end

  def handle_event("next_step", _params, socket) do
    case validate_step(socket.assigns) do
      :ok ->
        new_step = min(socket.assigns.step + 1, 7)

        socket =
          socket
          |> assign(:step, new_step)
          |> assign(:error, nil)
          |> maybe_prepare_step(new_step)

        {:noreply, socket}

      {:error, msg} ->
        {:noreply, assign(socket, :error, msg)}
    end
  end

  def handle_event("prev_step", _params, socket) do
    new_step = max(socket.assigns.step - 1, 1)
    {:noreply, socket |> assign(:step, new_step) |> assign(:error, nil)}
  end

  def handle_event("finish", _params, socket) do
    case validate_step(socket.assigns) do
      :ok ->
        character = build_final_character(socket.assigns)
        campaign_id = socket.assigns.campaign_id

        # 캠페인 서버에 캐릭터 등록
        state = Server.get_state(campaign_id)
        new_state = %{state | characters: [character]}
        # Server의 state를 직접 업데이트하기 위해 GenServer.call 사용
        GenServer.call(
          {:via, Registry, {TrpgMaster.Campaign.Registry, campaign_id}},
          {:set_character, character}
        )

        {:noreply, push_navigate(socket, to: "/play/#{campaign_id}")}

      {:error, msg} ->
        {:noreply, assign(socket, :error, msg)}
    end
  end

  # ── Step validation ────────────────────────────────────────────────────────

  defp validate_step(%{step: 1} = assigns) do
    cond do
      is_nil(assigns.selected_class) -> {:error, "클래스를 선택하세요."}
      length(assigns.class_skills) < assigns.class_skill_count -> {:error, "기술 숙련 #{assigns.class_skill_count}개를 선택하세요."}
      true -> :ok
    end
  end

  defp validate_step(%{step: 2} = assigns) do
    if is_nil(assigns.selected_race), do: {:error, "종족을 선택하세요."}, else: :ok
  end

  defp validate_step(%{step: 3} = assigns) do
    cond do
      is_nil(assigns.selected_background) -> {:error, "배경을 선택하세요."}
      is_nil(assigns.bg_ability_2) and assigns.bg_ability_1 == [] -> {:error, "능력치 보너스를 배정하세요. (+2 하나 또는 +1 둘)"}
      assigns.bg_ability_1 != [] and length(assigns.bg_ability_1) < 2 -> {:error, "+1을 하나 더 배정하세요. (총 2곳)"}
      true -> :ok
    end
  end

  defp validate_step(%{step: 4} = assigns) do
    all_assigned = Enum.all?(@ability_keys, fn k -> not is_nil(assigns.abilities[k]) end)

    cond do
      assigns.ability_method == "roll" and is_nil(assigns.rolled_scores) ->
        {:error, "주사위를 굴려주세요."}
      not all_assigned ->
        {:error, "모든 능력치에 값을 배정하세요."}
      true -> :ok
    end
  end

  defp validate_step(%{step: 5}), do: :ok

  defp validate_step(%{step: 6} = assigns) do
    if assigns.is_spellcaster do
      cond do
        length(assigns.selected_cantrips) < assigns.cantrip_limit and assigns.cantrip_limit > 0 ->
          {:error, "소마법 #{assigns.cantrip_limit}개를 선택하세요."}
        length(assigns.selected_spells) < resolved_spell_limit(assigns) and resolved_spell_limit(assigns) > 0 ->
          {:error, "1레벨 주문 #{resolved_spell_limit(assigns)}개를 선택하세요."}
        true -> :ok
      end
    else
      :ok
    end
  end

  defp validate_step(%{step: 7} = assigns) do
    if assigns.character_name == "", do: {:error, "캐릭터 이름을 입력하세요."}, else: :ok
  end

  defp validate_step(_), do: :ok

  # ── Step preparation ───────────────────────────────────────────────────────

  defp maybe_prepare_step(socket, 6) do
    if socket.assigns.is_spellcaster do
      class_id = socket.assigns.selected_class["id"]
      class_en = socket.assigns.selected_class["nameEn"] || class_id

      cantrips = CharacterData.cantrips_for_class(class_en)
      spells = CharacterData.level1_spells_for_class(class_en)

      # spell_limit이 :wis_mod_plus_level 같은 동적 값이면 계산
      spell_limit =
        case @spellcasting_classes[class_id][:spells] do
          :wis_mod_plus_level ->
            wis = final_ability_score(socket.assigns, "wis")
            max(1, CharacterData.ability_modifier(wis) + 1)

          :int_mod_plus_level ->
            int = final_ability_score(socket.assigns, "int")
            max(1, CharacterData.ability_modifier(int) + 1)

          n when is_integer(n) -> n
          _ -> 0
        end

      socket
      |> assign(:available_cantrips, cantrips)
      |> assign(:available_spells, spells)
      |> assign(:spell_limit, spell_limit)
      |> assign(:selected_cantrips, [])
      |> assign(:selected_spells, [])
    else
      socket
    end
  end

  defp maybe_prepare_step(socket, _), do: socket

  # ── Build final character ──────────────────────────────────────────────────

  defp build_final_character(assigns) do
    abilities = final_abilities_map(assigns)

    # 장비 결정
    equipment = collect_equipment(assigns)

    # 주문 정보
    spells_data =
      if assigns.is_spellcaster do
        cantrip_names =
          assigns.selected_cantrips
          |> Enum.map(fn id ->
            spell = Enum.find(assigns.available_cantrips, &(&1["id"] == id))
            if spell, do: spell["nameKo"] || spell["name"], else: id
          end)

        spell_names =
          assigns.selected_spells
          |> Enum.map(fn id ->
            spell = Enum.find(assigns.available_spells, &(&1["id"] == id))
            if spell, do: spell["nameKo"] || spell["name"], else: id
          end)

        %{"cantrips" => cantrip_names, "prepared" => spell_names}
      else
        %{}
      end

    CharacterData.build_character_map(%{
      name: assigns.character_name,
      class_id: assigns.selected_class["id"],
      race_id: assigns.selected_race["id"],
      background_id: assigns.selected_background["id"],
      abilities: abilities,
      class_skills: assigns.class_skills,
      equipment: equipment,
      spells: spells_data,
      armor_choice: find_armor_in_equipment(equipment)
    })
    |> Map.put("alignment", assigns.alignment)
  end

  defp final_abilities_map(assigns) do
    base = assigns.abilities
    bg2 = assigns.bg_ability_2
    bg1 = assigns.bg_ability_1

    @ability_keys
    |> Map.new(fn key ->
      val = base[key] || 10
      val = if key == bg2, do: val + 2, else: val
      val = if key in bg1, do: val + 1, else: val
      {key, val}
    end)
  end

  defp final_ability_score(assigns, key) do
    base = assigns.abilities[key] || 10
    base = if assigns.bg_ability_2 == key, do: base + 2, else: base
    base = if key in assigns.bg_ability_1, do: base + 1, else: base
    base
  end

  defp resolved_spell_limit(assigns) do
    class_id = if assigns.selected_class, do: assigns.selected_class["id"], else: nil

    case @spellcasting_classes[class_id] do
      %{spells: :wis_mod_plus_level} ->
        wis = final_ability_score(assigns, "wis")
        max(1, CharacterData.ability_modifier(wis) + 1)

      %{spells: :int_mod_plus_level} ->
        int = final_ability_score(assigns, "int")
        max(1, CharacterData.ability_modifier(int) + 1)

      %{spells: n} when is_integer(n) -> n
      _ -> assigns.spell_limit
    end
  end

  defp collect_equipment(assigns) do
    class = assigns.selected_class
    bg = assigns.selected_background

    class_equip = get_equip_option_text(class, assigns.class_equip_choice)

    bg_equip =
      case assigns.bg_equip_choice do
        "A" -> get_in(bg, ["equipment", "optionA", "ko"]) || ""
        "B" -> get_in(bg, ["equipment", "optionB", "ko"]) || ""
        _ -> ""
      end

    # 간단하게 문자열 파싱: 쉼표로 분리
    (parse_equipment_string(class_equip) ++ parse_equipment_string(bg_equip))
    |> Enum.uniq()
  end

  defp get_equip_option_text(class, choice) do
    equip = class["startingEquipmentKo"] || class["startingEquipment"]

    case equip do
      [%{"options" => options} | _] ->
        target = "(#{choice})"
        Enum.find(options, "", fn opt -> String.starts_with?(opt, target) end)
        |> String.replace(~r/^\([A-Z]\)\s*/, "")

      _ -> ""
    end
  end

  defp parse_equipment_string(str) when is_binary(str) do
    str
    |> String.split(~r/,\s*/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
  defp parse_equipment_string(_), do: []

  defp find_armor_in_equipment(equipment) do
    armor_data = CharacterData.armor()

    armor_list =
      cond do
        is_map(armor_data) -> Map.get(armor_data, "armor", []) ++ Map.get(armor_data, "shields", [])
        is_list(armor_data) -> armor_data
        true -> []
      end

    Enum.find_value(equipment, nil, fn item ->
      Enum.find_value(armor_list, nil, fn a ->
        name_ko = a["nameKo"] || a["name"] || ""
        name_en = a["nameEn"] || a["name"] || ""
        if String.contains?(item, name_ko) or String.contains?(item, name_en), do: a["id"]
      end)
    end)
  end

  defp ability_en_to_key(name) do
    case String.downcase(name) do
      "strength" -> "str"
      "dexterity" -> "dex"
      "constitution" -> "con"
      "intelligence" -> "int"
      "wisdom" -> "wis"
      "charisma" -> "cha"
      _ -> nil
    end
  end

  # ── Render ─────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="cc-container">
      <header class="cc-header">
        <div class="cc-header-top">
          <h1>캐릭터 생성</h1>
          <a href={"/play/#{@campaign_id}"} class="cc-skip-link">AI에게 맡기기 →</a>
        </div>
        <div class="cc-steps">
          <%= for {num, label, _key} <- @steps do %>
            <div class={"cc-step-dot #{if num == @step, do: "active"} #{if num < @step, do: "done"}"}>
              <span class="cc-step-num"><%= num %></span>
              <span class="cc-step-label"><%= label %></span>
            </div>
          <% end %>
        </div>
      </header>

      <div class="cc-body">
        <%= if @error do %>
          <div class="cc-error"><%= @error %></div>
        <% end %>

        <%= case @step do %>
          <% 1 -> %>
            <.step_class {assigns} />
          <% 2 -> %>
            <.step_race {assigns} />
          <% 3 -> %>
            <.step_background {assigns} />
          <% 4 -> %>
            <.step_abilities {assigns} />
          <% 5 -> %>
            <.step_equipment {assigns} />
          <% 6 -> %>
            <.step_spells {assigns} />
          <% 7 -> %>
            <.step_summary {assigns} />
        <% end %>
      </div>

      <footer class="cc-footer">
        <%= if @step > 1 do %>
          <button class="cc-btn cc-btn-secondary" phx-click="prev_step">← 이전</button>
        <% else %>
          <a href="/" class="cc-btn cc-btn-secondary">취소</a>
        <% end %>

        <%= if @step < 7 do %>
          <button class="cc-btn cc-btn-primary" phx-click="next_step">다음 →</button>
        <% else %>
          <button class="cc-btn cc-btn-primary cc-btn-finish" phx-click="finish">캠페인 시작!</button>
        <% end %>
      </footer>
    </div>
    """
  end

  # ── Step 1: Class Selection ────────────────────────────────────────────────

  defp step_class(assigns) do
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
            <div class="cc-card-name"><%= class["name"] %></div>
            <div class="cc-card-name-en"><%= class["nameEn"] %></div>
            <div class="cc-card-meta">
              HP: <%= class["hitPointDie"] %> | 주 능력: <%= class["primaryAbilityKo"] || class["primaryAbility"] %>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @selected_class do %>
        <div class="cc-detail-box">
          <h3><%= @selected_class["name"] %> <span class="cc-en"><%= @selected_class["nameEn"] %></span></h3>
          <p class="cc-detail-desc"><%= String.slice(@selected_class["description"] || "", 0..300) %>...</p>

          <div class="cc-detail-stats">
            <div><strong>HP 주사위:</strong> <%= @selected_class["hitPointDie"] %></div>
            <div><strong>내성 굴림:</strong> <%= @selected_class["savingThrowProficienciesKo"] || @selected_class["savingThrowProficiencies"] %></div>
            <div><strong>무기 숙련:</strong> <%= @selected_class["weaponProficienciesKo"] || @selected_class["weaponProficiencies"] %></div>
            <div><strong>방어구 훈련:</strong> <%= @selected_class["armorTrainingKo"] || @selected_class["armorTraining"] %></div>
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

          <%= if @selected_class["startingEquipmentKo"] || @selected_class["startingEquipment"] do %>
            <div class="cc-equip-preview">
              <h4>시작 장비 옵션</h4>
              <%= for equip_group <- @selected_class["startingEquipmentKo"] || @selected_class["startingEquipment"] do %>
                <%= for opt <- (equip_group["options"] || []) do %>
                  <div class="cc-equip-option"><%= opt %></div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Step 2: Race Selection ─────────────────────────────────────────────────

  defp step_race(assigns) do
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
        <% r = @selected_race %>
        <div class="cc-detail-box">
          <h3><%= get_in(r, ["name", "ko"]) %> <span class="cc-en"><%= get_in(r, ["name", "en"]) %></span></h3>

          <div class="cc-detail-desc">
            <%= for para <- (get_in(r, ["description", "ko"]) || []) do %>
              <p><%= para %></p>
            <% end %>
          </div>

          <div class="cc-detail-stats">
            <div><strong>생물 유형:</strong> <%= get_in(r, ["basicTraits", "creatureType", "ko"]) %></div>
            <div><strong>크기:</strong> <%= get_in(r, ["basicTraits", "size", "ko"]) %></div>
            <div><strong>이동속도:</strong> <%= get_in(r, ["basicTraits", "speed", "ko"]) %></div>
          </div>

          <div class="cc-traits">
            <h4>종족 특성</h4>
            <%= for trait <- (r["traits"] || []) do %>
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

  # ── Step 3: Background Selection ───────────────────────────────────────────

  defp step_background(assigns) do
    ~H"""
    <div class="cc-step-content">
      <h2>3. 배경 선택</h2>
      <p class="cc-desc">모험을 떠나기 전, 당신은 어떤 삶을 살았나요?</p>

      <div class="cc-card-grid">
        <%= for bg <- @backgrounds do %>
          <div
            class={"cc-card #{if @selected_background && @selected_background["id"] == bg["id"], do: "selected"}"}
            phx-click="select_background"
            phx-value-id={bg["id"]}
          >
            <div class="cc-card-name"><%= bg["name"] %></div>
            <div class="cc-card-name-en"><%= bg["nameEn"] %></div>
            <div class="cc-card-meta">
              특기: <%= get_in(bg, ["feat", "name", "ko"]) || "" %>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @selected_background do %>
        <% bg = @selected_background %>
        <div class="cc-detail-box">
          <h3><%= bg["name"] %> <span class="cc-en"><%= bg["nameEn"] %></span></h3>
          <p class="cc-detail-desc"><%= get_in(bg, ["description", "ko"]) %></p>

          <div class="cc-detail-stats">
            <div><strong>기술 숙련:</strong> <%= Enum.join(get_in(bg, ["skillProficiencies", "ko"]) || [], ", ") %></div>
            <div><strong>도구 숙련:</strong> <%= get_in(bg, ["toolProficiency", "ko"]) %></div>
            <div><strong>출신 특기:</strong> <%= get_in(bg, ["feat", "name", "ko"]) %></div>
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
            <div class="cc-equip-option"><strong>A:</strong> <%= get_in(bg, ["equipment", "optionA", "ko"]) %></div>
            <div class="cc-equip-option"><strong>B:</strong> <%= get_in(bg, ["equipment", "optionB", "ko"]) %></div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Step 4: Ability Scores ─────────────────────────────────────────────────

  defp step_abilities(assigns) do
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
          <% bg_bonus = cond do
            @bg_ability_2 == key -> 2
            key in @bg_ability_1 -> 1
            true -> 0
          end %>
          <% final_val = if base_val, do: base_val + bg_bonus, else: nil %>
          <% mod = if final_val, do: CharacterData.ability_modifier(final_val), else: nil %>

          <div class="cc-ability-card">
            <div class="cc-ability-name"><%= name %></div>

            <%= if base_val do %>
              <div class="cc-ability-value" phx-click="clear_ability" phx-value-key={key} title="클릭하여 초기화">
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
                    <button class="cc-score-btn" phx-click="assign_ability" phx-value-key={key} phx-value-score={score}>
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
        <p class="cc-hint">표준 배열: 15, 14, 13, 12, 10, 8 — 각 능력치에 하나씩 배정하세요. 배정된 값을 클릭하면 초기화됩니다.</p>
      <% end %>
    </div>
    """
  end

  # ── Step 5: Equipment ──────────────────────────────────────────────────────

  defp step_equipment(assigns) do
    ~H"""
    <div class="cc-step-content">
      <h2>5. 장비 선택</h2>

      <%= if @selected_class do %>
        <div class="cc-equip-section">
          <h3>클래스 시작 장비</h3>
          <div class="cc-equip-choices">
            <%= for equip_group <- (@selected_class["startingEquipmentKo"] || @selected_class["startingEquipment"] || []) do %>
              <%= for opt <- (equip_group["options"] || []) do %>
                <% choice = case Regex.run(~r/^\(([A-Z])\)/, opt) do
                  [_, letter] -> letter
                  _ -> opt
                end %>
                <button
                  class={"cc-equip-btn #{if @class_equip_choice == choice, do: "selected"}"}
                  phx-click="set_class_equip"
                  phx-value-choice={choice}
                >
                  <%= opt %>
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

  # ── Step 6: Spells ─────────────────────────────────────────────────────────

  defp step_spells(assigns) do
    ~H"""
    <div class="cc-step-content">
      <h2>6. 주문 선택</h2>

      <%= if not @is_spellcaster do %>
        <div class="cc-no-spells">
          <p><%= if @selected_class, do: @selected_class["name"], else: "선택한 클래스" %>은(는) 1레벨에서 주문을 사용하지 않습니다.</p>
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
                  <div class="cc-spell-name"><%= spell["nameKo"] || spell["name"] %></div>
                  <div class="cc-spell-name-en"><%= spell["name"] %></div>
                  <div class="cc-spell-meta">
                    <%= spell["castingTimeKo"] || spell["castingTime"] %> |
                    <%= spell["rangeKo"] || spell["range"] %>
                  </div>
                  <div class="cc-spell-desc"><%= String.slice(spell["descriptionKo"] || spell["description"] || "", 0..100) %>...</div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <% spell_lim = resolved_spell_limit(assigns) %>
        <%= if spell_lim > 0 do %>
          <div class="cc-spell-section">
            <h3>1레벨 주문 선택 (<%= length(@selected_spells) %>/<%= spell_lim %>)</h3>
            <div class="cc-spell-grid">
              <%= for spell <- @available_spells do %>
                <div
                  class={"cc-spell-card #{if spell["id"] in @selected_spells, do: "selected"}"}
                  phx-click="toggle_spell"
                  phx-value-id={spell["id"]}
                >
                  <div class="cc-spell-name"><%= spell["nameKo"] || spell["name"] %></div>
                  <div class="cc-spell-name-en"><%= spell["name"] %></div>
                  <div class="cc-spell-meta">
                    <%= spell["castingTimeKo"] || spell["castingTime"] %> |
                    <%= spell["rangeKo"] || spell["range"] %> |
                    <%= if spell["concentration"], do: "집중", else: spell["durationKo"] || spell["duration"] %>
                  </div>
                  <div class="cc-spell-desc"><%= String.slice(spell["descriptionKo"] || spell["description"] || "", 0..100) %>...</div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # ── Step 7: Summary ────────────────────────────────────────────────────────

  defp step_summary(assigns) do
    # 최종 능력치 계산
    final_abs =
      Map.new(@ability_keys, fn key ->
        base = assigns.abilities[key] || 10
        bonus = cond do
          assigns.bg_ability_2 == key -> 2
          key in assigns.bg_ability_1 -> 1
          true -> 0
        end
        {key, base + bonus}
      end)

    assigns = assign(assigns, :final_abilities, final_abs)

    ~H"""
    <div class="cc-step-content">
      <h2>7. 캐릭터 완성</h2>

      <div class="cc-name-input">
        <label>캐릭터 이름</label>
        <input type="text" value={@character_name} placeholder="이름을 입력하세요"
          phx-keyup="set_name" phx-debounce="300" />
      </div>

      <div class="cc-alignment-select">
        <label>성향</label>
        <select phx-change="set_alignment" name="alignment">
          <%= for al <- ["질서 선", "중립 선", "혼돈 선", "질서 중립", "순수 중립", "혼돈 중립", "질서 악", "중립 악", "혼돈 악"] do %>
            <option value={al} selected={al == @alignment}><%= al %></option>
          <% end %>
        </select>
      </div>

      <div class="cc-summary-sheet">
        <div class="cc-summary-header">
          <h3><%= if @character_name != "", do: @character_name, else: "???" %></h3>
          <p>
            <%= if @selected_race, do: get_in(@selected_race, ["name", "ko"]), else: "?" %>
            <%= if @selected_class, do: @selected_class["name"], else: "?" %>
            Lv.1
            | 배경: <%= if @selected_background, do: @selected_background["name"], else: "?" %>
          </p>
        </div>

        <div class="cc-summary-abilities">
          <%= for key <- @ability_keys do %>
            <% val = @final_abilities[key] %>
            <% mod = CharacterData.ability_modifier(val) %>
            <div class="cc-summary-ability">
              <div class="cc-summary-ab-name"><%= @ability_names[key] %></div>
              <div class="cc-summary-ab-val"><%= val %></div>
              <div class="cc-summary-ab-mod"><%= if mod >= 0, do: "+#{mod}", else: mod %></div>
            </div>
          <% end %>
        </div>

        <div class="cc-summary-stats">
          <% con_mod = CharacterData.ability_modifier(@final_abilities["con"]) %>
          <% hit_die = if @selected_class, do: parse_hit_die_val(@selected_class["hitPointDie"]), else: 8 %>
          <% hp = hit_die + con_mod %>
          <div class="cc-summary-stat">
            <span class="cc-stat-label">HP</span>
            <span class="cc-stat-value"><%= hp %></span>
          </div>
          <% dex_mod = CharacterData.ability_modifier(@final_abilities["dex"]) %>
          <% equipment = collect_equipment(assigns) %>
          <% armor_id = find_armor_in_equipment(equipment) %>
          <% ac = if armor_id do
            armor_data = CharacterData.armor()
            flat_list = cond do
              is_map(armor_data) -> Map.get(armor_data, "armor", []) ++ Map.get(armor_data, "shields", [])
              is_list(armor_data) -> armor_data
              true -> []
            end
            a = Enum.find(flat_list, &(&1["id"] == armor_id))
            if a, do: compute_summary_ac(a["ac"], dex_mod), else: 10 + dex_mod
          else
            10 + dex_mod
          end %>
          <div class="cc-summary-stat">
            <span class="cc-stat-label">AC</span>
            <span class="cc-stat-value"><%= ac %></span>
          </div>
          <div class="cc-summary-stat">
            <span class="cc-stat-label">이동속도</span>
            <span class="cc-stat-value"><%= if @selected_race, do: get_in(@selected_race, ["basicTraits", "speed", "ko"]) || "30피트", else: "30피트" %></span>
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
              <p><%= @selected_cantrips |> Enum.map(fn id -> find_spell_name(@available_cantrips, id) end) |> Enum.join(", ") %></p>
            </div>
          <% end %>

          <%= if @is_spellcaster and @selected_spells != [] do %>
            <div class="cc-summary-block">
              <h4>1레벨 주문</h4>
              <p><%= @selected_spells |> Enum.map(fn id -> find_spell_name(@available_spells, id) end) |> Enum.join(", ") %></p>
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
      spell -> spell["nameKo"] || spell["name"]
    end
  end

  defp compute_summary_ac(ac_str, dex_mod) when is_binary(ac_str) do
    cond do
      match = Regex.run(~r/^(\d+)\s*\+\s*Dex modifier\s*\(max\s*(\d+)\)/i, ac_str) ->
        [_, base_str, max_str] = match
        String.to_integer(base_str) + min(dex_mod, String.to_integer(max_str))

      match = Regex.run(~r/^(\d+)\s*\+\s*Dex modifier/i, ac_str) ->
        [_, base_str] = match
        String.to_integer(base_str) + dex_mod

      match = Regex.run(~r/^(\d+)$/, String.trim(ac_str)) ->
        [_, base_str] = match
        String.to_integer(base_str)

      true ->
        10 + dex_mod
    end
  end
  defp compute_summary_ac(_, dex_mod), do: 10 + dex_mod

  defp parse_hit_die_val(nil), do: 8
  defp parse_hit_die_val(str) do
    case Regex.run(~r/[Dd](\d+)/, str) do
      [_, num] -> String.to_integer(num)
      _ -> 8
    end
  end
end
