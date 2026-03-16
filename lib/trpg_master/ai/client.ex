defmodule TrpgMaster.AI.Client do
  @moduledoc """
  AI 프로바이더 facade.
  모델에 따라 적절한 프로바이더 모듈로 요청을 위임한다.
  """

  alias TrpgMaster.AI.Models

  @doc """
  AI API에 메시지를 보내고 응답을 받는다.
  모델 설정에 따라 Anthropic, OpenAI, Gemini 중 하나로 요청을 보낸다.

  옵션:
    - model: 사용할 모델 ID (기본값: 설정된 기본 모델)
    - max_tokens: 최대 출력 토큰 (기본값: 4096)

  반환값:
    {:ok, %{text: String.t(), tool_results: [map()], usage: map()}}
    {:error, term()}
  """
  def chat(system_prompt, messages, tools \\ [], opts \\ []) do
    model_id = Keyword.get(opts, :model, Models.default_model())

    case Models.find(model_id) do
      nil ->
        {:error, :unknown_model}

      model_info ->
        if Models.api_key_configured?(model_id) do
          provider_module(model_info.provider).chat(system_prompt, messages, tools, opts)
        else
          {:error, {:no_api_key, model_info.env}}
        end
    end
  end

  defp provider_module(:anthropic), do: TrpgMaster.AI.Providers.Anthropic
  defp provider_module(:openai), do: TrpgMaster.AI.Providers.OpenAI
  defp provider_module(:gemini), do: TrpgMaster.AI.Providers.Gemini

  @doc """
  API 에러 atom/tuple을 사용자 친화적인 한국어 메시지로 변환한다.
  """
  def format_error(:no_api_key), do: "API 키가 설정되지 않았습니다."
  def format_error({:no_api_key, env_var}), do: "#{env_var} API 키가 설정되지 않았습니다."
  def format_error(:unknown_model), do: "알 수 없는 AI 모델입니다."
  def format_error(:invalid_api_key), do: "API 키가 올바르지 않습니다. 설정을 확인해주세요."
  def format_error(:timeout), do: "AI 응답이 너무 오래 걸리고 있습니다. 다시 시도해주세요."
  def format_error(:connection_failed), do: "네트워크 연결에 실패했습니다. 인터넷 연결을 확인해주세요."
  def format_error(:max_tool_iterations), do: "도구 실행이 너무 많아 중단되었습니다. 다시 시도해주세요."
  def format_error(:rate_limited), do: "요청이 너무 많습니다. 잠시 후 다시 시도해주세요."

  def format_error({:api_error, 400, body}) do
    msg = get_in(body, ["error", "message"]) || ""

    if String.contains?(msg, "token") do
      "대화가 너무 길어져서 이전 대화를 정리했습니다. 계속 진행해주세요."
    else
      "요청 오류가 발생했습니다. 다시 시도해주세요."
    end
  end

  def format_error({:api_error, 429, _}), do: "요청이 너무 많습니다. 잠시 후 다시 시도해주세요."

  def format_error({:api_error, status, _}) when status in [500, 529],
    do: "일시적인 오류가 발생했습니다. 잠시 후 다시 시도해주세요."

  def format_error({:api_error, status, _}), do: "API 오류 (#{status}). 다시 시도해주세요."

  def format_error(reason) when is_binary(reason), do: reason
  def format_error(reason), do: "오류가 발생했습니다: #{inspect(reason)}"
end
