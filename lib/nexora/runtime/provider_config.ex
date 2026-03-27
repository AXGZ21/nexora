defmodule Nexora.Runtime.ProviderConfig do
  @moduledoc """
  Runtime configuration store for LLM provider API keys and settings.

  Stores API keys entered via the dashboard UI in ETS, with fallback
  to environment variables. This allows full provider configuration
  from the web interface without restarts.
  """
  use GenServer

  @table :provider_config

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Get an API key: checks UI-configured first, then env var."
  def get_api_key(env_var) do
    case :ets.lookup(@table, {:api_key, env_var}) do
      [{_, value}] when value != "" and not is_nil(value) -> value
      _ -> System.get_env(env_var)
    end
  end

  @doc "Set an API key via the UI."
  def set_api_key(env_var, value) do
    GenServer.call(__MODULE__, {:set_api_key, env_var, value})
  end

  @doc "Remove a UI-configured API key (falls back to env var)."
  def clear_api_key(env_var) do
    GenServer.call(__MODULE__, {:clear_api_key, env_var})
  end

  @doc "Check if an API key is available (UI or env)."
  def has_api_key?(env_var) do
    key = get_api_key(env_var)
    not is_nil(key) and key != ""
  end

  @doc "Get the source of an API key."
  def key_source(env_var) do
    case :ets.lookup(@table, {:api_key, env_var}) do
      [{_, value}] when value != "" and not is_nil(value) -> :dashboard
      _ ->
        case System.get_env(env_var) do
          nil -> :not_set
          "" -> :not_set
          _ -> :environment
        end
    end
  end

  @doc "Mask a key for display."
  def mask_key(env_var) do
    case get_api_key(env_var) do
      nil -> nil
      "" -> nil
      key when byte_size(key) > 8 ->
        "#{String.slice(key, 0..3)}...#{String.slice(key, -4..-1)}"
      _ -> "****"
    end
  end

  @doc "Store a provider-specific setting."
  def set(key, value) do
    GenServer.call(__MODULE__, {:set, key, value})
  end

  @doc "Get a provider-specific setting."
  def get(key, default \\ nil) do
    case :ets.lookup(@table, key) do
      [{_, value}] -> value
      [] -> default
    end
  end

  @doc "Test connection to a provider endpoint."
  def test_connection(base_url, api_key, auth_header \\ "Bearer") do
    headers = [
      {~c"content-type", ~c"application/json"},
      {~c"authorization", String.to_charlist("#{auth_header} #{api_key}")}
    ]

    body = Jason.encode!(%{
      model: "test",
      messages: [%{role: "user", content: "test"}],
      max_tokens: 1
    })

    case :httpc.request(:post, {String.to_charlist(base_url), headers, ~c"application/json", body}, [{:timeout, 10_000}], []) do
      {:ok, {{_, status, _}, _, resp_body}} ->
        cond do
          status in 200..299 -> {:ok, "Connected (#{status})"}
          status == 401 -> {:error, "Authentication failed (401) - check your API key"}
          status == 403 -> {:error, "Access denied (403) - check permissions"}
          status == 404 -> {:error, "Endpoint not found (404) - check URL"}
          status == 429 -> {:ok, "Connected (rate limited, but auth works)"}
          true -> {:error, "HTTP #{status}: #{String.slice(to_string(resp_body), 0..100)}"}
        end
      {:error, {:failed_connect, _}} ->
        {:error, "Connection failed - check URL and network"}
      {:error, reason} ->
        {:error, "Error: #{inspect(reason)}"}
    end
  end

  # Server

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:set_api_key, env_var, value}, _from, state) do
    :ets.insert(@table, {{:api_key, env_var}, value})
    Phoenix.PubSub.broadcast(Nexora.PubSub, "provider_config", {:key_updated, env_var})
    {:reply, :ok, state}
  end

  def handle_call({:clear_api_key, env_var}, _from, state) do
    :ets.delete(@table, {:api_key, env_var})
    Phoenix.PubSub.broadcast(Nexora.PubSub, "provider_config", {:key_cleared, env_var})
    {:reply, :ok, state}
  end

  def handle_call({:set, key, value}, _from, state) do
    :ets.insert(@table, {key, value})
    {:reply, :ok, state}
  end
end
