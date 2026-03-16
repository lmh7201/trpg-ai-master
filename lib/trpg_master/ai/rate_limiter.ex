defmodule TrpgMaster.AI.RateLimiter do
  @moduledoc """
  ETS 기반 슬라이딩 윈도우 rate limiter.
  분당 입력 토큰 사용량을 추적하고 한도 초과 시 대기한다.
  """

  use GenServer
  require Logger

  @table :ai_rate_limiter
  @window_ms 60_000
  @default_token_limit 30_000
  @max_wait_ms 30_000

  # ── Public API ──────────────────────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  API 호출 전 rate limit을 확인한다.
  한도 근접 시 필요한 만큼 대기한 후 :ok를 반환한다.
  대기 시간이 @max_wait_ms를 초과하면 {:error, :rate_limited}를 반환한다.
  """
  def check_and_wait(estimated_tokens \\ 0) do
    token_limit = token_limit()
    now = System.monotonic_time(:millisecond)
    cleanup_old_entries(now)

    current_usage = current_window_usage(now)

    if current_usage + estimated_tokens <= token_limit do
      :ok
    else
      wait_ms = estimate_wait_time(now, estimated_tokens, token_limit)

      if wait_ms > @max_wait_ms do
        Logger.warning("Rate limit 대기 시간 초과 (#{wait_ms}ms) — 요청 거부")
        {:error, :rate_limited}
      else
        Logger.info("Rate limit 근접 — #{wait_ms}ms 대기 (현재: #{current_usage}/#{token_limit} 토큰)")
        Process.sleep(wait_ms)
        :ok
      end
    end
  end

  @doc """
  API 호출 후 실제 사용한 토큰을 기록한다.
  """
  def record_usage(input_tokens) when is_integer(input_tokens) and input_tokens > 0 do
    now = System.monotonic_time(:millisecond)
    :ets.insert(@table, {now, input_tokens})
    :ok
  end

  def record_usage(_), do: :ok

  @doc """
  현재 윈도우의 토큰 사용량을 조회한다.
  """
  def current_usage do
    now = System.monotonic_time(:millisecond)
    cleanup_old_entries(now)
    current_window_usage(now)
  end

  # ── GenServer Callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(_) do
    table = :ets.new(@table, [:named_table, :ordered_set, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end

  # ── Private ─────────────────────────────────────────────────────────────────

  defp current_window_usage(now) do
    cutoff = now - @window_ms

    :ets.foldl(
      fn {ts, tokens}, acc ->
        if ts > cutoff, do: acc + tokens, else: acc
      end,
      0,
      @table
    )
  end

  defp cleanup_old_entries(now) do
    cutoff = now - @window_ms

    :ets.select_delete(@table, [
      {{:"$1", :_}, [{:<, :"$1", cutoff}], [true]}
    ])
  end

  defp estimate_wait_time(now, _estimated_tokens, _token_limit) do
    cutoff = now - @window_ms

    oldest_entry =
      case :ets.first(@table) do
        :"$end_of_table" -> now
        key when key > cutoff -> key
        key -> key
      end

    max(1000, oldest_entry + @window_ms - now + 1000)
  end

  defp token_limit do
    Application.get_env(:trpg_master, :rate_limit_tokens_per_minute, @default_token_limit)
  end
end
