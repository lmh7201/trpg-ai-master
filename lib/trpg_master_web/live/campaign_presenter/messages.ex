defmodule TrpgMasterWeb.CampaignPresenter.Messages do
  @moduledoc false

  def display_messages(conversation_history) do
    Enum.reduce(conversation_history, [], fn msg, acc ->
      case msg do
        %{"role" => "user", "synthetic" => true} ->
          acc

        %{"role" => "user", "content" => content} when is_binary(content) ->
          acc ++ [%{type: :player, text: content}]

        %{"role" => "assistant", "content" => content} when is_binary(content) ->
          acc ++ [%{type: :dm, text: content}]

        _ ->
          acc
      end
    end)
  end
end
