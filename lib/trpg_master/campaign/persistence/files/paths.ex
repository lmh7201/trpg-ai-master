defmodule TrpgMaster.Campaign.Persistence.Files.Paths do
  @moduledoc false

  def campaigns_dir do
    Path.join(data_dir(), "campaigns")
  end

  def campaign_dir(campaign_id) do
    Path.join([campaigns_dir(), sanitize_filename(campaign_id)])
  end

  def summary_path(campaign_id) do
    campaign_id
    |> campaign_dir()
    |> campaign_summary_path()
  end

  def campaign_summary_path(dir), do: Path.join(dir, "campaign-summary.json")
  def characters_dir(dir), do: Path.join(dir, "characters")
  def npcs_dir(dir), do: Path.join(dir, "npcs")
  def exploration_history_path(dir), do: Path.join(dir, "exploration_history.json")
  def legacy_exploration_history_path(dir), do: Path.join(dir, "conversation_history.json")
  def combat_history_path(dir), do: Path.join(dir, "combat_history.json")
  def journal_path(dir), do: Path.join(dir, "journal.json")
  def context_summary_path(dir), do: Path.join(dir, "context_summary.json")

  @doc """
  파일/디렉터리 이름을 안전한 형태로 바꾼다.

  - 경로 구분자(`/`, `\\`)와 예약 문자는 `_`로 치환한다.
  - 앞뒤 공백·점(`.`, `..` 포함)을 제거해 경로 순회(`..`)를 차단한다.
  - 결과가 빈 문자열이면 `_`를 돌려준다.

  이 함수는 파일 시스템에 쓰는 경로를 만들 때마다 반드시 거쳐야 한다.
  """
  def sanitize_filename(name) when is_binary(name) do
    sanitized =
      name
      |> String.replace(~r/[\/\\:*?"<>|\x00-\x1f]/u, "_")
      |> String.trim()
      |> String.replace(~r/^\.+/, "")
      |> String.replace(~r/\.+$/, "")

    case sanitized do
      "" -> "_"
      other -> other
    end
  end

  def sanitize_filename(_), do: "_"

  defp data_dir do
    Application.get_env(:trpg_master, :data_dir, "data")
  end
end
