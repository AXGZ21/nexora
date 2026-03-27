defmodule OpenClaw.Runtime.Providers.Google do
  @moduledoc "Google Gemini provider."
  @behaviour OpenClaw.Runtime.LLMClient

  @impl true
  def chat(_model, _messages, _system_prompt, _opts \\ []) do
    {:ok, %{
      content: "[Google Gemini provider not yet configured. Set GOOGLE_API_KEY environment variable.]",
      tokens: 0,
      cost: 0.0
    }}
  end

  @impl true
  def stream(model, messages, system_prompt, opts \\ []) do
    case chat(model, messages, system_prompt, opts) do
      {:ok, response} -> {:ok, [response.content]}
      error -> error
    end
  end

  @impl true
  def models do
    ["gemini-2.5-pro", "gemini-2.5-flash"]
  end
end
