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
    <.wizard_shell {assigns}>
      <%!-- 단계 본문은 LiveView가 선택하고, shell은 공통 레이아웃만 담당한다. --%>
      <div>
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
    </.wizard_shell>
    """
  end
end
