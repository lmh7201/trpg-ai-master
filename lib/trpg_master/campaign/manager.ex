defmodule TrpgMaster.Campaign.Manager do
  @moduledoc """
  캠페인 GenServer 프로세스의 생명주기를 관리한다.
  DynamicSupervisor를 통해 캠페인 서버를 시작/중지한다.
  """

  alias TrpgMaster.Campaign.{Server, State, Persistence}

  require Logger

  @doc """
  새 캠페인을 생성하고 서버를 시작한다.
  """
  def create_campaign(name, ai_model \\ nil) do
    id = generate_id()

    state = %State{
      id: id,
      name: name,
      ai_model: ai_model
    }

    case start_server(state) do
      {:ok, _pid} ->
        Persistence.save(state)
        {:ok, id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  기존 캠페인을 로드하고 서버를 시작한다.
  이미 실행 중이면 그대로 반환한다.
  """
  def start_campaign(campaign_id) do
    if Server.alive?(campaign_id) do
      {:ok, campaign_id}
    else
      case Persistence.load(campaign_id) do
        {:ok, state} ->
          case start_server(state) do
            {:ok, _pid} -> {:ok, campaign_id}
            {:error, {:already_started, _pid}} -> {:ok, campaign_id}
            {:error, reason} -> {:error, reason}
          end

        {:error, :not_found} ->
          {:error, :not_found}
      end
    end
  end

  @doc """
  캠페인 서버를 중지한다.
  """
  def stop_campaign(campaign_id) do
    case Registry.lookup(TrpgMaster.Campaign.Registry, campaign_id) do
      [{pid, _}] ->
        # Save before stopping
        state = Server.get_state(campaign_id)
        Persistence.save(state)
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        :ok
    end
  end

  @doc """
  캠페인을 삭제한다.
  """
  def delete_campaign(campaign_id) do
    stop_campaign(campaign_id)
    Persistence.delete(campaign_id)
  end

  @doc """
  현재 실행 중인 캠페인 ID 목록을 반환한다.
  """
  def active_campaigns do
    Registry.select(TrpgMaster.Campaign.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  # ── Private ─────────────────────────────────────────────────────────────────

  defp start_server(%State{} = state) do
    DynamicSupervisor.start_child(__MODULE__, {Server, state})
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
