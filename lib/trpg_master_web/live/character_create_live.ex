defmodule TrpgMasterWeb.CharacterCreateLive do
  use TrpgMasterWeb, :live_view

  import TrpgMasterWeb.CharacterCreateComponents

  require Logger

  alias TrpgMasterWeb.CharacterCreateSession
  alias TrpgMasterWeb.CharacterCreateFlow

  # ── Mount ──────────────────────────────────────────────────────────────────

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case CharacterCreateSession.mount_assigns(id) do
      {:navigate, path} ->
        {:ok, push_navigate(socket, to: path)}

      {:ok, assigns} ->
        {:ok, assign(socket, assigns)}
    end
  end

  # ── Events ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("select_class", %{"id" => class_id}, socket) do
    {:noreply, assign(socket, CharacterCreateSession.select_class(class_id))}
  end

  def handle_event("toggle_class_skill", %{"skill" => skill}, socket) do
    {:noreply, assign(socket, CharacterCreateFlow.toggle_class_skill(socket.assigns, skill))}
  end

  def handle_event("select_race", %{"id" => race_id}, socket) do
    {:noreply, assign(socket, CharacterCreateSession.select_race(race_id))}
  end

  def handle_event("select_background", %{"id" => bg_id}, socket) do
    {:noreply, assign(socket, CharacterCreateSession.select_background(bg_id))}
  end

  def handle_event("set_bg_ability", %{"rank" => rank, "key" => key}, socket) do
    {:noreply, assign(socket, CharacterCreateFlow.set_bg_ability(socket.assigns, rank, key))}
  end

  def handle_event("set_ability_method", %{"method" => method}, socket) do
    {:noreply, assign(socket, CharacterCreateFlow.set_ability_method(method))}
  end

  def handle_event("assign_ability", %{"key" => key, "score" => score_str}, socket) do
    case CharacterCreateFlow.assign_ability(socket.assigns, key, score_str) do
      {:ok, updates} ->
        {:noreply, assign(socket, updates)}

      :ignore ->
        {:noreply, socket}
    end
  end

  def handle_event("clear_ability", %{"key" => key}, socket) do
    {:noreply, assign(socket, CharacterCreateFlow.clear_ability(socket.assigns, key))}
  end

  def handle_event("roll_abilities", _params, socket) do
    {:noreply, assign(socket, CharacterCreateFlow.roll_abilities())}
  end

  def handle_event("set_class_equip", %{"choice" => choice}, socket) do
    {:noreply, assign(socket, CharacterCreateFlow.set_class_equip(choice))}
  end

  def handle_event("set_bg_equip", %{"choice" => choice}, socket) do
    {:noreply, assign(socket, CharacterCreateFlow.set_bg_equip(choice))}
  end

  def handle_event("toggle_cantrip", %{"id" => spell_id}, socket) do
    {:noreply, assign(socket, CharacterCreateFlow.toggle_cantrip(socket.assigns, spell_id))}
  end

  def handle_event("toggle_spell", %{"id" => spell_id}, socket) do
    {:noreply, assign(socket, CharacterCreateFlow.toggle_spell(socket.assigns, spell_id))}
  end

  def handle_event("set_name", params, socket),
    do: {:noreply, assign(socket, CharacterCreateFlow.set_name(field_value(params, "name")))}

  def handle_event("set_alignment", params, socket),
    do:
      {:noreply,
       assign(socket, CharacterCreateFlow.set_alignment(field_value(params, "alignment")))}

  def handle_event("set_appearance", %{"value" => val}, socket) do
    {:noreply, assign(socket, CharacterCreateFlow.set_appearance(val))}
  end

  def handle_event("set_backstory", %{"value" => val}, socket) do
    {:noreply, assign(socket, CharacterCreateFlow.set_backstory(val))}
  end

  def handle_event("show_detail", %{"type" => type, "id" => id}, socket) do
    {:noreply, assign(socket, CharacterCreateFlow.show_detail(type, id))}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, CharacterCreateFlow.close_detail())}
  end

  def handle_event("next_step", _params, socket) do
    {:noreply, apply_update_result(socket, CharacterCreateFlow.next_step(socket.assigns))}
  end

  def handle_event("prev_step", _params, socket) do
    {:noreply, assign(socket, CharacterCreateFlow.prev_step(socket.assigns))}
  end

  def handle_event("finish", _params, socket) do
    case CharacterCreateSession.finish(socket.assigns) do
      {:ok, campaign_id} ->
        {:noreply, push_navigate(socket, to: "/play/#{campaign_id}")}

      {:error, message} ->
        {:noreply, assign(socket, :error, message)}
    end
  end

  defp apply_update_result(socket, {:ok, updates}), do: assign(socket, updates)
  defp apply_update_result(socket, {:error, updates}), do: assign(socket, updates)

  defp field_value(params, key) do
    Map.get(params, key) || Map.get(params, "value") || ""
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
