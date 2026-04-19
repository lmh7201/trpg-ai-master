defmodule TrpgMasterWeb.CharacterCreateLive do
  use TrpgMasterWeb, :live_view

  import TrpgMasterWeb.CharacterCreateComponents

  alias TrpgMasterWeb.{CharacterCreateActions, CharacterCreateSession}

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
  def handle_event(event, params, socket) do
    {:noreply, apply_action(socket, CharacterCreateActions.handle(event, params, socket.assigns))}
  end

  defp apply_action(socket, {:assign, updates}), do: assign(socket, updates)
  defp apply_action(socket, {:navigate, path}), do: push_navigate(socket, to: path)
  defp apply_action(socket, :ignore), do: socket

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
