defmodule OpenClaw.Runtime.Providers.Ollama do
  @moduledoc "Ollama local model provider."
  @behaviour OpenClaw.Runtime.LLMClient
  require Logger

  @impl true
  def chat(model, messages, system_prompt, _opts \\ []) do
    base_url = OpenClaw.Runtime.ProviderConfig.get_api_key("OLLAMA_URL") || "http://localhost:11434"

    formatted = [%{"role" => "system", "content" => system_prompt}] ++ format_messages(messages)

    body = Jason.encode!(%{
      model: model,
      messages: formatted,
      stream: false
    })

    url = "#{base_url}/api/chat"

    case :httpc.request(:post, {~c"#{url}", [], ~c"application/json", body}, [{:timeout, 300_000}], []) do
      {:ok, {{_, 200, _}, _, resp_body}} ->
        response = Jason.decode!(to_string(resp_body))
        content = get_in(response, ["message", "content"]) || ""
        {:ok, %{content: content, tokens: 0, cost: 0.0}}

      {:ok, {{_, status, _}, _, _}} ->
        {:ok, %{
          content: "[Ollama not available (status #{status}). Is Ollama running at #{base_url}?]",
          tokens: 0,
          cost: 0.0
        }}

      {:error, _reason} ->
        {:ok, %{
          content: "[Cannot connect to Ollama at #{base_url}. Start Ollama to use local models.]",
          tokens: 0,
          cost: 0.0
        }}
    end
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
    ["llama3.1:8b", "llama3.1:70b", "mistral", "codestral", "qwen2.5:32b"]
  end

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      %{"role" => msg.role || msg[:role], "content" => msg.content || msg[:content]}
    end)
  end
end
