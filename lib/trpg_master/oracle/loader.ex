defmodule TrpgMaster.Oracle.Loader do
  @moduledoc """
  오라클 JSON 파일을 로드하고 캐시하는 Agent.

  앱 시작 시 priv/oracles/ 디렉토리의 모든 JSON 파일을 읽어
  메모리에 캐시한다. 핫 리로드는 지원하지 않으며 앱 재시작 시 갱신된다.

  오라클 이름은 JSON 파일명에서 확장자를 제거한 문자열이다.
  예: yes_no.json → "yes_no"
  """

  use Agent

  require Logger

  def start_link(_opts) do
    Agent.start_link(&load_all/0, name: __MODULE__)
  end

  @doc """
  오라클 이름으로 무작위 결과를 반환한다.

  Returns {:ok, result} | {:error, reason}
  """
  def random_result(oracle_name) do
    case get(oracle_name) do
      {:ok, %{"results" => results}} when is_list(results) and results != [] ->
        {:ok, Enum.random(results)}

      {:ok, _} ->
        {:error, "오라클 '#{oracle_name}'에 결과 목록이 없습니다."}

      :not_found ->
        available = list() |> Enum.map(& &1["metadata"]["name"]) |> Enum.join(", ")
        {:error, "오라클 '#{oracle_name}'을(를) 찾을 수 없습니다. 사용 가능: #{available}"}
    end
  end

  @doc """
  오라클 이름으로 데이터를 조회한다.

  Returns {:ok, oracle_data} | :not_found
  """
  def get(oracle_name) do
    case Agent.get(__MODULE__, &Map.get(&1, oracle_name)) do
      nil -> :not_found
      data -> {:ok, data}
    end
  end

  @doc """
  사용 가능한 모든 오라클 데이터 목록을 반환한다.
  """
  def list do
    Agent.get(__MODULE__, &Map.values/1)
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp load_all do
    oracles_dir = Application.app_dir(:trpg_master, "priv/oracles")

    case File.ls(oracles_dir) do
      {:ok, files} ->
        oracles =
          files
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.reduce(%{}, fn filename, acc ->
            path = Path.join(oracles_dir, filename)
            oracle_name = Path.rootname(filename)

            case load_file(path, filename) do
              {:ok, data} -> Map.put(acc, oracle_name, data)
              :error -> acc
            end
          end)

        names = Map.keys(oracles) |> Enum.join(", ")
        Logger.info("Oracle.Loader: #{map_size(oracles)}개 로드 완료 — #{names}")
        oracles

      {:error, reason} ->
        Logger.warning("Oracle.Loader: priv/oracles/ 읽기 실패 — #{inspect(reason)}")
        %{}
    end
  end

  defp load_file(path, filename) do
    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content) do
      Logger.info("Oracle.Loader: #{filename} 로드 완료")
      {:ok, data}
    else
      {:error, reason} ->
        Logger.warning("Oracle.Loader: #{filename} 로드 실패 — #{inspect(reason)}")
        :error
    end
  end
end
