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

  def sanitize_filename(name) do
    name
    |> String.replace(~r/[\/\\:*?"<>|]/, "_")
    |> String.trim()
  end

  defp data_dir do
    Application.get_env(:trpg_master, :data_dir, "data")
  end
end
