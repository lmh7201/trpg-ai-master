defmodule TrpgMaster.AI.PromptBuilder.Messages do
  @moduledoc false

  alias TrpgMaster.Campaign.State

  require Logger

  @max_history_tokens 12_000
  @recent_window_size 5

  def build_messages(history) when is_list(history) do
    total = estimate_tokens(history)

    if total <= @max_history_tokens do
      history
    else
      {recent, _remaining} =
        history
        |> Enum.reverse()
        |> Enum.reduce_while({[], @max_history_tokens}, fn msg, {acc, remaining} ->
          tokens = estimate_tokens_msg(msg) + 10

          if tokens <= remaining do
            {:cont, {[msg | acc], remaining - tokens}}
          else
            {:halt, {acc, 0}}
          end
        end)

      trimmed_count = length(history) - length(recent)

      if trimmed_count > 0 do
        Logger.info(
          "히스토리 트리밍: #{length(history)}개 → #{length(recent)}개 (#{trimmed_count}개 제거, 추정 토큰: #{total})"
        )
      end

      recent
    end
  end

  def build_messages_with_summary(current_message, _context_summary, conversation_history \\ []) do
    recent = Enum.take(conversation_history, -@recent_window_size)
    ensure_valid_turn_order(recent) ++ [%{"role" => "user", "content" => current_message}]
  end

  def build_turn_messages(%State{} = state, current_message, opts \\ []) do
    case state.phase do
      :combat ->
        build_combat_turn_messages(state, current_message, opts)

      _ ->
        build_exploration_turn_messages(state, current_message)
    end
  end

  defp build_exploration_turn_messages(state, current_message) do
    recent = Enum.take(state.exploration_history, -@recent_window_size)
    ensure_valid_turn_order(recent) ++ [%{"role" => "user", "content" => current_message}]
  end

  defp build_combat_turn_messages(state, _current_message, _opts) do
    exploration_recent = Enum.take(state.exploration_history, -@recent_window_size)

    current_round_msgs =
      state.combat_history
      |> Enum.drop(state.current_round_start_index)
      |> Enum.map(&Map.delete(&1, "synthetic"))

    ensure_valid_turn_order(exploration_recent) ++ current_round_msgs
  end

  defp ensure_valid_turn_order([%{"role" => "assistant"} | rest]), do: rest
  defp ensure_valid_turn_order(messages), do: messages

  defp estimate_tokens(text) when is_binary(text) do
    total_chars = String.length(text)

    if total_chars == 0 do
      0
    else
      byte_size = byte_size(text)
      multibyte_chars = byte_size - total_chars
      korean_ratio = min(multibyte_chars / max(byte_size, 1), 1.0)

      chars_per_token = 2.0 * korean_ratio + 4.0 * (1.0 - korean_ratio)
      tokens = ceil(total_chars / chars_per_token)

      tokens + 4
    end
  end

  defp estimate_tokens(messages) when is_list(messages) do
    Enum.sum(Enum.map(messages, &(estimate_tokens_msg(&1) + 10)))
  end

  defp estimate_tokens_msg(%{"content" => content}) when is_binary(content) do
    estimate_tokens(content)
  end

  defp estimate_tokens_msg(_), do: 10
end
