defmodule Nexora.Runtime.LLMClient do
  @moduledoc """
  Unified LLM client supporting multiple providers.

  Implements a behaviour-based architecture where each provider
  (Anthropic, OpenAI, Google, Ollama) is a separate module
  conforming to the same interface.
  """
  require Logger

  @type message :: %{role: String.t(), content: String.t()}
  @type response :: %{content: String.t(), tokens: integer() | nil, cost: float() | nil}

  @callback chat(String.t(), [message()], String.t(), keyword()) ::
              {:ok, response()} | {:error, term()}
  @callback stream(String.t(), [message()], String.t(), keyword()) ::
              {:ok, [String.t()]} | {:error, term()}
  @callback models() :: [String.t()]

  @doc "Send a chat completion request to the specified provider."
  def chat(provider, model, messages, system_prompt, opts \\ []) do
    provider_module(provider).chat(model, messages, system_prompt, opts)
  end

  @doc "Stream a chat completion response."
  def stream(provider, model, messages, system_prompt, opts \\ []) do
    provider_module(provider).stream(model, messages, system_prompt, opts)
  end

  @doc "List available models for a provider."
  def models(provider) do
    provider_module(provider).models()
  end

  @doc "List all configured providers, including custom ones."
  def providers do
    built_in = [
      %{id: :anthropic, name: "Anthropic", models: models(:anthropic)},
      %{id: :openai, name: "OpenAI", models: models(:openai)},
      %{id: :google, name: "Google", models: models(:google)},
      %{id: :ollama, name: "Ollama (Local)", models: models(:ollama)}
    ]

    custom = Nexora.Runtime.CustomProvider.list()
      |> Enum.map(fn p -> %{id: {:custom, p.id}, name: p.name, models: p.models || []} end)

    built_in ++ custom
  end

  defp provider_module(:anthropic), do: Nexora.Runtime.Providers.Anthropic
  defp provider_module(:openai), do: Nexora.Runtime.Providers.OpenAI
  defp provider_module(:google), do: Nexora.Runtime.Providers.Google
  defp provider_module(:ollama), do: Nexora.Runtime.Providers.Ollama
  defp provider_module({:custom, _id}), do: :custom
  defp provider_module(other) when is_binary(other) do
    case Nexora.Runtime.CustomProvider.get(other) do
      nil -> raise("Unknown provider: #{inspect(other)}")
      _provider -> :custom
    end
  end
  defp provider_module(other), do: raise("Unknown provider: #{inspect(other)}")
end
