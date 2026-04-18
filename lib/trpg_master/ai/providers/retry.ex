defmodule TrpgMaster.AI.Providers.Retry do
  @moduledoc """
  AI provider들의 API 재시도 정책을 공통화한다.
  """

  require Logger

  @type retry_rule :: %{
          required(:statuses) => [integer()],
          required(:max_retries) => non_neg_integer(),
          required(:log) => (pos_integer(), term() -> String.t()),
          optional(:sleep_ms) => (pos_integer(), term() -> non_neg_integer()),
          optional(:transform) => (term(), term() -> term())
        }

  @doc """
  재시도 규칙을 평가하고, 재시도 여부와 다음 컨텍스트를 반환한다.
  """
  def handle(reason, retry_count, context, opts) do
    sleep_fun = Keyword.get(opts, :sleep_fun, &Process.sleep/1)
    rules = Keyword.fetch!(opts, :rules)

    case Enum.find_value(rules, &apply_rule(&1, reason, retry_count, context, sleep_fun)) do
      nil -> normalize_error(reason)
      result -> result
    end
  end

  @doc """
  공통 rate limit 재시도 규칙을 생성한다.
  """
  def rate_limit_rule(provider) do
    status_rule(429, 3,
      log: fn attempt, _reason ->
        wait_ms = 2000 * attempt
        "#{provider} Rate limit — #{wait_ms}ms 대기 후 재시도 (#{attempt}/3)"
      end,
      sleep_ms: fn attempt, _reason -> 2000 * attempt end
    )
  end

  @doc """
  공통 서버 에러 재시도 규칙을 생성한다.
  """
  def server_error_rule(provider, statuses) do
    status_rule(statuses, 2,
      log: fn attempt, {:api_error, status, _reason} ->
        "#{provider} 서버 에러 #{status} — 3초 대기 후 재시도 (#{attempt}/2)"
      end,
      sleep_ms: fn _attempt, _reason -> 3000 end
    )
  end

  @doc """
  특정 status 코드 재시도 규칙을 생성한다.
  """
  def status_rule(status, max_retries, opts) when is_integer(status) do
    status_rule([status], max_retries, opts)
  end

  def status_rule(statuses, max_retries, opts) when is_list(statuses) do
    %{
      statuses: statuses,
      max_retries: max_retries,
      log: Keyword.fetch!(opts, :log),
      sleep_ms: Keyword.get(opts, :sleep_ms),
      transform: Keyword.get(opts, :transform, fn context, _reason -> context end)
    }
  end

  defp apply_rule(rule, {:api_error, status, _} = reason, retry_count, context, sleep_fun) do
    if Enum.member?(rule.statuses, status) and retry_count < rule.max_retries do
      attempt = retry_count + 1
      Logger.warning(rule.log.(attempt, reason))

      if sleep_ms_fun = rule[:sleep_ms] do
        sleep_fun.(sleep_ms_fun.(attempt, reason))
      end

      {:retry, rule.transform.(context, reason), attempt}
    end
  end

  defp apply_rule(_rule, _reason, _retry_count, _context, _sleep_fun), do: nil

  defp normalize_error({:api_error, 401, _reason}), do: {:error, :invalid_api_key}
  defp normalize_error(reason), do: {:error, reason}
end
