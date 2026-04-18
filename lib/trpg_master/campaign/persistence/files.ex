defmodule TrpgMaster.Campaign.Persistence.Files do
  @moduledoc false

  alias TrpgMaster.Campaign.State

  require Logger

  def save_state(%State{} = state, schema_version) do
    dir = campaign_dir(state.id)

    with :ok <- ensure_campaign_dirs(dir),
         summary <- State.to_summary(state) |> Map.put("schema_version", schema_version),
         :ok <- write_json(summary_path(state.id), summary),
         :ok <- save_characters(dir, state.characters),
         :ok <- save_npcs(dir, state.npcs),
         :ok <- write_json(Path.join(dir, "exploration_history.json"), state.exploration_history),
         :ok <- write_json(Path.join(dir, "combat_history.json"), state.combat_history),
         :ok <- write_json(Path.join(dir, "journal.json"), state.journal_entries),
         :ok <- save_context_summary(dir, state.context_summary) do
      :ok
    end
  end

  def load_state(campaign_id) do
    dir = campaign_dir(campaign_id)
    path = summary_path(campaign_id)

    if File.exists?(path) do
      with {:ok, summary} <- read_json(path),
           {:ok, characters} <- load_characters(dir),
           {:ok, npcs} <- load_npcs(dir),
           {:ok, exploration_history} <- load_exploration_history(dir),
           {:ok, combat_history} <- load_combat_history(dir),
           {:ok, journal_entries} <- load_journal(dir) do
        {:ok,
         %{
           summary: summary,
           characters: characters,
           npcs: npcs,
           exploration_history: exploration_history,
           combat_history: combat_history,
           journal_entries: journal_entries,
           context_summary: load_context_summary(dir)
         }}
      end
    else
      {:error, :not_found}
    end
  end

  def list_campaigns do
    campaigns_dir = Path.join(data_dir(), "campaigns")

    if File.exists?(campaigns_dir) do
      case File.ls(campaigns_dir) do
        {:ok, dirs} ->
          dirs
          |> Enum.map(&load_campaign_summary(campaigns_dir, &1))
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

  def campaign_dir(campaign_id) do
    Path.join([data_dir(), "campaigns", sanitize_filename(campaign_id)])
  end

  def summary_path(campaign_id) do
    Path.join(campaign_dir(campaign_id), "campaign-summary.json")
  end

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

  defp data_dir do
    Application.get_env(:trpg_master, :data_dir, "data")
  end

  defp ensure_campaign_dirs(dir) do
    with :ok <- File.mkdir_p(dir),
         :ok <- File.mkdir_p(Path.join(dir, "characters")),
         :ok <- File.mkdir_p(Path.join(dir, "npcs")) do
      :ok
    end
  end

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[\/\\:*?"<>|]/, "_")
    |> String.trim()
  end

  defp save_characters(dir, characters) do
    persist_collection(characters, fn character ->
      name = character["name"] || "unknown"
      path = Path.join([dir, "characters", "#{sanitize_filename(name)}.json"])
      write_json(path, character)
    end)
  end

  defp save_npcs(dir, npcs) do
    persist_collection(npcs, fn {name, data} ->
      path = Path.join([dir, "npcs", "#{sanitize_filename(name)}.json"])
      write_json(path, data)
    end)
  end

  defp persist_collection(collection, writer) do
    Enum.reduce_while(collection, :ok, fn item, _acc ->
      case writer.(item) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp load_campaign_summary(campaigns_dir, dir_name) do
    path = Path.join([campaigns_dir, dir_name, "campaign-summary.json"])

    case read_json(path) do
      {:ok, summary} ->
        %{
          id: summary["id"],
          name: summary["name"],
          updated_at: summary["updated_at"]
        }

      _ ->
        nil
    end
  end

  defp load_characters(dir) do
    load_json_list(Path.join(dir, "characters"))
  end

  defp load_npcs(dir) do
    npcs_dir = Path.join(dir, "npcs")

    if File.exists?(npcs_dir) do
      case File.ls(npcs_dir) do
        {:ok, files} ->
          npcs =
            files
            |> Enum.filter(&String.ends_with?(&1, ".json"))
            |> Enum.reduce(%{}, fn file, acc ->
              case read_json(Path.join(npcs_dir, file)) do
                {:ok, data} ->
                  name = data["name"] || Path.rootname(file)
                  Map.put(acc, name, data)

                _ ->
                  acc
              end
            end)

          {:ok, npcs}

        _ ->
          {:ok, %{}}
      end
    else
      {:ok, %{}}
    end
  end

  defp load_json_list(dir) do
    if File.exists?(dir) do
      case File.ls(dir) do
        {:ok, files} ->
          items =
            files
            |> Enum.filter(&String.ends_with?(&1, ".json"))
            |> Enum.map(fn file ->
              case read_json(Path.join(dir, file)) do
                {:ok, data} -> data
                _ -> nil
              end
            end)
            |> Enum.reject(&is_nil/1)

          {:ok, items}

        _ ->
          {:ok, []}
      end
    else
      {:ok, []}
    end
  end

  defp load_exploration_history(dir) do
    path = Path.join(dir, "exploration_history.json")

    if File.exists?(path) do
      read_json(path)
    else
      legacy_path = Path.join(dir, "conversation_history.json")

      if File.exists?(legacy_path) do
        Logger.info("[Persistence] 기존 conversation_history.json → exploration_history로 마이그레이션")
        read_json(legacy_path)
      else
        {:ok, []}
      end
    end
  end

  defp load_combat_history(dir) do
    path = Path.join(dir, "combat_history.json")

    if File.exists?(path) do
      read_json(path)
    else
      {:ok, []}
    end
  end

  defp save_context_summary(_dir, nil), do: :ok

  defp save_context_summary(dir, summary) do
    write_json(Path.join(dir, "context_summary.json"), %{"summary" => summary})
  end

  defp load_context_summary(dir) do
    path = Path.join(dir, "context_summary.json")

    case read_json(path) do
      {:ok, %{"summary" => summary}} -> summary
      _ -> nil
    end
  end

  defp load_journal(dir) do
    path = Path.join(dir, "journal.json")

    if File.exists?(path) do
      read_json(path)
    else
      {:ok, []}
    end
  end
end
