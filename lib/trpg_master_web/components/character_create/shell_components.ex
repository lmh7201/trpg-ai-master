defmodule TrpgMasterWeb.CharacterCreate.ShellComponents do
  @moduledoc false

  use TrpgMasterWeb, :html

  attr(:campaign_id, :string, required: true)
  attr(:step, :integer, required: true)
  attr(:steps, :list, required: true)
  attr(:error, :string, default: nil)
  slot(:inner_block, required: true)

  def wizard_shell(assigns) do
    ~H"""
    <div class="cc-container">
      <header class="cc-header">
        <div class="cc-header-top">
          <h1>캐릭터 생성</h1>
          <a href={"/play/#{@campaign_id}"} class="cc-skip-link">AI에게 맡기기 →</a>
        </div>
        <div class="cc-steps">
          <%= for {num, label, _key} <- @steps do %>
            <div class={step_dot_class(num, @step)}>
              <span class="cc-step-num"><%= num %></span>
              <span class="cc-step-label"><%= label %></span>
            </div>
          <% end %>
        </div>
      </header>

      <div class="cc-body">
        <div :if={@error} class="cc-error"><%= @error %></div>
        <%= render_slot(@inner_block) %>
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

  defp step_dot_class(num, current_step) do
    "cc-step-dot #{if num == current_step, do: "active"} #{if num < current_step, do: "done"}"
  end
end
