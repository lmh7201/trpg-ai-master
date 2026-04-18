defmodule TrpgMasterWeb.CampaignFlow do
  @moduledoc """
  CampaignLive의 화면 상태 전이와 메시지 조립을 담당한다.
  """

  alias TrpgMaster.AI.{Client, Models}
  alias TrpgMasterWeb.CampaignPresenter

  def submit_message(assigns, message) when is_binary(message) do
    trimmed = String.trim(message)

    cond do
      trimmed == "" ->
        :ignore

      assigns.processing ->
        :ignore

      true ->
        updates = %{
          messages: assigns.messages ++ [%{type: :player, text: trimmed}],
          input_text: "",
          loading: true,
          processing: true,
          error: nil,
          last_player_message: trimmed
        }

        {:ok, updates, trimmed}
    end
  end

  def submit_message(_assigns, _message), do: :ignore

  def retry_last(assigns) do
    case assigns.last_player_message do
      nil ->
        :ignore

      message ->
        {:ok, %{loading: true, error: nil}, message}
    end
  end

  def next_mode(:adventure), do: :debug
  def next_mode(_mode), do: :adventure

  def toggle_model_selector(assigns) do
    %{show_model_selector: !assigns.show_model_selector}
  end

  def select_model(assigns, model_id) do
    if Models.api_key_configured?(model_id) do
      model_info = Models.find(model_id)
      model_name = if model_info, do: model_info.name, else: model_id

      notice_msg = %{type: :system, text: "🤖 DM이 #{model_name}(으)로 변경되었습니다."}

      {:ok,
       %{
         ai_model: model_id,
         show_model_selector: false,
         messages: assigns.messages ++ [notice_msg]
       }}
    else
      model_info = Models.find(model_id)
      env_var = if model_info, do: model_info.env, else: "API 키"

      notice_msg = %{
        type: :system,
        text: "⚠️ #{env_var} 환경변수가 설정되지 않았습니다. 서버 관리자에게 문의하세요."
      }

      {:error,
       %{
         show_model_selector: false,
         messages: assigns.messages ++ [notice_msg]
       }}
    end
  end

  def begin_end_session do
    %{ending_session: true, loading: true}
  end

  def apply_player_action_result(assigns, [player_result | enemy_results], state)
      when enemy_results != [] do
    updates =
      state
      |> CampaignPresenter.state_assigns()
      |> Map.merge(%{
        messages: append_result_messages(assigns, player_result),
        loading: true
      })

    {:enemy_turns, updates, enemy_results}
  end

  def apply_player_action_result(assigns, result, state) when not is_list(result) do
    updates =
      state
      |> CampaignPresenter.state_assigns()
      |> Map.merge(%{
        messages: append_result_messages(assigns, result),
        loading: false,
        processing: false
      })

    {:done, updates}
  end

  def apply_player_action_error(reason) do
    %{
      loading: false,
      processing: false,
      error: Client.format_error(reason)
    }
  end

  def apply_enemy_turn(assigns, result, [], state) do
    updates =
      state
      |> CampaignPresenter.state_assigns()
      |> Map.merge(%{
        messages: append_result_messages(assigns, result),
        loading: false,
        processing: false
      })

    {:done, updates}
  end

  def apply_enemy_turn(assigns, result, rest, state) do
    updates =
      state
      |> CampaignPresenter.state_assigns()
      |> Map.merge(%{
        messages: append_result_messages(assigns, result),
        loading: true,
        processing: true
      })

    {:continue, updates, rest}
  end

  def apply_end_session_result(assigns, {:ok, summary_text}) do
    %{
      messages:
        assigns.messages ++
          [
            %{type: :system, text: "📋 세션이 종료되었습니다. 대화 기록이 저장되었습니다."},
            %{type: :dm, text: summary_text}
          ],
      loading: false,
      ending_session: false
    }
  end

  def apply_end_session_result(_assigns, {:error, reason}) do
    %{
      loading: false,
      ending_session: false,
      error: "세션 종료 실패: #{Client.format_error(reason)}"
    }
  end

  defp append_result_messages(assigns, result) do
    assigns.messages
    |> CampaignPresenter.append_tool_messages(assigns.mode, result)
    |> Kernel.++([%{type: :dm, text: result.text}])
  end
end
