defmodule TrpgMaster.Campaign.Summarizer.Request do
  @moduledoc false

  alias TrpgMaster.Campaign.Summarizer.{ModelPolicy, Prompts}

  @session_system "You are a D&D session scribe."
  @context_system "You are a TRPG session summarizer."
  @combat_system "You are a TRPG combat summarizer."

  def session(state) do
    build_request(
      @session_system,
      ModelPolicy.summary_model_for(state.ai_model),
      1024,
      [%{"role" => "user", "content" => Prompts.session_summary_prompt(state)}] ++
        Prompts.recent_combined_history(state)
    )
  end

  def context(state) do
    case assistant_messages(state.exploration_history) do
      [] ->
        :skip

      ai_messages ->
        previous_summary = state.context_summary || "(첫 번째 턴 — 이전 요약 없음)"

        build_request(
          @context_system,
          ModelPolicy.summary_model_for(state.ai_model),
          800,
          [
            %{
              "role" => "user",
              "content" => Prompts.context_summary_prompt(previous_summary, ai_messages)
            }
          ]
        )
    end
  end

  def combat_history(state) do
    case assistant_messages(state.combat_history) do
      [] ->
        nil

      ai_messages ->
        previous_summary = state.combat_history_summary || "(전투 시작 — 이전 요약 없음)"

        build_request(
          @combat_system,
          ModelPolicy.summary_model_for(state.ai_model),
          600,
          [
            %{
              "role" => "user",
              "content" =>
                Prompts.combat_history_summary_prompt(previous_summary, ai_messages, state)
            }
          ]
        )
    end
  end

  def post_combat(state) do
    case assistant_messages(state.combat_history) do
      [] ->
        nil

      ai_messages ->
        build_request(
          @combat_system,
          ModelPolicy.summary_model_for(state.ai_model),
          800,
          [
            %{
              "role" => "user",
              "content" => Prompts.post_combat_summary_prompt(ai_messages, state)
            }
          ]
        )
    end
  end

  defp build_request(system, model, max_tokens, messages) do
    %{
      system: system,
      model: model,
      max_tokens: max_tokens,
      messages: messages
    }
  end

  defp assistant_messages(history) do
    Enum.filter(history, fn
      %{"role" => "assistant"} -> true
      _ -> false
    end)
  end
end
