defmodule Nexora.Runtime.Providers.OpenAI do
  @moduledoc "OpenAI GPT provider."
  @behaviour Nexora.Runtime.LLMClient
  require Logger

  @api_url "https://api.openai.com/v1/chat/completions"

  @impl true
  def chat(model, messages, system_prompt, opts \\ []) do
    api_key = Nexora.Runtime.ProviderConfig.get_api_key("OPENAI_API_KEY")

    if is_nil(api_key) do
      {:ok, %{
        content: "[OpenAI API key not configured. Set OPENAI_API_KEY environment variable.]",
        tokens: 0,
        cost: 0.0
      }}
    else
      formatted = [%{"role" => "system", "content" => system_prompt}] ++ format_messages(messages)

      body = Jason.encode!(%{
        model: model,
        max_tokens: Keyword.get(opts, :max_tokens, 4096),
        messages: formatted
      })

      headers = [
        {"content-type", "application/json"},
        {"authorization", "Bearer #{api_key}"}
      ]

      case :httpc.request(:post, {~c"#{@api_url}", headers_to_charlist(headers), ~c"application/json", body}, [{:timeout, 120_000}], []) do
        {:ok, {{_, 200, _}, _, resp_body}} ->
          response = Jason.decode!(to_string(resp_body))
          content = get_in(response, ["choices", Access.at(0), "message", "content"]) || ""
          total_tokens = get_in(response, ["usage", "total_tokens"]) || 0
          {:ok, %{content: content, tokens: total_tokens, cost: 0.0}}

        {:ok, {{_, status, _}, _, _resp_body}} ->
          {:error, "OpenAI API error: #{status}"}

        {:error, reason} ->
          {:error, reason}
      end
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
    ["gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano", "o3", "o4-mini"]
  end

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      %{"role" => msg.role || msg[:role], "content" => msg.content || msg[:content]}
    end)
  end

  defp headers_to_charlist(headers) do
    Enum.map(headers, fn {k, v} -> {~c"#{k}", ~c"#{v}"} end)
  end
end
