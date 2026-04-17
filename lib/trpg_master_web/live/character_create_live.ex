defmodule TrpgMasterWeb.CharacterCreateLive do
  use TrpgMasterWeb, :live_view

  import TrpgMasterWeb.CharacterCreateComponents

  require Logger

  alias TrpgMaster.Campaign.{Manager, Server}
  alias TrpgMaster.Characters.Creation
  alias TrpgMaster.Rules.CharacterData

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
    form_state =
      Creation.initial_state(classes, CharacterData.races(), CharacterData.backgrounds())

    socket =
      socket
      |> assign(:campaign_id, id)
      |> assign(form_state)

    {:ok, socket}
  end

  # ── Events ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("select_class", %{"id" => class_id}, socket) do
    class = CharacterData.get_class(class_id)
    {:noreply, assign(socket, Creation.class_selection(class))}
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
    {:noreply, assign(socket, Creation.background_selection(bg))}
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
    {:noreply, assign(socket, Creation.ability_method_updates(method))}
  end

  def handle_event("assign_ability", %{"key" => key, "score" => score_str}, socket) do
    case Integer.parse(score_str) do
      {value, _} ->
        {:noreply, assign(socket, Creation.assign_ability(socket.assigns, key, value))}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("clear_ability", %{"key" => key}, socket) do
    {:noreply, assign(socket, Creation.clear_ability(socket.assigns, key))}
  end

  def handle_event("roll_abilities", _params, socket) do
    {:noreply, assign(socket, Creation.roll_abilities())}
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
    limit = Creation.resolved_spell_limit(socket.assigns)

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

  def handle_event("set_appearance", %{"value" => val}, socket) do
    {:noreply, assign(socket, :appearance, val)}
  end

  def handle_event("set_backstory", %{"value" => val}, socket) do
    {:noreply, assign(socket, :backstory, val)}
  end

  def handle_event("show_detail", %{"type" => type, "id" => id}, socket) do
    {:noreply, assign(socket, :detail_panel, %{type: type, id: id})}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, :detail_panel, nil)}
  end

  def handle_event("next_step", _params, socket) do
    case Creation.validate_step(socket.assigns) do
      :ok ->
        new_step = min(socket.assigns.step + 1, 7)
        step_updates = Creation.prepare_step(socket.assigns, new_step)

        socket =
          socket
          |> assign(:step, new_step)
          |> assign(:error, nil)
          |> assign(step_updates)

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
    case Creation.validate_step(socket.assigns) do
      :ok ->
        character = Creation.build_character(socket.assigns)
        campaign_id = socket.assigns.campaign_id

        Server.set_character(campaign_id, character)

        {:noreply, push_navigate(socket, to: "/play/#{campaign_id}")}

      {:error, msg} ->
        {:noreply, assign(socket, :error, msg)}
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
            <.class_step {assigns} />
          <% 2 -> %>
            <.race_step {assigns} />
          <% 3 -> %>
            <.background_step {assigns} />
          <% 4 -> %>
            <.abilities_step {assigns} />
          <% 5 -> %>
            <.equipment_step {assigns} />
          <% 6 -> %>
            <.spells_step {assigns} />
          <% 7 -> %>
            <.summary_step {assigns} />
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
end
