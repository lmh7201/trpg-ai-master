defmodule TrpgMaster.AI.Providers.RetryTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.Providers.Retry

  test "handle/4 retries on rate limit with exponential backoff" do
    Process.put(:retry_sleeps, [])
    on_exit(fn -> Process.delete(:retry_sleeps) end)

    assert {:retry, %{body: :state}, 1} =
             Retry.handle({:api_error, 429, %{}}, 0, %{body: :state},
               rules: [Retry.rate_limit_rule("OpenAI")],
               sleep_fun: &record_sleep/1
             )

    assert Process.get(:retry_sleeps) == [2000]
  end

  test "handle/4 normalizes invalid api key errors" do
    assert {:error, :invalid_api_key} =
             Retry.handle({:api_error, 401, %{}}, 0, :state,
               rules: [Retry.rate_limit_rule("OpenAI")]
             )
  end

  test "handle/4 applies custom transform rules" do
    assert {:retry, %{trimmed: true}, 1} =
             Retry.handle({:api_error, 400, %{}}, 0, %{trimmed: false},
               rules: [
                 Retry.status_rule(400, 2,
                   log: fn _attempt, _reason -> "trim" end,
                   transform: fn _context, _reason -> %{trimmed: true} end
                 )
               ]
             )
  end

  test "handle/4 returns the original error when no rule matches" do
    reason = {:api_error, 422, %{"error" => "unprocessable"}}

    assert {:error, ^reason} =
             Retry.handle(reason, 0, :state, rules: [Retry.rate_limit_rule("OpenAI")])
  end

  defp record_sleep(duration_ms) do
    Process.put(:retry_sleeps, Process.get(:retry_sleeps, []) ++ [duration_ms])
  end
end
