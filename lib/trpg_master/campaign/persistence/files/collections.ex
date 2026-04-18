defmodule TrpgMaster.Campaign.Persistence.Files.Collections do
  @moduledoc false

  alias TrpgMaster.Campaign.Persistence.Files.Paths
  require Logger

  def ensure_campaign_dirs(dir) do
    with :ok <- File.mkdir_p(dir),
         :ok <- File.mkdir_p(Paths.characters_dir(dir)),
         :ok <- File.mkdir_p(Paths.npcs_dir(dir)) do
      :ok
    end
  end

  def save_characters(dir, characters, write_json_fun) do
    persist_collection(characters, fn character ->
      name = character["name"] || "unknown"
      path = Path.join([Paths.characters_dir(dir), "#{Paths.sanitize_filename(name)}.json"])
      write_json_fun.(path, character)
    end)
  end

  def save_npcs(dir, npcs, write_json_fun) do
    persist_collection(npcs, fn {name, data} ->
      path = Path.join([Paths.npcs_dir(dir), "#{Paths.sanitize_filename(name)}.json"])
      write_json_fun.(path, data)
    end)
  end

  def load_campaign_summary(campaigns_dir, dir_name, read_json_fun) do
    path = Path.join([campaigns_dir, dir_name, "campaign-summary.json"])

    case read_json_fun.(path) do
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

  def load_characters(dir, read_json_fun) do
    load_json_list(Paths.characters_dir(dir), read_json_fun)
  end

  def load_npcs(dir, read_json_fun) do
    npcs_dir = Paths.npcs_dir(dir)

    if File.exists?(npcs_dir) do
      case File.ls(npcs_dir) do
        {:ok, files} ->
          npcs =
            files
            |> Enum.filter(&String.ends_with?(&1, ".json"))
            |> Enum.reduce(%{}, fn file, acc ->
              case read_json_fun.(Path.join(npcs_dir, file)) do
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

  def load_exploration_history(dir, read_json_fun) do
    path = Paths.exploration_history_path(dir)

    if File.exists?(path) do
      read_json_fun.(path)
    else
      legacy_path = Paths.legacy_exploration_history_path(dir)

      if File.exists?(legacy_path) do
        Logger.info("[Persistence] 기존 conversation_history.json → exploration_history로 마이그레이션")
        read_json_fun.(legacy_path)
      else
        {:ok, []}
      end
    end
  end

  def load_combat_history(dir, read_json_fun) do
    path = Paths.combat_history_path(dir)

    if File.exists?(path) do
      read_json_fun.(path)
    else
      {:ok, []}
    end
  end

  def save_context_summary(_dir, nil, _write_json_fun), do: :ok

  def save_context_summary(dir, summary, write_json_fun) do
    write_json_fun.(Paths.context_summary_path(dir), %{"summary" => summary})
  end

  def load_context_summary(dir, read_json_fun) do
    case read_json_fun.(Paths.context_summary_path(dir)) do
      {:ok, %{"summary" => summary}} -> summary
      _ -> nil
    end
  end

  def load_journal(dir, read_json_fun) do
    path = Paths.journal_path(dir)

    if File.exists?(path) do
      read_json_fun.(path)
    else
      {:ok, []}
    end
  end

  defp persist_collection(collection, writer) do
    Enum.reduce_while(collection, :ok, fn item, _acc ->
      case writer.(item) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp load_json_list(dir, read_json_fun) do
    if File.exists?(dir) do
      case File.ls(dir) do
        {:ok, files} ->
          items =
            files
            |> Enum.filter(&String.ends_with?(&1, ".json"))
            |> Enum.map(fn file ->
              case read_json_fun.(Path.join(dir, file)) do
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
end
