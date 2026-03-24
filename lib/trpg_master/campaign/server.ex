defmodule TrpgMaster.Campaign.Server do
  @moduledoc """
  캠페인 하나 = GenServer 프로세스 하나.
  플레이어 메시지 처리, 상태 관리, AI 호출을 담당한다.
  크래시 후 재시작 시 Persistence.load로 자동 복원한다.
  """

  use GenServer

  alias TrpgMaster.Campaign.{State, Persistence}
  alias TrpgMaster.AI.{Client, Models, PromptBuilder, Tools}

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
    # 크래시 후 재시작 시 Persistence.load로 최신 상태 복원
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

    case generate_session_summary(state) do
      {:ok, summary_text} ->
        # 세션 로그 저장
        session_number = estimate_session_number(state)
        Persistence.append_session_log(state, session_number, summary_text)

        # 히스토리 및 요약 리셋 (캐릭터/NPC/퀘스트는 유지)
        new_state = %{state |
          exploration_history: [],
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
        handle_combat_action(message, state)

      _ ->
        handle_exploration_action(message, state)
    end
  end

  # ── 탐험 모드 처리 ─────────────────────────────────────────────────────────

  defp handle_exploration_action(message, state) do
    history = state.exploration_history ++ [%{"role" => "user", "content" => message}]
    state = %{state | exploration_history: history}

    Logger.info(
      "탐험 액션 처리 시작 [#{state.id}] 턴 #{state.turn_count} — 히스토리: #{length(history)}개"
    )

    system_prompt = PromptBuilder.build(state)
    tools = Tools.definitions(state.phase) ++ Tools.state_tool_definitions()
    trimmed_history = PromptBuilder.build_turn_messages(state, message)

    model_opts = model_opts(state)
    Process.put(:journal_entries, state.journal_entries)
    Process.put(:campaign_characters, state.characters)

    result =
      try do
        Client.chat(system_prompt, trimmed_history, tools, model_opts)
      after
        Process.delete(:journal_entries)
        Process.delete(:campaign_characters)
      end

    case result do
      {:ok, result} ->
        state_before = state
        state = apply_tool_results(state, result.tool_results)
        log_npc_changes(state, state_before)

        state = %{
          state
          | exploration_history:
              state.exploration_history ++ [%{"role" => "assistant", "content" => result.text}]
        }

        # 전투 직후 첫 탐험 턴이면 post_combat_summary 소비
        state =
          if state.post_combat_summary do
            %{state | post_combat_summary: nil}
          else
            state
          end

        state = update_context_summary(state)
        Persistence.save_async(state)

        Logger.info(
          "턴 #{state.turn_count} 저장 완료 [#{state.id}] — npcs: #{map_size(state.npcs)}개, exploration: #{length(state.exploration_history)}개"
        )

        {:reply, {:ok, result}, state}

      {:error, reason} ->
        Logger.error("AI 호출 실패 [#{state.id}]: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  # ── 전투 모드 처리 (2단계 API 호출) ─────────────────────────────────────────

  defp handle_combat_action(message, state) do
    # 1) 현재 라운드 시작 인덱스를 기록한 뒤 플레이어 메시지를 combat_history에 추가
    round_start_index = length(state.combat_history)
    state = %{state |
      current_round_start_index: round_start_index,
      combat_history: state.combat_history ++ [%{"role" => "user", "content" => message}]
    }

    Logger.info(
      "전투 액션 처리 시작 [#{state.id}] 턴 #{state.turn_count} — combat_history: #{length(state.combat_history)}개"
    )

    # 2) 플레이어 턴 API 호출
    system_prompt = PromptBuilder.build(state, combat_phase: :player_turn)
    tools = Tools.definitions(:combat) ++ Tools.state_tool_definitions()
    trimmed_history = PromptBuilder.build_turn_messages(state, message, combat_phase: :player_turn)
    model_opts = model_opts(state)

    Process.put(:journal_entries, state.journal_entries)
    Process.put(:campaign_characters, state.characters)

    player_result =
      try do
        Client.chat(system_prompt, trimmed_history, tools, model_opts)
      after
        Process.delete(:journal_entries)
        Process.delete(:campaign_characters)
      end

    case player_result do
      {:ok, player_result} ->
        state_before = state
        state = apply_tool_results(state, player_result.tool_results)
        log_npc_changes(state, state_before)

        # 플레이어 턴 AI 응답을 combat_history에 추가
        state = %{
          state
          | combat_history:
              state.combat_history ++ [%{"role" => "assistant", "content" => player_result.text}]
        }

        # end_combat 호출 또는 전멸 감지 시 전투 종료
        if state.phase != :combat or combat_should_end?(state) do
          state = force_end_combat_if_needed(state)
          state = finalize_combat(state, player_result.text)
          state = update_context_summary(state)
          Persistence.save_async(state)
          {:reply, {:ok, player_result}, state}
        else
          # 3) 적 그룹별 순차 API 호출
          enemy_groups = extract_enemy_groups(state)
          handle_enemy_group_turns(state, [player_result], enemy_groups, tools, model_opts)
        end

      {:error, reason} ->
        Logger.error("AI 호출 실패 (플레이어 턴) [#{state.id}]: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  # combat_state["enemies"]에서 살아있는 적 그룹 이름 목록 추출
  defp extract_enemy_groups(state) do
    case get_in(state.combat_state, ["enemies"]) do
      enemies when is_list(enemies) and enemies != [] ->
        enemies
        |> Enum.reject(fn e ->
          hp = e["hp_current"]
          is_number(hp) and hp <= 0
        end)
        |> Enum.map(fn e -> e["name"] end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      _ ->
        # enemies 정보가 없으면 단일 그룹으로 폴백
        ["적"]
    end
  end

  # 적 그룹별 순차 API 호출 — 재귀적으로 그룹 리스트를 소비
  defp handle_enemy_group_turns(state, results, [], tools, model_opts) do
    # 모든 적 그룹 처리 완료 → 라운드 정리 API 호출
    round_trigger = "이번 라운드가 끝났습니다. 라운드를 정리하고 플레이어에게 다음 행동을 물어보세요."
    state = %{state | combat_history: state.combat_history ++ [%{"role" => "user", "content" => round_trigger}]}

    system_prompt = PromptBuilder.build(state, combat_phase: :round_summary)
    trimmed_history = PromptBuilder.build_turn_messages(state, round_trigger)

    Process.put(:journal_entries, state.journal_entries)
    Process.put(:campaign_characters, state.characters)

    round_result =
      try do
        Client.chat(system_prompt, trimmed_history, tools, model_opts)
      after
        Process.delete(:journal_entries)
        Process.delete(:campaign_characters)
      end

    case round_result do
      {:ok, round_result} ->
        state_before = state
        state = apply_tool_results(state, round_result.tool_results)
        log_npc_changes(state, state_before)

        # 라운드 정리 AI 응답을 combat_history에 추가
        state = %{state | combat_history: state.combat_history ++ [%{"role" => "assistant", "content" => round_result.text}]}

        results = results ++ [round_result]

        # 전투 종료 체크 (라운드 정리 중 end_combat 호출 가능성)
        if state.phase != :combat or combat_should_end?(state) do
          state = force_end_combat_if_needed(state)
          state = finalize_combat(state, round_result.text)
          state = update_context_summary(state)
          Persistence.save_async(state)
          {:reply, {:ok, results}, state}
        else
          # 이전 라운드 요약 생성 (다음 라운드에서 시스템 프롬프트에 포함됨)
          state = update_combat_history_summary(state)
          state = update_context_summary(state)
          Persistence.save_async(state)

          Logger.info(
            "전투 턴 #{state.turn_count} 저장 완료 [#{state.id}] — combat_history: #{length(state.combat_history)}개"
          )

          {:reply, {:ok, results}, state}
        end

      {:error, reason} ->
        Logger.error("AI 호출 실패 (라운드 정리) [#{state.id}]: #{inspect(reason)}")
        # 라운드 정리 실패 시 이전까지의 결과 반환
        state = update_combat_history_summary(state)
        Persistence.save_async(state)
        {:reply, {:ok, results}, state}
    end
  end

  defp handle_enemy_group_turns(state, results, [enemy_name | rest], tools, model_opts) do
    is_last_group = rest == []
    trigger_msg = "이제 #{enemy_name}의 턴입니다. #{enemy_name}의 행동을 서술해주세요."
    combat_phase = {:enemy_turn, enemy_name, is_last_group}

    # 트리거 메시지를 combat_history에 user 메시지로 저장 (라운드 전체 히스토리 유지)
    state = %{state | combat_history: state.combat_history ++ [%{"role" => "user", "content" => trigger_msg}]}

    system_prompt = PromptBuilder.build(state, combat_phase: combat_phase)
    trimmed_history = PromptBuilder.build_turn_messages(state, trigger_msg, combat_phase: combat_phase)

    Process.put(:journal_entries, state.journal_entries)
    Process.put(:campaign_characters, state.characters)

    enemy_result =
      try do
        Client.chat(system_prompt, trimmed_history, tools, model_opts)
      after
        Process.delete(:journal_entries)
        Process.delete(:campaign_characters)
      end

    case enemy_result do
      {:ok, enemy_result} ->
        state_before = state
        state = apply_tool_results(state, enemy_result.tool_results)
        log_npc_changes(state, state_before)

        # 적 턴 AI 응답을 combat_history에 추가
        state = %{
          state
          | combat_history:
              state.combat_history ++ [%{"role" => "assistant", "content" => enemy_result.text}]
        }

        results = results ++ [enemy_result]

        # end_combat 호출 또는 전멸 감지 시 전투 종료, 나머지 적 그룹 스킵
        if state.phase != :combat or combat_should_end?(state) do
          state = force_end_combat_if_needed(state)
          state = finalize_combat(state, enemy_result.text)
          state = update_context_summary(state)
          Persistence.save_async(state)
          {:reply, {:ok, results}, state}
        else
          # 다음 적 그룹으로 계속
          handle_enemy_group_turns(state, results, rest, tools, model_opts)
        end

      {:error, reason} ->
        Logger.error("AI 호출 실패 (#{enemy_name} 턴) [#{state.id}]: #{inspect(reason)}")
        # 지금까지 성공한 결과만 반환
        Persistence.save_async(state)

        if length(results) == 1 do
          # 플레이어 결과만 있으면 단일 결과 반환
          {:reply, {:ok, hd(results)}, state}
        else
          {:reply, {:ok, results}, state}
        end
    end
  end

  # 플레이어 전멸 또는 적 전멸 시 전투 자동 종료 판단
  defp combat_should_end?(state) do
    player_names = get_in(state.combat_state, ["player_names"]) || []
    enemies = get_in(state.combat_state, ["enemies"]) || []

    all_players_dead?(state.characters, player_names) or
      all_enemies_dead?(state.characters, player_names, enemies)
  end

  defp all_players_dead?(characters, player_names) when player_names != [] do
    players = Enum.filter(characters, fn c -> c["name"] in player_names end)

    players != [] and
      Enum.all?(players, fn c ->
        hp = c["hp_current"]
        is_number(hp) and hp <= 0
      end)
  end

  defp all_players_dead?(_, _), do: false

  defp all_enemies_dead?(_characters, _player_names, enemies) when is_list(enemies) and enemies != [] do
    # combat_state["enemies"]의 HP를 기준으로 적 전멸 판단
    # (적은 state.characters에 추가되지 않으므로 enemies 목록을 직접 사용)
    Enum.all?(enemies, fn e ->
      hp = e["hp_current"]
      is_number(hp) and hp <= 0
    end)
  end

  defp all_enemies_dead?(_, _, _), do: false

  # combat_should_end?가 true이지만 아직 phase가 :combat인 경우, 강제 전투 종료 처리
  defp force_end_combat_if_needed(%{phase: :combat} = state) do
    Logger.info("전멸 감지로 전투 자동 종료 [#{state.id}]")
    player_names = get_in(state.combat_state, ["player_names"]) || []

    characters =
      if player_names != [] do
        Enum.filter(state.characters, fn c -> c["name"] in player_names end)
      else
        state.characters
      end

    %{state | phase: :exploration, combat_state: nil, characters: characters}
  end

  defp force_end_combat_if_needed(state), do: state

  # 전투 종료 시 처리: post_combat_summary 생성, combat_history 초기화
  defp finalize_combat(state, last_response_text) do
    Logger.info("전투 종료 처리 [#{state.id}] — combat_history: #{length(state.combat_history)}개")

    # 전투 마무리 서술을 exploration_history에 추가 (전투 종료 마커로 AI가 전투를 계속하지 않도록 함)
    transition_text = "[전투 종료] " <> last_response_text
    state = %{
      state
      | exploration_history:
          state.exploration_history ++ [%{"role" => "assistant", "content" => transition_text}]
    }

    # post_combat_summary 생성
    state =
      case generate_post_combat_summary(state) do
        {:ok, summary} ->
          Logger.info("전투 종료 요약 생성 완료 [#{state.id}]")
          %{state | post_combat_summary: summary}

        {:error, reason} ->
          Logger.warning("전투 종료 요약 생성 실패 [#{state.id}]: #{inspect(reason)}")
          state
      end

    # combat_history, combat_history_summary 초기화
    %{state | combat_history: [], combat_history_summary: nil}
  end

  # ── Private helpers ─────────────────────────────────────────────────────────

  defp via(campaign_id) do
    {:via, Registry, {TrpgMaster.Campaign.Registry, campaign_id}}
  end

  defp estimate_session_number(state) do
    # 기존 로그 파일에서 세션 번호를 추정 (간단하게 turn_count 기반)
    max(1, div(state.turn_count, 5))
  end

  defp generate_session_summary(state) do
    # 현재 캠페인의 프로바이더와 동일한 저비용 모델 사용
    haiku_model = summary_model_for(state.ai_model)

    summary_prompt = """
    당신은 D&D 세션 서기입니다. 아래 세션 정보를 바탕으로 간결한 세션 요약을 작성해주세요.

    ## 캠페인: #{state.name}
    ## 위치: #{state.current_location || "미정"}
    ## 진행 턴: #{state.turn_count}

    ## 캐릭터
    #{format_characters(state.characters)}

    ## NPC
    #{format_npcs(state.npcs)}

    ## 퀘스트
    #{format_quests(state.active_quests)}

    위 정보를 바탕으로 다음 형식으로 요약을 작성해주세요:

    ## 세션 요약
    (이번 세션의 주요 사건을 2~3문단으로 요약)

    ## 파티 현황
    (캐릭터 HP, 현재 위치, 활성 퀘스트)

    ## 등장 NPC
    (이번 세션에 등장한 NPC 목록)

    ## 다음 세션 예고
    (다음 세션에서 할 일이나 남은 미스터리를 1~2문장으로)
    """

    # 최근 대화 히스토리만 포함 (마지막 20개, 탐험+전투 통합)
    all_history = state.exploration_history ++ state.combat_history
    recent_history = Enum.take(all_history, -20)

    case Client.chat(summary_prompt, recent_history, [], model: haiku_model, max_tokens: 1024) do
      {:ok, result} -> {:ok, result.text}
      {:error, reason} -> {:error, reason}
    end
  end

  # 슬라이딩 윈도우 크기 (PromptBuilder와 동일)
  @recent_window_size 5

  defp generate_context_summary(state) do
    history = state.exploration_history

    # AI(assistant) 응답만 필터링 — 유저 채팅은 요약에 포함하지 않음
    ai_messages =
      Enum.filter(history, fn %{"role" => role} -> role == "assistant" end)

    if ai_messages == [] do
      :skip
    else
      haiku_model = summary_model_for(state.ai_model)
      previous = state.context_summary || "(첫 번째 턴 — 이전 요약 없음)"

      # 최근 AI 응답 5개를 이전 요약과 통합
      recent_ai = Enum.take(ai_messages, -5)

      new_exchange =
        recent_ai
        |> Enum.map(fn %{"content" => content} ->
          "DM: #{String.slice(content, 0, 1000)}"
        end)
        |> Enum.join("\n")

      summary_prompt = """
      당신은 TRPG 세션 기록 요약 도우미입니다.
      [중요] 반드시 이전 요약의 핵심 정보를 보존하면서 최근 AI 응답 내용을 통합하세요.

      ## 이전 요약
      #{previous}

      ## 최근 AI(DM) 응답 히스토리 (최대 5개)
      #{new_exchange}

      ## 지시사항
      위 정보를 하나의 간결한 요약으로 통합하세요 (최대 500자).
      반드시 포함할 내용:
      - 등장한 NPC들 (이름과 태도)
      - 현재 진행 중인 퀘스트와 상태
      - 현재 위치
      - 최근 주요 사건이나 결정
      불필요한 세부사항은 생략하고, 다음 턴에서 DM이 맥락을 파악하는 데 필요한 정보만 남기세요.
      마크다운 서식을 사용하지 마세요. ##, **, *, ` 같은 서식 기호 없이 순수 텍스트로만 작성하세요.
      """

      summary_messages = [%{"role" => "user", "content" => summary_prompt}]

      case Client.chat("You are a TRPG session summarizer.", summary_messages, [],
             model: haiku_model,
             max_tokens: 800
           ) do
        {:ok, result} -> {:ok, result.text}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # 시간/날짜 정보만 있고 실제 내용이 없는 요약을 필터링
  defp meaningful_summary?(text) when is_binary(text) do
    stripped =
      text
      |> String.replace(~r/\d{4}[-\/]\d{1,2}[-\/]\d{1,2}/, "")
      |> String.replace(~r/\d{1,2}:\d{2}(:\d{2})?/, "")
      |> String.replace(~r/[T\-\/:\s.,()]+/, "")
      |> String.replace(~r/첫\s*번째\s*턴/, "")
      |> String.replace("이전 요약 없음", "")
      |> String.trim()

    String.length(stripped) >= 10
  end

  defp meaningful_summary?(_), do: false

  # 전투 참가자 (플레이어 + 적) 상태를 포맷팅
  defp format_combatants_status(state) do
    player_names = get_in(state.combat_state, ["player_names"]) || []
    enemies = get_in(state.combat_state, ["enemies"]) || []

    player_lines =
      state.characters
      |> Enum.filter(fn c -> c["name"] in player_names end)
      |> Enum.map(fn c ->
        hp = if c["hp_current"] && c["hp_max"], do: " HP #{c["hp_current"]}/#{c["hp_max"]}", else: ""
        status = if is_number(c["hp_current"]) and c["hp_current"] <= 0, do: " [쓰러짐]", else: ""
        conditions = case c["conditions"] do
          list when is_list(list) and list != [] -> " 상태: #{Enum.join(list, ", ")}"
          _ -> ""
        end
        "- [아군] #{c["name"]}#{hp}#{status}#{conditions}"
      end)

    enemy_lines =
      Enum.map(enemies, fn e ->
        hp = if e["hp_current"] && e["hp_max"], do: " HP #{e["hp_current"]}/#{e["hp_max"]}", else: ""
        status = if is_number(e["hp_current"]) and e["hp_current"] <= 0, do: " [사망]", else: ""
        "- [적] #{e["name"]}#{hp}#{status}"
      end)

    Enum.join(player_lines ++ enemy_lines, "\n")
  end

  defp format_characters([]), do: "(없음)"

  defp format_characters(characters) do
    characters
    |> Enum.map(fn c ->
      hp = if c["hp_current"] && c["hp_max"], do: " HP #{c["hp_current"]}/#{c["hp_max"]}", else: ""
      "- #{c["name"]}#{hp}"
    end)
    |> Enum.join("\n")
  end

  defp format_npcs(npcs) when map_size(npcs) == 0, do: "(없음)"

  defp format_npcs(npcs) do
    npcs
    |> Enum.map(fn {name, data} ->
      desc = if data["description"], do: " — #{data["description"]}", else: ""
      "- #{name}#{desc}"
    end)
    |> Enum.join("\n")
  end

  defp format_quests([]), do: "(없음)"

  defp format_quests(quests) do
    quests
    |> Enum.map(fn q ->
      status = if q["status"], do: " [#{q["status"]}]", else: ""
      "- #{q["name"]}#{status}"
    end)
    |> Enum.join("\n")
  end

  # 현재 선택된 모델의 프로바이더에 맞는 요약 모델 반환
  defp summary_model_for(nil), do: "claude-haiku-4-5-20251001"
  defp summary_model_for(model_id) do
    case Models.provider_for(model_id) do
      :anthropic -> "claude-haiku-4-5-20251001"
      :openai -> "gpt-5.4-mini"
      :gemini -> "gemini-2.5-flash"
      _ -> "claude-haiku-4-5-20251001"
    end
  end

  defp model_opts(%{ai_model: nil}), do: []
  defp model_opts(%{ai_model: model_id}), do: [model: model_id]

  defp log_npc_changes(state, state_before) do
    if map_size(state.npcs) != map_size(state_before.npcs) do
      Logger.info(
        "NPC 상태 변경 [#{state.id}]: #{map_size(state_before.npcs)}개 → #{map_size(state.npcs)}개"
      )
    end
  end

  defp update_context_summary(state) do
    case generate_context_summary(state) do
      {:ok, new_summary} ->
        if state.context_summary && meaningful_summary?(state.context_summary) do
          Persistence.append_summary_log(state.id, state.context_summary)
        end

        Logger.info("컨텍스트 요약 갱신 [#{state.id}]")
        %{state | context_summary: new_summary}

      :skip ->
        Logger.info("컨텍스트 요약 스킵 [#{state.id}] — AI 응답 없음")
        state

      {:error, reason} ->
        Logger.warning("컨텍스트 요약 생성 실패 [#{state.id}]: #{inspect(reason)}")
        state
    end
  end

  defp update_combat_history_summary(state) do
    case generate_combat_history_summary(state) do
      {:ok, summary} ->
        Logger.info("전투 히스토리 요약 갱신 [#{state.id}]")
        %{state | combat_history_summary: summary}

      {:error, reason} ->
        Logger.warning("전투 히스토리 요약 생성 실패 [#{state.id}]: #{inspect(reason)}")
        state
    end
  end

  defp generate_combat_history_summary(state) do
    ai_messages =
      Enum.filter(state.combat_history, fn %{"role" => role} -> role == "assistant" end)

    if ai_messages == [] do
      {:ok, nil}
    else
      haiku_model = summary_model_for(state.ai_model)
      previous = state.combat_history_summary || "(전투 시작 — 이전 요약 없음)"

      # 이전 요약 + 최근 AI 응답만 통합 (누적 방식, 매번 전체를 다시 요약하지 않음)
      recent_ai = Enum.take(ai_messages, -3)

      new_exchange =
        recent_ai
        |> Enum.map(fn %{"content" => content} ->
          "DM: #{String.slice(content, 0, 800)}"
        end)
        |> Enum.join("\n")

      combatants_status = format_combatants_status(state)

      summary_prompt = """
      당신은 TRPG 전투 기록 요약 도우미입니다.
      [중요] 반드시 이전 요약의 핵심 정보를 보존하면서 최근 전투 내용을 통합하세요.

      ## 이전 전투 요약
      #{previous}

      ## 최근 전투 진행 (최대 3건)
      #{new_exchange}

      ## 현재 참가자 상태
      #{combatants_status}

      ## 지시사항
      위 정보를 하나의 간결한 전투 요약으로 통합하세요 (최대 400자).
      반드시 포함할 내용:
      - 각 라운드의 주요 공격/피해
      - 현재 적의 상태 (HP 변화, 사망 여부)
      - 현재 아군의 상태 (HP 변화)
      - 사용된 주요 능력이나 주문
      마크다운 서식을 사용하지 마세요. 순수 텍스트로만 작성하세요.
      """

      summary_messages = [%{"role" => "user", "content" => summary_prompt}]

      case Client.chat("You are a TRPG combat summarizer.", summary_messages, [],
             model: haiku_model,
             max_tokens: 600
           ) do
        {:ok, result} -> {:ok, result.text}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp generate_post_combat_summary(state) do
    ai_messages =
      Enum.filter(state.combat_history, fn %{"role" => role} -> role == "assistant" end)

    if ai_messages == [] do
      {:ok, nil}
    else
      haiku_model = summary_model_for(state.ai_model)

      combat_exchanges =
        ai_messages
        |> Enum.map(fn %{"content" => content} ->
          "DM: #{String.slice(content, 0, 800)}"
        end)
        |> Enum.join("\n")

      combatants_status = format_combatants_status(state)

      summary_prompt = """
      당신은 TRPG 전투 기록 요약 도우미입니다. 전투가 끝났습니다.

      ## 전투 전체 기록
      #{combat_exchanges}

      ## 전투 종료 시 참가자 상태
      #{combatants_status}

      ## 지시사항
      위 전투 전체를 간결하게 요약하세요 (최대 500자).
      반드시 포함할 내용:
      - 전투 참가자 (아군, 적)와 최종 상태 (HP, 사망 여부)
      - 전투의 전개 과정 (주요 전환점)
      - 전투 결과 (승패, 사상자)
      - 획득한 전리품이나 경험치 (언급된 경우)
      마크다운 서식을 사용하지 마세요. 순수 텍스트로만 작성하세요.
      """

      summary_messages = [%{"role" => "user", "content" => summary_prompt}]

      case Client.chat("You are a TRPG combat summarizer.", summary_messages, [],
             model: haiku_model,
             max_tokens: 800
           ) do
        {:ok, result} -> {:ok, result.text}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # 도구 결과 리스트를 순회하며 캠페인 상태에 반영한다.
  # 각 도구별로 apply_single_tool_result/2를 호출하여 캐릭터, NPC, 퀘스트, 위치, 전투 상태를 갱신.
  defp apply_tool_results(state, tool_results) do
    Enum.reduce(tool_results, state, fn result, acc ->
      apply_single_tool_result(acc, result)
    end)
  end

  defp apply_single_tool_result(state, %{tool: "update_character", input: input}) do
    char_name = input["character_name"]
    changes = input["changes"] || %{}

    Logger.info("캐릭터 업데이트: #{char_name} — #{inspect(changes)}")

    characters =
      case find_character_index(state.characters, char_name) do
        nil ->
          # 캐릭터는 반드시 위자드(character_create_live)를 통해서만 생성된다.
          # AI가 update_character로 새 캐릭터를 만드는 것은 허용하지 않는다.
          Logger.warning("update_character: '#{char_name}' 캐릭터 없음 — 무시 (위자드로만 캐릭터 생성 가능)")
          state.characters

        idx ->
          List.update_at(state.characters, idx, fn char ->
            updated = apply_character_changes(char, changes)
            # 레벨이 증가했고 hp_max가 명시되지 않은 경우 자동으로 HP/숙련보너스 재계산
            maybe_apply_level_up_stats(char, updated, changes)
          end)
      end

    state = %{state | characters: characters}

    # 전투 중이면 combat_state["enemies"]의 HP도 동기화
    sync_enemy_hp_to_combat_state(state, char_name, changes)
  end

  # update_character 후 combat_state["enemies"]의 HP를 동기화
  defp sync_enemy_hp_to_combat_state(%{combat_state: nil} = state, _name, _changes), do: state

  defp sync_enemy_hp_to_combat_state(state, char_name, changes) do
    enemies = get_in(state.combat_state, ["enemies"]) || []
    hp_current = changes["hp_current"]
    normalized = char_name |> String.trim() |> String.downcase()

    match? = fn e -> (e["name"] || "") |> String.trim() |> String.downcase() == normalized end

    if hp_current && Enum.any?(enemies, match?) do
      updated_enemies =
        Enum.map(enemies, fn e ->
          if match?.(e) do
            e
            |> Map.put("hp_current", hp_current)
            |> then(fn e2 ->
              if changes["hp_max"], do: Map.put(e2, "hp_max", changes["hp_max"]), else: e2
            end)
          else
            e
          end
        end)

      put_in(state.combat_state["enemies"], updated_enemies)
    else
      state
    end
  end

  defp apply_single_tool_result(state, %{tool: "register_npc", input: input}) do
    name = input["name"]
    Logger.info("NPC 등록: #{name}")

    npc_data =
      Map.merge(
        Map.get(state.npcs, name, %{}),
        input |> Map.drop(["name"]) |> Map.reject(fn {_k, v} -> is_nil(v) end)
      )
      |> Map.put("name", name)

    %{state | npcs: Map.put(state.npcs, name, npc_data)}
  end

  defp apply_single_tool_result(state, %{tool: "update_quest", input: input}) do
    quest_name = input["quest_name"]

    quests =
      case Enum.find_index(state.active_quests, &(&1["name"] == quest_name)) do
        nil ->
          state.active_quests ++
            [
              %{
                "name" => quest_name,
                "status" => input["status"] || "발견",
                "description" => input["description"],
                "notes" => input["notes"]
              }
            ]

        idx ->
          List.update_at(state.active_quests, idx, fn quest ->
            quest
            |> maybe_put("status", input["status"])
            |> maybe_put("description", input["description"])
            |> maybe_put("notes", input["notes"])
          end)
      end

    %{state | active_quests: quests}
  end

  defp apply_single_tool_result(state, %{tool: "set_location", input: input}) do
    Logger.info("위치 변경: #{state.current_location} → #{input["location_name"]}")
    %{state | current_location: input["location_name"]}
  end

  defp apply_single_tool_result(state, %{tool: "start_combat", input: input}) do
    if state.combat_state do
      Logger.warning("[Campaign #{state.id}] 기존 전투가 진행 중인데 새 전투가 시작됨. 기존 전투를 덮어씁니다.")
    end

    participants = input["participants"] || []
    enemies = input["enemies"]
    Logger.info("전투 시작: #{Enum.join(participants, ", ")}")

    player_names = Enum.map(state.characters, fn c -> c["name"] end)

    combat = %{
      "participants" => participants,
      "round" => 1,
      "turn_order" => [],
      "player_names" => player_names
    }

    combat =
      if is_list(enemies) && enemies != [] do
        Map.put(combat, "enemies", enemies)
      else
        combat
      end

    %{state | phase: :combat, combat_state: combat}
  end

  defp apply_single_tool_result(state, %{tool: "end_combat", input: input}) do
    Logger.info("전투 종료")
    player_names = get_in(state.combat_state, ["player_names"]) || []

    characters =
      if player_names != [] do
        Enum.filter(state.characters, fn c -> c["name"] in player_names end)
      else
        state.characters
      end

    xp_gained = input["xp"] || 0

    characters =
      if xp_gained > 0 do
        Enum.map(characters, fn char -> apply_xp_gain(char, xp_gained) end)
      else
        characters
      end

    %{state | phase: :exploration, combat_state: nil, characters: characters}
  end

  defp apply_single_tool_result(state, %{tool: "level_up", input: input}) do
    alias TrpgMaster.Rules.CharacterData
    char_name = input["character_name"]
    asi = input["asi"]
    feat = input["feat"]
    subclass = input["subclass"]
    new_spells = input["new_spells"]
    Logger.info("레벨업 요청: #{char_name}")

    characters =
      case find_character_index(state.characters, char_name) do
        nil ->
          Logger.warning("레벨업 대상 캐릭터 없음: #{char_name}")
          state.characters

        idx ->
          List.update_at(state.characters, idx, fn char ->
            current_level = char["level"] || 1
            current_xp = char["xp"] || 0
            xp_based_level = min(CharacterData.level_for_xp(current_xp), 20)
            # XP 기반 레벨이 더 높으면 그것을 사용, 아니면 1레벨 강제 상승
            target_level = if xp_based_level > current_level, do: xp_based_level, else: current_level + 1
            target_level = min(target_level, 20)

            if target_level > current_level do
              Logger.info("레벨업 적용: #{char_name} #{current_level} → #{target_level}")
              char
              |> apply_level_up(current_level, target_level)
              |> apply_asi(asi)
              |> apply_feat(feat)
              |> apply_subclass(subclass)
              |> apply_new_spells(new_spells)
              # ASI 레벨인데 ASI/feat 선택이 없으면 대기 플래그 설정
              |> then(fn c ->
                if CharacterData.asi_level?(target_level, char["class_id"]) && is_nil(asi) && is_nil(feat) do
                  Map.put(c, "asi_pending", true)
                else
                  Map.delete(c, "asi_pending")
                end
              end)
              # 서브클래스 선택 레벨인데 아직 서브클래스가 없으면 대기 플래그 설정
              |> then(fn c ->
                if CharacterData.subclass_level?(target_level, char["class_id"]) &&
                     is_nil(subclass) && is_nil(c["subclass"]) do
                  Map.put(c, "subclass_pending", true)
                else
                  Map.delete(c, "subclass_pending")
                end
              end)
            else
              Logger.info("레벨업 조건 미충족 또는 최대 레벨: #{char_name} (현재 레벨: #{current_level})")
              char
            end
          end)
      end

    %{state | characters: characters}
  end

  @max_journal_entries 100

  defp apply_single_tool_result(state, %{tool: "write_journal", input: input}) do
    entry_text = input["entry"]
    category = input["category"] || "note"

    entry = %{
      "text" => entry_text,
      "category" => category,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Logger.info("저널 기록 [#{state.id}] [#{category}]: #{String.slice(entry_text, 0, 50)}...")

    entries = (state.journal_entries ++ [entry]) |> Enum.take(-@max_journal_entries)
    %{state | journal_entries: entries}
  end

  defp apply_single_tool_result(state, %{tool: "read_journal", input: _input}) do
    # read_journal은 Tools.execute에서 프로세스 딕셔너리로 처리하므로 상태 변경 없음
    state
  end

  defp apply_single_tool_result(state, result) do
    Logger.debug("알 수 없는 도구 결과 무시: #{inspect(result.tool)}")
    state
  end

  # XP 획득 및 레벨업 처리
  defp apply_xp_gain(char, xp_gained) do
    alias TrpgMaster.Rules.CharacterData

    current_xp = char["xp"] || 0
    current_level = char["level"] || 1
    new_xp = current_xp + xp_gained
    new_level = min(CharacterData.level_for_xp(new_xp), 20)

    char = Map.put(char, "xp", new_xp)
    Logger.info("XP 획득: #{char["name"]} #{current_xp} → #{new_xp} XP")

    if new_level > current_level do
      Logger.info("레벨업 발생: #{char["name"]} #{current_level} → #{new_level}")
      leveled = apply_level_up(char, current_level, new_level)
      # ASI 레벨이면 플래그 설정 (AI가 다음 턴에 플레이어에게 선택 요청)
      leveled =
        if TrpgMaster.Rules.CharacterData.asi_level?(new_level, char["class_id"]) do
          Map.put(leveled, "asi_pending", true)
        else
          leveled
        end
      # 서브클래스 선택 레벨이고 아직 서브클래스가 없으면 플래그 설정
      if TrpgMaster.Rules.CharacterData.subclass_level?(new_level, char["class_id"]) &&
           is_nil(char["subclass"]) do
        Map.put(leveled, "subclass_pending", true)
      else
        leveled
      end
    else
      char
    end
  end

  # 레벨업 시 HP, 숙련 보너스, 주문 슬롯을 재계산한다.
  defp apply_level_up(char, old_level, new_level) do
    alias TrpgMaster.Rules.CharacterData

    con_mod = get_in(char, ["ability_modifiers", "con"]) || 0
    hit_die = CharacterData.parse_hit_die(char["hit_die"])

    levels_gained = new_level - old_level
    # D&D 5e 평균 규칙: floor(hit_die / 2) + 1 + CON 수정치, 최소 1
    hp_per_level = max(div(hit_die, 2) + 1 + con_mod, 1)
    hp_increase = hp_per_level * levels_gained

    new_hp_max = (char["hp_max"] || 1) + hp_increase
    new_prof_bonus = CharacterData.proficiency_bonus_for_level(new_level)

    # 주문 슬롯 갱신
    class_id = char["class_id"]
    new_spell_slots = CharacterData.spell_slots_for_class_level(class_id, new_level)

    # 소마법/주문 습득 가능 수 갱신 (AI가 new_spells 선택 시 참고)
    new_cantrips_count = CharacterData.cantrips_known_for_class_level(class_id, new_level)
    new_spells_count = CharacterData.spells_known_for_class_level(class_id, new_level)

    # 레벨업으로 새로 획득하는 클래스 피처 누적
    new_class_features = CharacterData.class_features_for_levels(class_id, old_level + 1, new_level)
    existing_class_features = char["class_features"] || []
    merged_class_features = existing_class_features ++ new_class_features

    # 서브클래스 피처 누적 (서브클래스가 이미 선택된 경우, apply_subclass보다 먼저 실행되므로 기존 서브클래스만 처리)
    subclass_id = char["subclass_id"]
    new_subclass_features =
      if subclass_id do
        CharacterData.subclass_features_for_levels(subclass_id, old_level + 1, new_level)
      else
        []
      end

    existing_subclass_features = char["subclass_features"] || []
    merged_subclass_features = existing_subclass_features ++ new_subclass_features

    char
    |> Map.put("level", new_level)
    |> Map.put("hp_max", new_hp_max)
    |> Map.put("hp_current", (char["hp_current"] || 1) + hp_increase)
    |> Map.put("proficiency_bonus", new_prof_bonus)
    |> Map.put("class_features", merged_class_features)
    |> Map.put("subclass_features", merged_subclass_features)
    |> then(fn c ->
      if new_spell_slots do
        c
        |> Map.put("spell_slots", new_spell_slots)
        |> Map.update("spell_slots_used", %{}, fn used ->
          # 새로 추가된 슬롯 레벨은 사용량 0으로 초기화, 기존 사용량 유지
          Map.merge(used, Map.new(new_spell_slots, fn {lvl, _} -> {lvl, Map.get(used, lvl, 0)} end))
        end)
      else
        c
      end
    end)
    |> then(fn c ->
      c = if new_cantrips_count, do: Map.put(c, "cantrips_known_count", new_cantrips_count), else: c
      if new_spells_count, do: Map.put(c, "spells_known_count", new_spells_count), else: c
    end)
  end

  # ASI(능력치 향상) 적용: 지정된 능력치를 올리되 상한 20 적용
  defp apply_asi(char, asi) when is_map(asi) do
    abilities = char["abilities"] || %{}

    new_abilities =
      Enum.reduce(asi, abilities, fn {stat, amount}, acc ->
        current = acc[stat] || 10
        Map.put(acc, stat, min(current + amount, 20))
      end)

    new_modifiers =
      Map.new(new_abilities, fn {k, v} ->
        {k, TrpgMaster.Rules.CharacterData.ability_modifier(v)}
      end)

    char
    |> Map.put("abilities", new_abilities)
    |> Map.put("ability_modifiers", new_modifiers)
  end
  defp apply_asi(char, _), do: char

  # 특기(Feat) 습득: level_up의 feat 파라미터로 전달된 특기 이름을 feats 목록에 추가한다.
  # dnd_reference_ko feats 데이터에서 매칭을 시도하고, 없으면 이름 그대로 추가한다.
  defp apply_feat(char, feat_name) when is_binary(feat_name) and feat_name != "" do
    alias TrpgMaster.Rules.CharacterData
    name_lower = String.downcase(feat_name)

    resolved_name =
      CharacterData.feats()
      |> Enum.find(fn f ->
        ko = get_in(f, ["name", "ko"]) || ""
        en = get_in(f, ["name", "en"]) || ""
        String.downcase(ko) == name_lower || String.downcase(en) == name_lower
      end)
      |> case do
        nil -> feat_name
        f -> get_in(f, ["name", "ko"]) || get_in(f, ["name", "en"]) || feat_name
      end

    existing = char["feats"] || []
    if resolved_name in existing do
      char
    else
      Map.put(char, "feats", existing ++ [resolved_name])
    end
  end
  defp apply_feat(char, _), do: char

  # 서브클래스 선택: level_up의 subclass 파라미터로 전달된 서브클래스를 캐릭터에 저장한다.
  # dnd_reference_ko 서브클래스 데이터에서 이름 매칭 후 한국어 이름으로 저장한다.
  # 선택 레벨(보통 3레벨)의 서브클래스 피처를 즉시 부여한다.
  defp apply_subclass(char, subclass_name) when is_binary(subclass_name) and subclass_name != "" do
    alias TrpgMaster.Rules.CharacterData
    class_id = char["class_id"]
    resolved = CharacterData.resolve_subclass_name(class_id, subclass_name)
    subclass_id = CharacterData.resolve_subclass_id(class_id, subclass_name)
    Logger.info("서브클래스 선택: #{char["name"]} → #{resolved} (id: #{subclass_id})")

    char = Map.put(char, "subclass", resolved)
    char = if subclass_id, do: Map.put(char, "subclass_id", subclass_id), else: char

    # 선택 레벨의 서브클래스 피처 즉시 부여
    if subclass_id do
      selection_level = char["level"] || 1
      new_features =
        CharacterData.subclass_features_for_level(subclass_id, selection_level)
        |> Enum.map(fn name -> %{"name" => name, "level" => selection_level} end)

      existing = char["subclass_features"] || []
      Map.put(char, "subclass_features", existing ++ new_features)
    else
      char
    end
  end
  defp apply_subclass(char, _), do: char

  # 새 주문 습득: level_up의 new_spells 파라미터로 전달된 주문을 spells_known에 추가한다.
  # 주문은 %{"name" => "...", "level" => 0~9} 형태의 맵 목록.
  # spells_known 구조: %{"cantrips" => [...], "1" => [...], "2" => [...], ...}
  defp apply_new_spells(char, nil), do: char
  defp apply_new_spells(char, []), do: char

  defp apply_new_spells(char, new_spells) when is_list(new_spells) do
    Enum.reduce(new_spells, char, fn spell, acc ->
      spell_name = spell["name"] || inspect(spell)

      level_key =
        case spell["level"] do
          0 -> "cantrips"
          n when is_integer(n) and n >= 1 -> Integer.to_string(n)
          _ -> "1"
        end

      Map.update(acc, "spells_known", %{}, fn known ->
        Map.update(known, level_key, [spell_name], fn existing ->
          if spell_name in existing, do: existing, else: existing ++ [spell_name]
        end)
      end)
    end)
  end

  defp apply_new_spells(char, _), do: char

  # update_character로 수동 레벨업 시, hp_max가 명시되지 않으면 자동 재계산
  defp maybe_apply_level_up_stats(old_char, new_char, changes) do
    old_level = old_char["level"] || 1
    new_level = new_char["level"] || 1

    if new_level > old_level && is_nil(changes["hp_max"]) do
      apply_level_up(new_char, old_level, new_level)
    else
      new_char
    end
  end

  # 이름으로 캐릭터 인덱스를 찾는다. trim + downcase로 유연하게 매칭한다.
  defp find_character_index(characters, name) when is_binary(name) do
    normalized = name |> String.trim() |> String.downcase()
    Enum.find_index(characters, fn c ->
      (c["name"] || "") |> String.trim() |> String.downcase() == normalized
    end)
  end
  defp find_character_index(_characters, _name), do: nil

  # 캐릭터 맵에 변경사항을 적용한다.
  # 지원 필드: hp_current, hp_max, class, level, xp, ac, spell_slots, spell_slots_used,
  #           race, inventory, proficiency_bonus, abilities, ability_modifiers
  # 리스트 필드: inventory_add/remove, conditions_add/remove
  defp apply_character_changes(char, changes) do
    char
    |> maybe_put("hp_current", changes["hp_current"])
    |> maybe_put("hp_max", changes["hp_max"])
    |> maybe_put("class", changes["class"])
    |> maybe_put("level", changes["level"])
    |> maybe_put("xp", changes["xp"])
    |> maybe_put("ac", changes["ac"])
    |> maybe_put("spell_slots", changes["spell_slots"])
    |> merge_spell_slots_used(changes["spell_slots_used"])
    |> maybe_put("race", changes["race"])
    |> maybe_put("inventory", changes["inventory"])
    |> maybe_put("proficiency_bonus", changes["proficiency_bonus"])
    |> maybe_put("abilities", changes["abilities"])
    |> maybe_put("ability_modifiers", changes["ability_modifiers"])
    |> apply_list_change("inventory", changes["inventory_add"], changes["inventory_remove"])
    |> apply_list_change("conditions", changes["conditions_add"], changes["conditions_remove"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp apply_list_change(map, key, add, remove) do
    current = Map.get(map, key, [])
    current = if is_list(add), do: current ++ add, else: current
    current = if is_list(remove), do: current -- remove, else: current
    Map.put(map, key, current)
  end

  # spell_slots_used를 단순 교체 대신 머지 방식으로 갱신하고, 슬롯 초과 사용을 검증한다.
  defp merge_spell_slots_used(char, nil), do: char

  defp merge_spell_slots_used(char, new_used) when is_map(new_used) do
    current = char["spell_slots_used"] || %{}
    merged = Map.merge(current, new_used)
    char = Map.put(char, "spell_slots_used", merged)
    validate_spell_slots_used(char)
  end

  # spell_slots_used 값이 spell_slots 최대치를 초과하지 않도록 검증한다.
  defp validate_spell_slots_used(char) do
    slots = char["spell_slots"] || %{}
    used = char["spell_slots_used"] || %{}

    validated =
      Map.new(used, fn {level, count} ->
        max_slots = slots[level] || 0
        {level, min(count, max_slots)}
      end)

    Map.put(char, "spell_slots_used", validated)
  end
end
