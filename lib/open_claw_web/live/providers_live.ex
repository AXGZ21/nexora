defmodule OpenClawWeb.ProvidersLive do
  use OpenClawWeb, :live_view

  alias OpenClaw.Runtime.CustomProvider
  alias OpenClaw.Runtime.ProviderConfig

  @built_in_providers [
    %{
      id: "anthropic",
      name: "Anthropic",
      description: "Claude models - Opus, Sonnet, Haiku",
      env_var: "ANTHROPIC_API_KEY",
      base_url: "https://api.anthropic.com/v1/messages",
      models: ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5"],
      icon_color: "text-amber-400",
      bg_color: "bg-amber-500/10"
    },
    %{
      id: "openai",
      name: "OpenAI",
      description: "GPT-4.1, o3, o4-mini models",
      env_var: "OPENAI_API_KEY",
      base_url: "https://api.openai.com/v1/chat/completions",
      models: ["gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano", "o3", "o4-mini"],
      icon_color: "text-green-400",
      bg_color: "bg-green-500/10"
    },
    %{
      id: "google",
      name: "Google AI",
      description: "Gemini models",
      env_var: "GOOGLE_API_KEY",
      base_url: "https://generativelanguage.googleapis.com/v1beta/models",
      models: ["gemini-2.0-flash", "gemini-2.0-pro"],
      icon_color: "text-blue-400",
      bg_color: "bg-blue-500/10"
    },
    %{
      id: "ollama",
      name: "Ollama",
      description: "Local models via Ollama",
      env_var: "OLLAMA_URL",
      base_url: "http://localhost:11434/api/chat",
      models: ["llama3.1", "codellama", "mistral", "phi3"],
      icon_color: "text-purple-400",
      bg_color: "bg-purple-500/10"
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(OpenClaw.PubSub, "providers")
      Phoenix.PubSub.subscribe(OpenClaw.PubSub, "provider_config")
    end

    socket = socket
      |> assign(:active_tab, :providers)
      |> assign(:page_title, "Providers")
      |> assign(:built_in, load_built_in())
      |> assign(:custom_providers, CustomProvider.list())
      |> assign(:show_add_form, false)
      |> assign(:show_key_input, nil)
      |> assign(:key_input_value, "")
      |> assign(:testing, nil)
      |> assign(:test_result, nil)
      |> assign(:editing_provider, nil)
      |> assign(:form_data, default_form())

    {:ok, socket}
  end

  defp default_form do
    %{
      "name" => "",
      "base_url" => "",
      "api_key_env" => "",
      "api_key_value" => "",
      "models" => "",
      "max_tokens" => "4096",
      "auth_header" => "Bearer"
    }
  end

  defp load_built_in do
    Enum.map(@built_in_providers, fn p ->
      source = ProviderConfig.key_source(p.env_var)
      masked = ProviderConfig.mask_key(p.env_var)
      Map.merge(p, %{key_source: source, masked_key: masked})
    end)
  end

  # --- Events ---

  @impl true
  def handle_event("toggle_add_form", _params, socket) do
    {:noreply, assign(socket, show_add_form: !socket.assigns.show_add_form, editing_provider: nil, form_data: default_form())}
  end

  def handle_event("show_key_input", %{"provider" => provider_id}, socket) do
    {:noreply, assign(socket, show_key_input: provider_id, key_input_value: "")}
  end

  def handle_event("hide_key_input", _params, socket) do
    {:noreply, assign(socket, show_key_input: nil, key_input_value: "")}
  end

  def handle_event("save_api_key", %{"env_var" => env_var, "api_key" => key}, socket) do
    key = String.trim(key)
    if key != "" do
      ProviderConfig.set_api_key(env_var, key)
      socket = socket
        |> assign(:built_in, load_built_in())
        |> assign(:show_key_input, nil)
        |> assign(:key_input_value, "")
        |> put_flash(:info, "API key saved")
      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "API key cannot be empty")}
    end
  end

  def handle_event("clear_api_key", %{"env_var" => env_var}, socket) do
    ProviderConfig.clear_api_key(env_var)
    socket = socket
      |> assign(:built_in, load_built_in())
      |> put_flash(:info, "API key cleared (will fall back to environment variable if set)")
    {:noreply, socket}
  end

  def handle_event("test_connection", %{"provider" => provider_id}, socket) do
    socket = assign(socket, testing: provider_id, test_result: nil)
    send(self(), {:do_test, provider_id})
    {:noreply, socket}
  end

  def handle_event("test_custom", %{"id" => id}, socket) do
    socket = assign(socket, testing: "custom_#{id}", test_result: nil)
    send(self(), {:do_test_custom, id})
    {:noreply, socket}
  end

  def handle_event("save_provider", %{"provider" => params}, socket) do
    models = params["models"] |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    api_key_env = String.trim(params["api_key_env"] || "")

    config = [
      name: String.trim(params["name"]),
      base_url: String.trim(params["base_url"]),
      api_key_env: api_key_env,
      auth_header: String.trim(params["auth_header"] || "Bearer"),
      models: models,
      default_model: List.first(models),
      max_tokens: String.to_integer(params["max_tokens"] || "4096"),
      request_format: :openai
    ]

    # If they provided an actual API key value, store it
    api_key_value = String.trim(params["api_key_value"] || "")
    if api_key_value != "" and api_key_env != "" do
      ProviderConfig.set_api_key(api_key_env, api_key_value)
    end

    case socket.assigns.editing_provider do
      nil ->
        case CustomProvider.register(config) do
          {:ok, _provider} ->
            socket = socket
              |> assign(:custom_providers, CustomProvider.list())
              |> assign(:show_add_form, false)
              |> assign(:form_data, default_form())
              |> put_flash(:info, "Provider registered")
            {:noreply, socket}
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
        end
      edit_id ->
        changes = Enum.into(config, %{})
        case CustomProvider.update(edit_id, changes) do
          {:ok, _} ->
            socket = socket
              |> assign(:custom_providers, CustomProvider.list())
              |> assign(:show_add_form, false)
              |> assign(:editing_provider, nil)
              |> assign(:form_data, default_form())
              |> put_flash(:info, "Provider updated")
            {:noreply, socket}
          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Update failed")}
        end
    end
  end

  def handle_event("edit_provider", %{"id" => id}, socket) do
    case CustomProvider.get(id) do
      nil -> {:noreply, socket}
      p ->
        form_data = %{
          "name" => p.name || "",
          "base_url" => p.base_url || "",
          "api_key_env" => p.api_key_env || "",
          "api_key_value" => "",
          "models" => Enum.join(p.models || [], ", "),
          "max_tokens" => to_string(p.max_tokens || 4096),
          "auth_header" => p.auth_header || "Bearer"
        }
        {:noreply, assign(socket, show_add_form: true, editing_provider: id, form_data: form_data)}
    end
  end

  def handle_event("remove_provider", %{"id" => id}, socket) do
    CustomProvider.unregister(id)
    socket = socket
      |> assign(:custom_providers, CustomProvider.list())
      |> put_flash(:info, "Provider removed")
    {:noreply, socket}
  end

  def handle_event("toggle_provider", %{"id" => id}, socket) do
    case CustomProvider.get(id) do
      nil -> {:noreply, socket}
      provider ->
        CustomProvider.update(id, enabled: !provider.enabled)
        {:noreply, assign(socket, :custom_providers, CustomProvider.list())}
    end
  end

  # --- Info handlers ---

  @impl true
  def handle_info({:do_test, provider_id}, socket) do
    provider = Enum.find(@built_in_providers, &(&1.id == provider_id))
    if provider do
      key = ProviderConfig.get_api_key(provider.env_var)
      result = if key && key != "" do
        ProviderConfig.test_connection(provider.base_url, key)
      else
        {:error, "No API key configured"}
      end
      {:noreply, assign(socket, testing: nil, test_result: {provider_id, result})}
    else
      {:noreply, assign(socket, testing: nil)}
    end
  end

  def handle_info({:do_test_custom, id}, socket) do
    case CustomProvider.get(id) do
      nil ->
        {:noreply, assign(socket, testing: nil, test_result: {"custom_#{id}", {:error, "Provider not found"}})}
      provider ->
        key = ProviderConfig.get_api_key(provider.api_key_env || "")
        result = if key && key != "" do
          ProviderConfig.test_connection(provider.base_url, key, provider.auth_header || "Bearer")
        else
          {:error, "No API key configured for #{provider.api_key_env}"}
        end
        {:noreply, assign(socket, testing: nil, test_result: {"custom_#{id}", result})}
    end
  end

  def handle_info({:provider_registered, _}, socket) do
    {:noreply, assign(socket, :custom_providers, CustomProvider.list())}
  end
  def handle_info({:provider_unregistered, _}, socket) do
    {:noreply, assign(socket, :custom_providers, CustomProvider.list())}
  end
  def handle_info({:key_updated, _}, socket) do
    {:noreply, assign(socket, :built_in, load_built_in())}
  end
  def handle_info({:key_cleared, _}, socket) do
    {:noreply, assign(socket, :built_in, load_built_in())}
  end
  def handle_info(_, socket), do: {:noreply, socket}

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8 max-w-6xl">
      <%!-- Header --%>
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-2xl font-bold text-white">LLM Providers</h2>
          <p class="text-sm text-gray-400 mt-1">Configure API keys, manage custom providers, and test connections</p>
        </div>
        <button phx-click="toggle_add_form" class="flex items-center gap-2 px-4 py-2.5 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg transition-colors">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
          </svg>
          Add Custom Provider
        </button>
      </div>

      <%!-- Stats Bar --%>
      <div class="grid grid-cols-4 gap-4">
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <p class="text-xs text-gray-500 uppercase tracking-wider">Built-in</p>
          <p class="text-2xl font-bold text-white mt-1"><%= length(@built_in) %></p>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <p class="text-xs text-gray-500 uppercase tracking-wider">Custom</p>
          <p class="text-2xl font-bold text-white mt-1"><%= length(@custom_providers) %></p>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <p class="text-xs text-gray-500 uppercase tracking-wider">Configured</p>
          <p class="text-2xl font-bold text-emerald-400 mt-1"><%= Enum.count(@built_in, &(&1.key_source != :not_set)) + Enum.count(@custom_providers, &(&1.enabled)) %></p>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <p class="text-xs text-gray-500 uppercase tracking-wider">Total Models</p>
          <p class="text-2xl font-bold text-white mt-1"><%= Enum.sum(Enum.map(@built_in, &length(&1.models))) + Enum.sum(Enum.map(@custom_providers, &length(&1.models || []))) %></p>
        </div>
      </div>

      <%!-- Add/Edit Provider Form --%>
      <%= if @show_add_form do %>
        <div class="bg-gray-900 border border-emerald-500/30 rounded-xl overflow-hidden">
          <div class="px-6 py-4 bg-emerald-500/5 border-b border-gray-800">
            <h3 class="text-lg font-semibold text-white">
              <%= if @editing_provider, do: "Edit Provider", else: "Register Custom Provider" %>
            </h3>
            <p class="text-xs text-gray-400 mt-1">Any OpenAI-compatible API endpoint works</p>
          </div>
          <form phx-submit="save_provider" class="p-6 space-y-5">
            <div class="grid grid-cols-2 gap-5">
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1.5">Provider Name</label>
                <input type="text" name="provider[name]" value={@form_data["name"]} required
                  placeholder="e.g. Together AI, Groq, vLLM"
                  class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2.5 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500 placeholder-gray-600" />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1.5">Auth Header Type</label>
                <select name="provider[auth_header]" class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2.5 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500">
                  <option value="Bearer" selected={@form_data["auth_header"] == "Bearer"}>Bearer Token</option>
                  <option value="X-API-Key" selected={@form_data["auth_header"] == "X-API-Key"}>X-API-Key</option>
                  <option value="Api-Key" selected={@form_data["auth_header"] == "Api-Key"}>Api-Key</option>
                </select>
              </div>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1.5">API Endpoint URL</label>
              <input type="url" name="provider[base_url]" value={@form_data["base_url"]} required
                placeholder="https://api.provider.com/v1/chat/completions"
                class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2.5 text-white text-sm font-mono focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500 placeholder-gray-600" />
            </div>

            <div class="grid grid-cols-2 gap-5">
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1.5">API Key Variable Name</label>
                <input type="text" name="provider[api_key_env]" value={@form_data["api_key_env"]}
                  placeholder="e.g. TOGETHER_API_KEY"
                  class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2.5 text-white text-sm font-mono focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500 placeholder-gray-600" />
                <p class="text-xs text-gray-600 mt-1">Used to reference this key internally</p>
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1.5">API Key Value</label>
                <input type="password" name="provider[api_key_value]" value={@form_data["api_key_value"]}
                  placeholder="sk-..."
                  class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2.5 text-white text-sm font-mono focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500 placeholder-gray-600" />
                <p class="text-xs text-gray-600 mt-1">Stored securely in memory, not on disk</p>
              </div>
            </div>

            <div class="grid grid-cols-3 gap-5">
              <div class="col-span-2">
                <label class="block text-sm font-medium text-gray-300 mb-1.5">Models (comma-separated)</label>
                <input type="text" name="provider[models]" value={@form_data["models"]} required
                  placeholder="model-name-1, model-name-2"
                  class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2.5 text-white text-sm font-mono focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500 placeholder-gray-600" />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1.5">Max Tokens</label>
                <input type="number" name="provider[max_tokens]" value={@form_data["max_tokens"]}
                  class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2.5 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
              </div>
            </div>

            <div class="flex items-center gap-3 pt-2">
              <button type="submit" class="px-5 py-2.5 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg transition-colors">
                <%= if @editing_provider, do: "Update Provider", else: "Register Provider" %>
              </button>
              <button type="button" phx-click="toggle_add_form" class="px-5 py-2.5 bg-gray-700 hover:bg-gray-600 text-gray-300 text-sm font-medium rounded-lg transition-colors">
                Cancel
              </button>
            </div>
          </form>
        </div>
      <% end %>

      <%!-- Built-in Providers --%>
      <div>
        <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-4">Built-in Providers</h3>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <%= for provider <- @built_in do %>
            <div class="bg-gray-900 border border-gray-800 rounded-xl overflow-hidden">
              <%!-- Provider Header --%>
              <div class="p-5">
                <div class="flex items-start justify-between mb-3">
                  <div class="flex items-center gap-3">
                    <div class={"w-10 h-10 rounded-lg flex items-center justify-center #{provider.bg_color}"}>
                      <svg class={"w-5 h-5 #{provider.icon_color}"} fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904 9 18.75l-.813-2.846a4.5 4.5 0 0 0-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 0 0 3.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 0 0 3.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 0 0-3.09 3.09ZM18.259 8.715 18 9.75l-.259-1.035a3.375 3.375 0 0 0-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 0 0 2.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 0 0 2.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 0 0-2.456 2.456ZM16.894 20.567 16.5 21.75l-.394-1.183a2.25 2.25 0 0 0-1.423-1.423L13.5 18.75l1.183-.394a2.25 2.25 0 0 0 1.423-1.423l.394-1.183.394 1.183a2.25 2.25 0 0 0 1.423 1.423l1.183.394-1.183.394a2.25 2.25 0 0 0-1.423 1.423Z" />
                      </svg>
                    </div>
                    <div>
                      <h4 class="text-base font-semibold text-white"><%= provider.name %></h4>
                      <p class="text-xs text-gray-500"><%= provider.description %></p>
                    </div>
                  </div>
                  <span class={[
                    "px-2.5 py-1 rounded-full text-xs font-medium",
                    provider.key_source == :dashboard && "bg-emerald-500/20 text-emerald-400",
                    provider.key_source == :environment && "bg-cyan-500/20 text-cyan-400",
                    provider.key_source == :not_set && "bg-gray-700/50 text-gray-500"
                  ]}>
                    <%= case provider.key_source do %>
                      <% :dashboard -> %>Dashboard
                      <% :environment -> %>Env Var
                      <% :not_set -> %>Not Set
                    <% end %>
                  </span>
                </div>

                <%!-- API Key Section --%>
                <div class="bg-gray-800/50 rounded-lg p-3 mb-3">
                  <%= if @show_key_input == provider.id do %>
                    <form phx-submit="save_api_key" class="flex gap-2">
                      <input type="hidden" name="env_var" value={provider.env_var} />
                      <input type="password" name="api_key" required autofocus
                        placeholder="Paste your API key..."
                        class="flex-1 bg-gray-900 border border-gray-600 rounded-lg px-3 py-1.5 text-white text-xs font-mono focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500 placeholder-gray-600" />
                      <button type="submit" class="px-3 py-1.5 bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-medium rounded-lg transition-colors">
                        Save
                      </button>
                      <button type="button" phx-click="hide_key_input" class="px-3 py-1.5 bg-gray-700 hover:bg-gray-600 text-gray-300 text-xs rounded-lg transition-colors">
                        Cancel
                      </button>
                    </form>
                  <% else %>
                    <div class="flex items-center justify-between">
                      <div>
                        <span class="text-xs text-gray-500"><%= provider.env_var %></span>
                        <span class={["text-xs font-mono ml-2", if(provider.masked_key, do: "text-emerald-400", else: "text-gray-600")]}>
                          <%= provider.masked_key || "Not configured" %>
                        </span>
                      </div>
                      <div class="flex items-center gap-1.5">
                        <button phx-click="show_key_input" phx-value-provider={provider.id}
                          class="px-2.5 py-1 bg-gray-700 hover:bg-gray-600 text-gray-300 text-xs rounded-md transition-colors">
                          <%= if provider.masked_key, do: "Change", else: "Set Key" %>
                        </button>
                        <%= if provider.key_source == :dashboard do %>
                          <button phx-click="clear_api_key" phx-value-env_var={provider.env_var}
                            class="px-2.5 py-1 bg-gray-700 hover:bg-gray-600 text-red-400 text-xs rounded-md transition-colors">
                            Clear
                          </button>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>

                <%!-- Models --%>
                <div class="flex flex-wrap gap-1.5 mb-3">
                  <%= for model <- provider.models do %>
                    <span class="px-2 py-0.5 bg-gray-800 text-gray-400 rounded text-[11px] font-mono"><%= model %></span>
                  <% end %>
                </div>

                <%!-- Test Connection --%>
                <div class="flex items-center justify-between">
                  <button phx-click="test_connection" phx-value-provider={provider.id}
                    disabled={@testing == provider.id}
                    class="flex items-center gap-1.5 px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs font-medium rounded-lg transition-colors disabled:opacity-50">
                    <%= if @testing == provider.id do %>
                      <svg class="w-3.5 h-3.5 animate-spin" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99" />
                      </svg>
                      Testing...
                    <% else %>
                      <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M9.348 14.652a3.75 3.75 0 0 1 0-5.304m5.304 0a3.75 3.75 0 0 1 0 5.304m-7.425 2.121a6.75 6.75 0 0 1 0-9.546m9.546 0a6.75 6.75 0 0 1 0 9.546M5.106 18.894c-3.808-3.807-3.808-9.98 0-13.788m13.788 0c3.808 3.807 3.808 9.98 0 13.788M12 12h.008v.008H12V12Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Z" />
                      </svg>
                      Test Connection
                    <% end %>
                  </button>
                  <%= if @test_result && elem(@test_result, 0) == provider.id do %>
                    <span class={["text-xs font-medium", if(elem(elem(@test_result, 1), 0) == :ok, do: "text-emerald-400", else: "text-red-400")]}>
                      <%= elem(elem(@test_result, 1), 1) %>
                    </span>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Custom Providers (BYOP) --%>
      <div>
        <div class="flex items-center justify-between mb-4">
          <div>
            <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Custom Providers (BYOP)</h3>
            <p class="text-xs text-gray-600 mt-0.5">Bring Your Own Provider - any OpenAI-compatible endpoint</p>
          </div>
        </div>

        <%= if @custom_providers == [] do %>
          <div class="bg-gray-900/50 border border-dashed border-gray-700 rounded-xl p-10 text-center">
            <svg class="w-10 h-10 text-gray-700 mx-auto mb-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1">
              <path stroke-linecap="round" stroke-linejoin="round" d="M13.19 8.688a4.5 4.5 0 0 1 1.242 7.244l-4.5 4.5a4.5 4.5 0 0 1-6.364-6.364l1.757-1.757m13.35-.622 1.757-1.757a4.5 4.5 0 0 0-6.364-6.364l-4.5 4.5a4.5 4.5 0 0 0 1.242 7.244" />
            </svg>
            <p class="text-gray-500 font-medium">No custom providers yet</p>
            <p class="text-gray-600 text-sm mt-1">Connect to Together AI, Groq, Fireworks, vLLM, or any OpenAI-compatible endpoint</p>
            <button phx-click="toggle_add_form" class="mt-4 px-4 py-2 bg-gray-800 hover:bg-gray-700 text-gray-300 text-sm font-medium rounded-lg transition-colors">
              Add Your First Provider
            </button>
          </div>
        <% else %>
          <div class="space-y-3">
            <%= for provider <- @custom_providers do %>
              <div class={"bg-gray-900 border rounded-xl overflow-hidden #{if provider.enabled, do: "border-gray-800", else: "border-gray-800/50 opacity-60"}"}>
                <div class="p-5">
                  <div class="flex items-start justify-between mb-3">
                    <div class="flex items-center gap-3">
                      <div class="w-10 h-10 rounded-lg bg-emerald-500/10 flex items-center justify-center">
                        <svg class="w-5 h-5 text-emerald-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
                          <path stroke-linecap="round" stroke-linejoin="round" d="M13.19 8.688a4.5 4.5 0 0 1 1.242 7.244l-4.5 4.5a4.5 4.5 0 0 1-6.364-6.364l1.757-1.757m13.35-.622 1.757-1.757a4.5 4.5 0 0 0-6.364-6.364l-4.5 4.5a4.5 4.5 0 0 0 1.242 7.244" />
                        </svg>
                      </div>
                      <div>
                        <h4 class="text-base font-semibold text-white"><%= provider.name %></h4>
                        <p class="text-xs text-gray-500 font-mono"><%= provider.base_url %></p>
                      </div>
                    </div>
                    <div class="flex items-center gap-2">
                      <span class={[
                        "px-2 py-0.5 rounded-full text-xs font-medium",
                        provider.enabled && "bg-emerald-500/20 text-emerald-400",
                        !provider.enabled && "bg-red-500/20 text-red-400"
                      ]}>
                        <%= if provider.enabled, do: "Active", else: "Disabled" %>
                      </span>
                    </div>
                  </div>

                  <%!-- Key Info --%>
                  <div class="bg-gray-800/50 rounded-lg p-3 mb-3">
                    <div class="flex items-center justify-between">
                      <div class="flex items-center gap-3">
                        <span class="text-xs text-gray-500"><%= provider.api_key_env || "No key var" %></span>
                        <%= if provider.api_key_env do %>
                          <% has_key = ProviderConfig.has_api_key?(provider.api_key_env) %>
                          <span class={["text-xs", if(has_key, do: "text-emerald-400", else: "text-gray-600")]}>
                            <%= if has_key, do: ProviderConfig.mask_key(provider.api_key_env), else: "Not set" %>
                          </span>
                        <% end %>
                      </div>
                      <span class="text-xs text-gray-600">Max: <%= provider.max_tokens || 4096 %> tokens</span>
                    </div>
                  </div>

                  <%!-- Models --%>
                  <div class="flex flex-wrap gap-1.5 mb-3">
                    <%= for model <- (provider.models || []) do %>
                      <span class="px-2 py-0.5 bg-gray-800 text-gray-400 rounded text-[11px] font-mono"><%= model %></span>
                    <% end %>
                  </div>

                  <%!-- Actions --%>
                  <div class="flex items-center justify-between">
                    <div class="flex items-center gap-2">
                      <button phx-click="test_custom" phx-value-id={provider.id}
                        disabled={@testing == "custom_#{provider.id}"}
                        class="flex items-center gap-1.5 px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs font-medium rounded-lg transition-colors disabled:opacity-50">
                        <%= if @testing == "custom_#{provider.id}" do %>
                          <svg class="w-3 h-3 animate-spin" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99" />
                          </svg>
                          Testing...
                        <% else %>
                          Test
                        <% end %>
                      </button>
                      <button phx-click="edit_provider" phx-value-id={provider.id}
                        class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs font-medium rounded-lg transition-colors">
                        Edit
                      </button>
                      <button phx-click="toggle_provider" phx-value-id={provider.id}
                        class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs font-medium rounded-lg transition-colors">
                        <%= if provider.enabled, do: "Disable", else: "Enable" %>
                      </button>
                    </div>
                    <div class="flex items-center gap-2">
                      <%= if @test_result && elem(@test_result, 0) == "custom_#{provider.id}" do %>
                        <span class={["text-xs font-medium", if(elem(elem(@test_result, 1), 0) == :ok, do: "text-emerald-400", else: "text-red-400")]}>
                          <%= elem(elem(@test_result, 1), 1) %>
                        </span>
                      <% end %>
                      <button phx-click="remove_provider" phx-value-id={provider.id}
                        data-confirm="Remove #{provider.name}? This cannot be undone."
                        class="px-3 py-1.5 bg-red-900/30 hover:bg-red-800/40 text-red-400 text-xs font-medium rounded-lg transition-colors">
                        Remove
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Info Box --%>
      <div class="bg-gray-900/50 border border-gray-800 rounded-xl p-5">
        <h4 class="text-sm font-semibold text-white mb-2">How Provider Configuration Works</h4>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 text-xs text-gray-400">
          <div>
            <p class="text-emerald-400 font-medium mb-1">Dashboard Keys</p>
            <p>API keys set here are stored in memory and take priority over environment variables. They persist until the server restarts.</p>
          </div>
          <div>
            <p class="text-cyan-400 font-medium mb-1">Environment Variables</p>
            <p>Set via your deployment config for persistent keys. Dashboard keys override env vars when both exist.</p>
          </div>
          <div>
            <p class="text-purple-400 font-medium mb-1">Custom Providers</p>
            <p>Any OpenAI-compatible API works. Supports Together AI, Groq, Fireworks, Mistral, vLLM, llama.cpp, and more.</p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
