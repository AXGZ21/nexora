defmodule OpenClaw.Runtime.CustomProvider do
  @moduledoc """
  Manages user-defined custom LLM providers.

  Supports any OpenAI-compatible API endpoint, allowing users
  to connect to:
  - Self-hosted models (vLLM, text-generation-inference, llama.cpp)
  - Alternative providers (Together, Groq, Fireworks, Mistral)
  - Custom gateways and proxies
  - Enterprise internal endpoints
  """
  use GenServer

  @table :custom_providers

  defstruct [
    :id,
    :name,
    :base_url,
    :api_key_env,
    :auth_header,
    :models,
    :default_model,
    :max_tokens,
    :extra_headers,
    :request_format,
    enabled: true,
    created_at: nil
  ]

  # --- Client API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def register(provider_config) do
    GenServer.call(__MODULE__, {:register, provider_config})
  end

  def unregister(id) do
    GenServer.call(__MODULE__, {:unregister, id})
  end

  def list do
    GenServer.call(__MODULE__, :list)
  end

  def get(id) do
    GenServer.call(__MODULE__, {:get, id})
  end

  def update(id, changes) do
    GenServer.call(__MODULE__, {:update, id, changes})
  end

  def chat(provider_id, model, messages, system_prompt, opts \\ []) do
    case get(provider_id) do
      nil -> {:error, :provider_not_found}
      provider -> do_chat(provider, model, messages, system_prompt, opts)
    end
  end

  # --- Server ---

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])

    # Register some default custom providers
    defaults = [
      %__MODULE__{
        id: "together",
        name: "Together AI",
        base_url: "https://api.together.xyz/v1/chat/completions",
        api_key_env: "TOGETHER_API_KEY",
        auth_header: "Bearer",
        models: ["meta-llama/Llama-3.1-70B-Instruct", "mistralai/Mixtral-8x7B-Instruct-v0.1"],
        default_model: "meta-llama/Llama-3.1-70B-Instruct",
        max_tokens: 4096,
        request_format: :openai,
        created_at: DateTime.utc_now()
      },
      %__MODULE__{
        id: "groq",
        name: "Groq",
        base_url: "https://api.groq.com/openai/v1/chat/completions",
        api_key_env: "GROQ_API_KEY",
        auth_header: "Bearer",
        models: ["llama-3.1-70b-versatile", "mixtral-8x7b-32768", "gemma2-9b-it"],
        default_model: "llama-3.1-70b-versatile",
        max_tokens: 4096,
        request_format: :openai,
        created_at: DateTime.utc_now()
      },
      %__MODULE__{
        id: "fireworks",
        name: "Fireworks AI",
        base_url: "https://api.fireworks.ai/inference/v1/chat/completions",
        api_key_env: "FIREWORKS_API_KEY",
        auth_header: "Bearer",
        models: ["accounts/fireworks/models/llama-v3p1-70b-instruct"],
        default_model: "accounts/fireworks/models/llama-v3p1-70b-instruct",
        max_tokens: 4096,
        request_format: :openai,
        created_at: DateTime.utc_now()
      },
      %__MODULE__{
        id: "mistral",
        name: "Mistral AI",
        base_url: "https://api.mistral.ai/v1/chat/completions",
        api_key_env: "MISTRAL_API_KEY",
        auth_header: "Bearer",
        models: ["mistral-large-latest", "mistral-medium-latest", "codestral-latest"],
        default_model: "mistral-large-latest",
        max_tokens: 4096,
        request_format: :openai,
        created_at: DateTime.utc_now()
      }
    ]

    for p <- defaults, do: :ets.insert(@table, {p.id, p})
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, config}, _from, state) do
    provider = %__MODULE__{
      id: config[:id] || generate_id(),
      name: config[:name] || "Custom Provider",
      base_url: config[:base_url],
      api_key_env: config[:api_key_env],
      auth_header: config[:auth_header] || "Bearer",
      models: config[:models] || [],
      default_model: config[:default_model],
      max_tokens: config[:max_tokens] || 4096,
      extra_headers: config[:extra_headers] || %{},
      request_format: config[:request_format] || :openai,
      enabled: true,
      created_at: DateTime.utc_now()
    }

    :ets.insert(@table, {provider.id, provider})

    Phoenix.PubSub.broadcast(OpenClaw.PubSub, "providers", {:provider_registered, provider})
    {:reply, {:ok, provider}, state}
  end

  def handle_call({:unregister, id}, _from, state) do
    :ets.delete(@table, id)
    Phoenix.PubSub.broadcast(OpenClaw.PubSub, "providers", {:provider_unregistered, id})
    {:reply, :ok, state}
  end

  def handle_call(:list, _from, state) do
    providers = :ets.tab2list(@table) |> Enum.map(fn {_id, p} -> p end)
    {:reply, providers, state}
  end

  def handle_call({:get, id}, _from, state) do
    case :ets.lookup(@table, id) do
      [{_, provider}] -> {:reply, provider, state}
      [] -> {:reply, nil, state}
    end
  end

  def handle_call({:update, id, changes}, _from, state) do
    case :ets.lookup(@table, id) do
      [{_, provider}] ->
        updated = Enum.reduce(changes, provider, fn {k, v}, acc ->
          Map.put(acc, k, v)
        end)
        :ets.insert(@table, {id, updated})
        {:reply, {:ok, updated}, state}
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  # --- Private ---

  defp do_chat(provider, model, messages, system_prompt, opts) do
    api_key = OpenClaw.Runtime.ProviderConfig.get_api_key(provider.api_key_env || "")

    if is_nil(api_key) or api_key == "" do
      {:ok, %{
        content: "[#{provider.name} not configured. Set #{provider.api_key_env} environment variable.]",
        tokens: 0,
        cost: 0.0
      }}
    else
      model = model || provider.default_model
      formatted = [%{"role" => "system", "content" => system_prompt}] ++
        Enum.map(messages, fn msg ->
          %{"role" => msg[:role] || msg.role, "content" => msg[:content] || msg.content}
        end)

      body = Jason.encode!(%{
        model: model,
        max_tokens: Keyword.get(opts, :max_tokens, provider.max_tokens || 4096),
        messages: formatted
      })

      auth_value = "#{provider.auth_header} #{api_key}"
      headers = [
        {~c"content-type", ~c"application/json"},
        {~c"authorization", String.to_charlist(auth_value)}
      ]

      extra = (provider.extra_headers || %{})
        |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

      all_headers = headers ++ extra

      case :httpc.request(:post, {String.to_charlist(provider.base_url), all_headers, ~c"application/json", body}, [{:timeout, 120_000}], []) do
        {:ok, {{_, 200, _}, _, resp_body}} ->
          response = Jason.decode!(to_string(resp_body))
          content = get_in(response, ["choices", Access.at(0), "message", "content"]) || ""
          total_tokens = get_in(response, ["usage", "total_tokens"]) || 0
          {:ok, %{content: content, tokens: total_tokens, cost: 0.0}}

        {:ok, {{_, status, _}, _, resp_body}} ->
          {:error, "#{provider.name} API error #{status}: #{String.slice(to_string(resp_body), 0..200)}"}

        {:error, reason} ->
          {:error, "#{provider.name} connection error: #{inspect(reason)}"}
      end
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false) |> String.downcase()
  end
end
