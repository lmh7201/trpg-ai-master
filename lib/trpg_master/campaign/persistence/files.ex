defmodule TrpgMaster.Campaign.Persistence.Files do
  @moduledoc false

  alias TrpgMaster.Campaign.Persistence.Files.{Collections, Paths}
  alias TrpgMaster.Campaign.State

  def save_state(%State{} = state, schema_version) do
    dir = campaign_dir(state.id)

    with :ok <- Collections.ensure_campaign_dirs(dir),
         summary <- State.to_summary(state) |> Map.put("schema_version", schema_version),
         :ok <- write_json(summary_path(state.id), summary),
         :ok <- Collections.save_characters(dir, state.characters, &write_json/2),
         :ok <- Collections.save_npcs(dir, state.npcs, &write_json/2),
         :ok <- write_json(Paths.exploration_history_path(dir), state.exploration_history),
         :ok <- write_json(Paths.combat_history_path(dir), state.combat_history),
         :ok <- write_json(Paths.journal_path(dir), state.journal_entries),
         :ok <- Collections.save_context_summary(dir, state.context_summary, &write_json/2) do
      :ok
    end
  end

  def load_state(campaign_id) do
    dir = campaign_dir(campaign_id)
    path = summary_path(campaign_id)

    if File.exists?(path) do
      with {:ok, summary} <- read_json(path),
           {:ok, characters} <- Collections.load_characters(dir, &read_json/1),
           {:ok, npcs} <- Collections.load_npcs(dir, &read_json/1),
           {:ok, exploration_history} <- Collections.load_exploration_history(dir, &read_json/1),
           {:ok, combat_history} <- Collections.load_combat_history(dir, &read_json/1),
           {:ok, journal_entries} <- Collections.load_journal(dir, &read_json/1) do
        {:ok,
         %{
           summary: summary,
           characters: characters,
           npcs: npcs,
           exploration_history: exploration_history,
           combat_history: combat_history,
           journal_entries: journal_entries,
           context_summary: Collections.load_context_summary(dir, &read_json/1)
         }}
      end
    else
      {:error, :not_found}
    end
  end

  def list_campaigns do
    campaigns_dir = Paths.campaigns_dir()

    if File.exists?(campaigns_dir) do
      case File.ls(campaigns_dir) do
        {:ok, dirs} ->
          dirs
          |> Enum.map(fn dir_name ->
            Collections.load_campaign_summary(campaigns_dir, dir_name, &read_json/1)
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(& &1.updated_at, :desc)

        _ ->
          []
      end
    else
      []
    end
  end

  def delete_campaign(campaign_id) do
    dir = campaign_dir(campaign_id)

    if File.exists?(dir) do
      File.rm_rf(dir)
      :ok
    else
      :ok
    end
  end

  defdelegate campaign_dir(campaign_id), to: Paths
  defdelegate summary_path(campaign_id), to: Paths

  def write_json(path, data) do
    case Jason.encode(data, pretty: true) do
      {:ok, json} -> File.write(path, json)
      {:error, reason} -> {:error, reason}
    end
  end

  def read_json(path) do
    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content) do
      {:ok, data}
    end
  end
end
