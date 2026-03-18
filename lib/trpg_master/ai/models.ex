defmodule TrpgMaster.AI.Models do
  @moduledoc """
  지원하는 AI 모델 목록과 API 키 가용성을 관리한다.
  """

  @models [
    %{
      id: "claude-sonnet-4-6",
      name: "Claude Sonnet 4.6",
      provider: :anthropic,
      env: "ANTHROPIC_API_KEY",
      config_key: :anthropic_api_key
    },
    %{
      id: "claude-haiku-4-5-20251001",
      name: "Claude Haiku 4.5",
      provider: :anthropic,
      env: "ANTHROPIC_API_KEY",
      config_key: :anthropic_api_key
    },
    %{
      id: "gpt-5.4",
      name: "GPT-5.4",
      provider: :openai,
      env: "OPENAI_API_KEY",
      config_key: :openai_api_key
    },
    %{
      id: "gpt-5.4-mini",
      name: "GPT-5.4 Mini",
      provider: :openai,
      env: "OPENAI_API_KEY",
      config_key: :openai_api_key
    },
    %{
      id: "gemini-3.1-pro-preview",
      name: "Gemini 3.1 Pro Preview",
      provider: :gemini,
      env: "GOOGLE_API_KEY",
      config_key: :google_api_key
    },
    %{
      id: "gemini-2.5-flash",
      name: "Gemini 2.5 Flash",
      provider: :gemini,
      env: "GOOGLE_API_KEY",
      config_key: :google_api_key
    }
  ]

  @doc "전체 모델 목록 반환"
  def all, do: @models

  @doc "모델 ID로 모델 정보 조회"
  def find(model_id), do: Enum.find(@models, &(&1.id == model_id))

  @doc "모델 ID에 해당하는 프로바이더 atom 반환"
  def provider_for(model_id) do
    case find(model_id) do
      nil -> nil
      model -> model.provider
    end
  end

  @doc "해당 모델의 API 키가 설정되어 있는지 확인"
  def api_key_configured?(model_id) do
    case find(model_id) do
      nil -> false
      model ->
        key = Application.get_env(:trpg_master, model.config_key)
        not (is_nil(key) or key == "")
    end
  end

  @doc "각 모델에 available 상태를 포함한 목록 반환"
  def list_with_status do
    Enum.map(@models, fn model ->
      Map.put(model, :available, api_key_configured?(model.id))
    end)
  end

  @doc "현재 설정된 기본 모델 ID 반환"
  def default_model do
    Application.get_env(:trpg_master, :ai_model, "claude-sonnet-4-6")
  end

  @doc "프로바이더 이름을 한국어로 반환"
  def provider_label(:anthropic), do: "Anthropic"
  def provider_label(:openai), do: "OpenAI"
  def provider_label(:gemini), do: "Google Gemini"
  def provider_label(_), do: "Unknown"
end
