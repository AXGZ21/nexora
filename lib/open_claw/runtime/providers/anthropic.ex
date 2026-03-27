defmodule OpenClaw.Runtime.Providers.Anthropic do
  @moduledoc "Anthropic Claude provider."
  @behaviour OpenClaw.Runtime.LLMClient
  require Logger

  @api_url "https://api.anthropic.com/v1/messages"

  @impl true
  def chat(model, messages, system_prompt, opts \\ []) do
    api_key = api_key()

    if is_nil(api_key) do
      {:ok, %{
        content: "[Anthropic API key not configured. Set ANTHROPIC_API_KEY environment variable.]",
        tokens: 0,
        cost: 0.0
      }}
    else
      formatted = format_messages(messages)

      body = Jason.encode!(%{
        model: model,
        max_tokens: Keyword.get(opts, :max_tokens, 4096),
        system: system_prompt,
        messages: formatted
      })

      headers = [
        {"content-type", "application/json"},
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"}
      ]

      case :httpc.request(:post, {~c"#{@api_url}", headers_to_charlist(headers), ~c"application/json", body}, [{:timeout, 120_000}], []) do
        {:ok, {{_, 200, _}, _, resp_body}} ->
          response = Jason.decode!(to_string(resp_body))
          content = get_in(response, ["content", Access.at(0), "text"]) || ""
          input_tokens = get_in(response, ["usage", "input_tokens"]) || 0
          output_tokens = get_in(response, ["usage", "output_tokens"]) || 0
          total_tokens = input_tokens + output_tokens
          cost = calculate_cost(model, input_tokens, output_tokens)

          {:ok, %{content: content, tokens: total_tokens, cost: cost}}

        {:ok, {{_, status, _}, _, resp_body}} ->
          Logger.error("Anthropic API error #{status}: #{resp_body}")
          {:error, "API error: #{status}"}

        {:error, reason} ->
          Logger.error("Anthropic request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @impl true
  def stream(model, messages, system_prompt, opts \\ []) do
    # For now, fall back to non-streaming
    case chat(model, messages, system_prompt, opts) do
      {:ok, response} -> {:ok, [response.content]}
      error -> error
    end
  end

  @impl true
  def models do
    [
      "claude-opus-4-6",
      "claude-sonnet-4-6",
      "claude-haiku-4-5"
    ]
  end

  defp api_key, do: System.get_env("ANTHROPIC_API_KEY")

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      %{"role" => msg.role || msg[:role], "content" => msg.content || msg[:content]}
    end)
  end

  defp headers_to_charlist(headers) do
    Enum.map(headers, fn {k, v} -> {~c"#{k}", ~c"#{v}"} end)
  end

  defp calculate_cost(model, input_tokens, output_tokens) do
    {input_rate, output_rate} = case model do
      m when m in ["claude-opus-4-6"] -> {15.0 / 1_000_000, 75.0 / 1_000_000}
      m when m in ["claude-sonnet-4-6"] -> {3.0 / 1_000_000, 15.0 / 1_000_000}
      m when m in ["claude-haiku-4-5"] -> {0.80 / 1_000_000, 4.0 / 1_000_000}
      _ -> {3.0 / 1_000_000, 15.0 / 1_000_000}
    end

    input_tokens * input_rate + output_tokens * output_rate
  end
end
