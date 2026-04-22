defmodule TrpgMaster.AI.ToolContext do
  @moduledoc """
  도구 실행 중 필요한 캠페인 컨텍스트(캐릭터 목록, 저널)를 전달하기 위한 얇은 어댑터.

  AI provider → StandardChat → ToolExecution → ToolExecutor 까지 provider별
  인터페이스가 고정되어 있어 컨텍스트를 인자로 전달하기 어렵다. 그래서 GenServer
  프로세스 로컬 storage(Process dictionary)를 사용한다.

  직접 Process.put/get을 호출하는 대신 이 모듈을 통해서만 읽고 쓰도록 해서,
  스코프(생성/소비 경계)와 허용되는 키를 한 곳에서 관리한다.
  """

  @key_characters :campaign_characters
  @key_journal :journal_entries

  @type t :: %{optional(:characters) => list(map()), optional(:journal_entries) => list(map())}

  @doc """
  주어진 `context`를 Process dictionary에 심어 두고 `fun/0`을 실행한 뒤,
  실행 결과와 관계없이 컨텍스트를 제거한다.
  `context`가 `nil`이면 아무 것도 심지 않는다.
  """
  @spec with_context(nil | t(), (-> result)) :: result when result: var
  def with_context(nil, fun) when is_function(fun, 0), do: fun.()

  def with_context(context, fun) when is_map(context) and is_function(fun, 0) do
    put(context)

    try do
      fun.()
    after
      clear()
    end
  end

  @doc """
  현재 프로세스에 컨텍스트를 저장한다. `with_context/2`가 책임지는 스코프
  바깥에서는 사용을 피한다.
  """
  @spec put(t()) :: :ok
  def put(context) when is_map(context) do
    if characters = Map.get(context, :characters), do: Process.put(@key_characters, characters)
    if journal = Map.get(context, :journal_entries), do: Process.put(@key_journal, journal)
    :ok
  end

  @doc """
  현재 프로세스의 컨텍스트를 제거한다.
  """
  @spec clear() :: :ok
  def clear do
    Process.delete(@key_characters)
    Process.delete(@key_journal)
    :ok
  end

  @doc """
  현재 프로세스에 저장된 캐릭터 목록을 읽는다. 없으면 `[]`.
  """
  @spec characters() :: list(map())
  def characters, do: Process.get(@key_characters, [])

  @doc """
  현재 프로세스에 저장된 저널 목록을 읽는다. 없으면 `[]`.
  """
  @spec journal_entries() :: list(map())
  def journal_entries, do: Process.get(@key_journal, [])
end
