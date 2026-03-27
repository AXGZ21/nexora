defmodule OpenClawWeb.ProvidersLive do
  use OpenClawWeb, :live_view

  alias OpenClaw.Runtime.CustomProvider

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(OpenClaw.PubSub, "providers")
    end

    providers = CustomProvider.list()
    built_in = [
      %{id: "anthropic", name: "Anthropic", status: env_status("ANTHROPIC_API_KEY"), models: ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5"]},
      %{id: "openai", name: "OpenAI", status: env_status("OPENAI_API_KEY"), models: ["gpt-4.1", "gpt-4.1-mini", "o3", "o4-mini"]},
      %{id: "google", name: "Google AI", status: env_status("GOOGLE_API_KEY"), models: ["gemini-2.0-flash"]},
      %{id: "ollama", name: "Ollama (Local)", status: :local, models: ["llama3.1", "codellama", "mistral"]}
    ]

    socket = socket
      |> assign(:active_tab, :providers)
      |> assign(:page_title, "Providers")
      |> assign(:built_in, built_in)
      |> assign(:custom_providers, providers)
      |> assign(:show_form, false)
      |> assign(:form_data, %{name: "", base_url: "", api_key_env: "", models: "", default_model: ""})

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_form", _params, socket) do
    {:noreply, assign(socket, :show_form, !socket.assigns.show_form)}
  end

  def handle_event("save_provider", %{"provider" => params}, socket) do
    models = params["models"] |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    config = [
      name: params["name"],
      base_url: params["base_url"],
      api_key_env: params["api_key_env"],
      models: models,
      default_model: List.first(models),
      request_format: :openai
    ]

    case CustomProvider.register(config) do
      {:ok, _provider} ->
        socket = socket
          |> assign(:custom_providers, CustomProvider.list())
          |> assign(:show_form, false)
          |> put_flash(:info, "Provider registered successfully")
        {:noreply, socket}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
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

  @impl true
  def handle_info({:provider_registered, _}, socket) do
    {:noreply, assign(socket, :custom_providers, CustomProvider.list())}
  end
  def handle_info({:provider_unregistered, _}, socket) do
    {:noreply, assign(socket, :custom_providers, CustomProvider.list())}
  end
  def handle_info(_, socket), do: {:noreply, socket}

  defp env_status(key) do
    case System.get_env(key) do
      nil -> :not_configured
      "" -> :not_configured
      _ -> :configured
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-2xl font-bold text-white">LLM Providers</h2>
          <p class="text-sm text-gray-400 mt-1">Manage built-in and custom model providers</p>
        </div>
        <button phx-click="toggle_form" class="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg transition-colors">
          + Add Custom Provider
        </button>
      </div>

      <!-- Add Provider Form -->
      <%= if @show_form do %>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h3 class="text-lg font-semibold text-white mb-4">Register Custom Provider</h3>
          <form phx-submit="save_provider" class="space-y-4">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Provider Name</label>
                <input type="text" name="provider[name]" required placeholder="e.g. Together AI"
                  class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">API Key Env Variable</label>
                <input type="text" name="provider[api_key_env]" required placeholder="e.g. TOGETHER_API_KEY"
                  class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
              </div>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">Base URL (OpenAI-compatible endpoint)</label>
              <input type="url" name="provider[base_url]" required placeholder="https://api.provider.com/v1/chat/completions"
                class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">Models (comma-separated)</label>
              <input type="text" name="provider[models]" required placeholder="model-1, model-2, model-3"
                class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
            </div>
            <div class="flex gap-3">
              <button type="submit" class="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg transition-colors">
                Register Provider
              </button>
              <button type="button" phx-click="toggle_form" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-gray-300 text-sm font-medium rounded-lg transition-colors">
                Cancel
              </button>
            </div>
          </form>
        </div>
      <% end %>

      <!-- Built-in Providers -->
      <div>
        <h3 class="text-sm font-semibold text-gray-400 uppercase tracking-wider mb-3">Built-in Providers</h3>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <%= for provider <- @built_in do %>
            <div class="bg-gray-900 border border-gray-800 rounded-xl p-5">
              <div class="flex items-center justify-between mb-3">
                <h4 class="text-lg font-semibold text-white"><%= provider.name %></h4>
                <span class={[
                  "px-2 py-1 rounded-full text-xs font-medium",
                  provider.status == :configured && "bg-emerald-500/20 text-emerald-400",
                  provider.status == :not_configured && "bg-gray-700 text-gray-400",
                  provider.status == :local && "bg-blue-500/20 text-blue-400"
                ]}>
                  <%= case provider.status do %>
                    <% :configured -> %>Configured
                    <% :not_configured -> %>Not Configured
                    <% :local -> %>Local
                  <% end %>
                </span>
              </div>
              <div class="flex flex-wrap gap-1.5">
                <%= for model <- provider.models do %>
                  <span class="px-2 py-0.5 bg-gray-800 text-gray-300 rounded text-xs font-mono"><%= model %></span>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Custom Providers -->
      <div>
        <h3 class="text-sm font-semibold text-gray-400 uppercase tracking-wider mb-3">Custom Providers (BYOP)</h3>
        <%= if @custom_providers == [] do %>
          <div class="bg-gray-900/50 border border-dashed border-gray-700 rounded-xl p-8 text-center">
            <p class="text-gray-500">No custom providers registered yet.</p>
            <p class="text-gray-600 text-sm mt-1">Add any OpenAI-compatible endpoint to get started.</p>
          </div>
        <% else %>
          <div class="space-y-3">
            <%= for provider <- @custom_providers do %>
              <div class="bg-gray-900 border border-gray-800 rounded-xl p-5">
                <div class="flex items-center justify-between mb-2">
                  <div class="flex items-center gap-3">
                    <h4 class="text-lg font-semibold text-white"><%= provider.name %></h4>
                    <span class={[
                      "px-2 py-0.5 rounded-full text-xs font-medium",
                      provider.enabled && "bg-emerald-500/20 text-emerald-400",
                      !provider.enabled && "bg-red-500/20 text-red-400"
                    ]}>
                      <%= if provider.enabled, do: "Active", else: "Disabled" %>
                    </span>
                  </div>
                  <div class="flex items-center gap-2">
                    <button phx-click="toggle_provider" phx-value-id={provider.id}
                      class="px-3 py-1 bg-gray-700 hover:bg-gray-600 text-gray-300 text-xs rounded-lg transition-colors">
                      <%= if provider.enabled, do: "Disable", else: "Enable" %>
                    </button>
                    <button phx-click="remove_provider" phx-value-id={provider.id}
                      data-confirm="Remove this provider?"
                      class="px-3 py-1 bg-red-900/50 hover:bg-red-800/50 text-red-400 text-xs rounded-lg transition-colors">
                      Remove
                    </button>
                  </div>
                </div>
                <p class="text-xs text-gray-500 font-mono mb-2"><%= provider.base_url %></p>
                <div class="flex flex-wrap gap-1.5">
                  <%= for model <- (provider.models || []) do %>
                    <span class="px-2 py-0.5 bg-gray-800 text-gray-300 rounded text-xs font-mono"><%= model %></span>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
