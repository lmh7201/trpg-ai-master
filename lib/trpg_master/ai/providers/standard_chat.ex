defmodule TrpgMaster.AI.Providers.StandardChat do
  @moduledoc """
  OpenAI/Gemini처럼 공통 재시도 정책과 tool loop를 공유하는 provider 실행기.
  """

  alias TrpgMaster.AI.Providers.Retry
  require Logger

  @doc """
  공통 chat loop를 실행한다.

  필수 옵션:
    - `:provider` - 로그에 사용할 provider 이름
    - `:body` - 초기 request body
    - `:context` - API 호출에 필요한 고정 컨텍스트
    - `:call_api` - `(context, body -> {:ok, response} | {:error, reason})`
    - `:response_module` - `tool_loop?/1`, `tool_calls/1`, `append_tool_results/3`, `completion_text/1`
    - `:execute_tools` - `(tool_calls -> {tool_results, provider_payloads})`
    - `:usage_info` - `(response, current_usage -> %{usage: map(), log: String.t()})`
    - `:retry_rules` - `Retry.handle/4`에 전달할 규칙 목록
  """
  def run(opts) do
    state = %{
      body: Keyword.fetch!(opts, :body),
      tool_results: Keyword.get(opts, :tool_results, []),
      usage: Keyword.get(opts, :initial_usage, %{input_tokens: 0, output_tokens: 0})
    }

    do_chat_with_retry(
      Keyword.fetch!(opts, :context),
      state,
      0,
      Keyword.get(opts, :max_tool_iterations, 20),
      opts
    )
  end

  defp do_chat_with_retry(context, state, retry_count, max_tool_iterations, opts) do
    case do_chat_loop(context, state, max_tool_iterations, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason, latest_state} ->
        handle_api_error(context, latest_state, reason, retry_count, max_tool_iterations, opts)
    end
  end

  defp handle_api_error(context, state, reason, retry_count, max_tool_iterations, opts) do
    retry_opts =
      Keyword.merge(
        [rules: Keyword.fetch!(opts, :retry_rules)],
        Keyword.get(opts, :retry_opts, [])
      )

    case Retry.handle(reason, retry_count, state, retry_opts) do
      {:retry, updated_state, next_retry_count} ->
        do_chat_with_retry(context, updated_state, next_retry_count, max_tool_iterations, opts)

      {:error, normalized_reason} ->
        {:error, normalized_reason}
    end
  end

  defp do_chat_loop(_context, state, 0, opts) do
    Logger.warning("#{Keyword.fetch!(opts, :provider)} Tool use 최대 반복 횟수 초과")
    {:error, :max_tool_iterations, state}
  end

  defp do_chat_loop(context, state, iterations_left, opts) do
    call_api = Keyword.fetch!(opts, :call_api)

    case call_api.(context, state.body) do
      {:ok, response} ->
        usage_info = Keyword.fetch!(opts, :usage_info).(response, state.usage)
        Logger.info(usage_info.log)
        handle_response(context, state, response, iterations_left, usage_info.usage, opts)

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp handle_response(context, state, response, iterations_left, usage, opts) do
    response_module = Keyword.fetch!(opts, :response_module)

    if response_module.tool_loop?(response) do
      {new_tool_results, provider_payloads} =
        Keyword.fetch!(opts, :execute_tools).(response_module.tool_calls(response))

      updated_state = %{
        state
        | body: response_module.append_tool_results(state.body, response, provider_payloads),
          tool_results: state.tool_results ++ new_tool_results,
          usage: usage
      }

      do_chat_loop(context, updated_state, iterations_left - 1, opts)
    else
      {:ok,
       %{
         text: response_module.completion_text(response),
         tool_results: state.tool_results,
         usage: usage
       }}
    end
  end
end
