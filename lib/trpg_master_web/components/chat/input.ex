defmodule TrpgMasterWeb.Chat.Input do
  @moduledoc false

  use TrpgMasterWeb, :html

  @doc """
  채팅 입력 폼 컴포넌트.
  """
  attr(:input_text, :string, default: "")
  attr(:loading, :boolean, default: false)
  attr(:processing, :boolean, default: false)

  def chat_input(assigns) do
    ~H"""
    <form class="input-area" phx-submit="send_message" id="message-form">
      <textarea
        name="message"
        placeholder={if @processing, do: "DM이 응답을 준비하는 중...", else: "무엇을 하시겠습니까? (Shift+Enter로 줄바꿈)"}
        autocomplete="off"
        autocorrect="off"
        autocapitalize="off"
        spellcheck="false"
        disabled={@loading || @processing}
        rows="1"
        phx-hook="AutoResize"
        id="message-input"
      ><%= @input_text %></textarea>
      <button type="submit" disabled={@loading} aria-label="전송">
        <span>↑</span>
      </button>
    </form>
    """
  end
end
