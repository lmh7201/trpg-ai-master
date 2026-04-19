defmodule TrpgMaster.Campaign.Summarizer.ModelPolicy do
  @moduledoc false

  alias TrpgMaster.AI.Models

  @default_summary_model "claude-haiku-4-5-20251001"

  def summary_model_for(nil), do: @default_summary_model

  def summary_model_for(model_id) do
    case Models.provider_for(model_id) do
      :anthropic -> @default_summary_model
      :openai -> "gpt-5.4-mini"
      :gemini -> "gemini-2.5-flash"
      _ -> @default_summary_model
    end
  end
end
