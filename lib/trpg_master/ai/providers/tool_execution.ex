defmodule TrpgMaster.AI.Providers.ToolExecution do
  @moduledoc """
  Provider별 tool call을 공통 `tool_results`와 응답 블록으로 변환한다.
  """

  alias TrpgMaster.AI.Tools
  require Logger

  @type extracted_call :: %{
          required(:name) => String.t(),
          optional(:id) => String.t(),
          optional(:input) => map()
        }

  @doc """
  tool call 목록을 실행하고 공통 `tool_results`와 provider별 응답 payload를 반환한다.
  """
  def run(tool_calls, opts) when is_list(tool_calls) do
    provider = Keyword.fetch!(opts, :provider)
    extract = Keyword.fetch!(opts, :extract)
    success = Keyword.fetch!(opts, :success)
    error = Keyword.fetch!(opts, :error)

    results =
      Enum.map(tool_calls, fn raw_call ->
        extracted = extract_tool_call(raw_call, extract)

        Logger.info("#{provider} 도구 실행: #{extracted.name} — #{inspect(extracted.input)}")

        case Tools.execute(extracted.name, extracted.input) do
          {:ok, result} ->
            {success_result(extracted, result), success.(extracted, result)}

          {:error, reason} ->
            {error_result(extracted, reason), error.(extracted, reason)}
        end
      end)

    {Enum.map(results, &elem(&1, 0)), Enum.map(results, &elem(&1, 1))}
  end

  defp extract_tool_call(raw_call, extract) do
    raw_call
    |> extract.()
    |> Map.new()
    |> Map.put_new(:input, %{})
  end

  defp success_result(extracted, result) do
    %{
      tool: extracted.name,
      input: extracted.input,
      result: result
    }
  end

  defp error_result(extracted, reason) do
    %{
      tool: extracted.name,
      input: extracted.input,
      error: reason
    }
  end
end
