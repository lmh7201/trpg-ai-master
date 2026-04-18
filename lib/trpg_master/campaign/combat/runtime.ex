defmodule TrpgMaster.Campaign.Combat.Runtime do
  @moduledoc false

  alias TrpgMaster.Campaign.Summarizer

  require Logger

  def start_turn(state, message) do
    round_start_index = length(state.combat_history)

    state
    |> Map.put(:current_round_start_index, round_start_index)
    |> append_history_entry(%{"role" => "user", "content" => message})
  end

  def append_history_entry(state, entry) do
    %{state | combat_history: state.combat_history ++ [entry]}
  end

  def should_end?(state) do
    player_names = get_in(state.combat_state, ["player_names"]) || []
    enemies = get_in(state.combat_state, ["enemies"]) || []

    all_players_dead?(state.characters, player_names) or all_enemies_dead?(enemies)
  end

  def force_end_if_needed(%{phase: :combat} = state) do
    Logger.info("전멸 감지로 전투 자동 종료 [#{state.id}]")
    player_names = get_in(state.combat_state, ["player_names"]) || []

    characters =
      if player_names != [] do
        Enum.filter(state.characters, fn character -> character["name"] in player_names end)
      else
        state.characters
      end

    %{state | phase: :exploration, combat_state: nil, characters: characters}
  end

  def force_end_if_needed(state), do: state

  def finalize(
        state,
        last_response_text,
        generate_post_combat_summary_fun \\ &Summarizer.generate_post_combat_summary/1
      ) do
    Logger.info("전투 종료 처리 [#{state.id}] — combat_history: #{length(state.combat_history)}개")

    transition_text = "[전투 종료] " <> last_response_text

    state =
      %{
        state
        | exploration_history:
            state.exploration_history ++ [%{"role" => "assistant", "content" => transition_text}]
      }

    state =
      case generate_post_combat_summary_fun.(state) do
        {:ok, summary} ->
          Logger.info("전투 종료 요약 생성 완료 [#{state.id}]")
          %{state | post_combat_summary: summary}

        {:error, reason} ->
          Logger.warning("전투 종료 요약 생성 실패 [#{state.id}]: #{inspect(reason)}")
          state
      end

    %{state | combat_history: [], combat_history_summary: nil}
  end

  def extract_enemy_groups(state) do
    case get_in(state.combat_state, ["enemies"]) do
      enemies when is_list(enemies) and enemies != [] ->
        enemies
        |> Enum.reject(fn enemy ->
          hp = enemy["hp_current"]
          is_number(hp) and hp <= 0
        end)
        |> Enum.map(fn enemy -> enemy["name"] end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      _ ->
        ["적"]
    end
  end

  defp all_players_dead?(characters, player_names) when player_names != [] do
    players = Enum.filter(characters, fn character -> character["name"] in player_names end)

    players != [] and
      Enum.all?(players, fn character ->
        hp = character["hp_current"]
        is_number(hp) and hp <= 0
      end)
  end

  defp all_players_dead?(_, _), do: false

  defp all_enemies_dead?(enemies) when is_list(enemies) and enemies != [] do
    Enum.all?(enemies, fn enemy ->
      hp = enemy["hp_current"]
      is_number(hp) and hp <= 0
    end)
  end

  defp all_enemies_dead?(_), do: false
end
