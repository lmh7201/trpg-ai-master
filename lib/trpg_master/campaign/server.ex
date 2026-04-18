defmodule TrpgMaster.Campaign.Server do
  @moduledoc """
  캠페인 하나 = GenServer 프로세스 하나.
  플레이어 메시지 처리, 상태 관리, AI 호출을 담당한다.
  크래시 후 재시작 시 Persistence.load로 자동 복원한다.

  도구 실행은 ToolHandler, 요약 생성은 Summarizer, 전투 흐름은 Combat에 위임한다.
  """

  use GenServer

  alias TrpgMaster.Campaign.{Combat, Exploration, Persistence, State, Summarizer}

  require Logger

  @player_action_timeout 180_000

  # ── Public API ──────────────────────────────────────────────────────────────

  def start_link(%State{} = state) do
    GenServer.start_link(__MODULE__, state, name: via(state.id))
  end

  def player_action(campaign_id, message) do
    GenServer.call(via(campaign_id), {:player_action, message}, @player_action_timeout)
  end

  def get_state(campaign_id) do
    GenServer.call(via(campaign_id), :get_state)
  end

  def set_character(campaign_id, character) do
    GenServer.call(via(campaign_id), {:set_character, character})
  end

  def set_mode(campaign_id, mode) when mode in [:adventure, :debug] do
    GenServer.call(via(campaign_id), {:set_mode, mode})
  end

  def set_model(campaign_id, model_id) do
    GenServer.call(via(campaign_id), {:set_model, model_id})
  end

  def end_session(campaign_id) do
    GenServer.call(via(campaign_id), :end_session, 120_000)
  end

  def alive?(campaign_id) do
    case Registry.lookup(TrpgMaster.Campaign.Registry, campaign_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  # ── GenServer Callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(%State{id: campaign_id} = initial_state) do
    case Persistence.load(campaign_id) do
      {:ok, loaded_state} ->
        Logger.info("캠페인 복원: #{loaded_state.name} [#{loaded_state.id}]")
        {:ok, loaded_state}

      {:error, _} ->
        Logger.info("캠페인 서버 시작: #{initial_state.name} [#{initial_state.id}]")
        {:ok, initial_state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:set_character, character}, _from, state) do
    new_state = %{state | characters: [character]}
    Persistence.save_async(new_state)
    Logger.info("캐릭터 등록 [#{state.id}]: #{character["name"]}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_mode, mode}, _from, state) do
    new_state = %{state | mode: mode}
    Persistence.save_async(new_state)
    Logger.info("모드 변경 [#{state.id}]: #{state.mode} → #{mode}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_model, model_id}, _from, state) do
    new_state = %{state | ai_model: model_id}
    Persistence.save_async(new_state)
    Logger.info("AI 모델 변경 [#{state.id}]: #{state.ai_model} → #{model_id}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:end_session, _from, state) do
    Logger.info("세션 종료 처리 시작 [#{state.id}] 턴 #{state.turn_count}")

    case Summarizer.generate_session_summary(state) do
      {:ok, summary_text} ->
        session_number = Summarizer.estimate_session_number(state)
        Persistence.append_session_log(state, session_number, summary_text)

        new_state = %{
          state
          | exploration_history: [],
            combat_history: [],
            combat_history_summary: nil,
            post_combat_summary: nil,
            context_summary: nil
        }

        Persistence.save_async(new_state)

        {:reply, {:ok, summary_text}, new_state}

      {:error, reason} ->
        Logger.error("세션 요약 생성 실패 [#{state.id}]: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:player_action, message}, _from, state) do
    state = %{state | turn_count: state.turn_count + 1}

    case state.phase do
      :combat ->
        Combat.handle_action(message, state,
          model_opts: model_opts(state),
          tool_context: tool_context(state)
        )

      _ ->
        Exploration.handle_action(message, state,
          model_opts: model_opts(state),
          tool_context: tool_context(state)
        )
    end
  end

  # ── Private helpers ─────────────────────────────────────────────────────────

  defp via(campaign_id) do
    {:via, Registry, {TrpgMaster.Campaign.Registry, campaign_id}}
  end

  defp model_opts(%{ai_model: nil}), do: []
  defp model_opts(%{ai_model: model_id}), do: [model: model_id]

  defp tool_context(state) do
    %{journal_entries: state.journal_entries, characters: state.characters}
  end
end
