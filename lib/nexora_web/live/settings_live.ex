defmodule NexoraWeb.SettingsLive do
  use NexoraWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      page_title: "Settings",
      active_tab: :settings,
      anthropic_key: mask_key(System.get_env("ANTHROPIC_API_KEY")),
      openai_key: mask_key(System.get_env("OPENAI_API_KEY")),
      google_key: mask_key(System.get_env("GOOGLE_API_KEY")),
      ollama_url: System.get_env("OLLAMA_URL") || "http://localhost:11434"
    )}
  end

  defp mask_key(nil), do: "Not configured"
  defp mask_key(""), do: "Not configured"
  defp mask_key(key) when byte_size(key) > 8 do
    "#{String.slice(key, 0..3)}...#{String.slice(key, -4..-1)}"
  end
  defp mask_key(_), do: "****"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 max-w-3xl">
      <div>
        <h2 class="text-xl font-bold text-white">Settings</h2>
        <p class="text-sm text-gray-400 mt-1">Configure providers, gateway, and preferences</p>
      </div>

      <!-- API Keys -->
      <div class="bg-gray-900 border border-gray-800 rounded-xl">
        <div class="px-6 py-4 border-b border-gray-800">
          <h3 class="text-sm font-semibold text-white">API Keys</h3>
          <p class="text-xs text-gray-500 mt-1">Set via environment variables. Restart required after changes.</p>
        </div>
        <div class="p-6 space-y-4">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm text-white">Anthropic (Claude)</p>
              <p class="text-xs text-gray-500">ANTHROPIC_API_KEY</p>
            </div>
            <span class={"text-xs font-mono #{if @anthropic_key == "Not configured", do: "text-red-400", else: "text-emerald-400"}"}><%= @anthropic_key %></span>
          </div>
          <div class="border-t border-gray-800"></div>
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm text-white">OpenAI</p>
              <p class="text-xs text-gray-500">OPENAI_API_KEY</p>
            </div>
            <span class={"text-xs font-mono #{if @openai_key == "Not configured", do: "text-red-400", else: "text-emerald-400"}"}><%= @openai_key %></span>
          </div>
          <div class="border-t border-gray-800"></div>
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm text-white">Google (Gemini)</p>
              <p class="text-xs text-gray-500">GOOGLE_API_KEY</p>
            </div>
            <span class={"text-xs font-mono #{if @google_key == "Not configured", do: "text-red-400", else: "text-emerald-400"}"}><%= @google_key %></span>
          </div>
          <div class="border-t border-gray-800"></div>
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm text-white">Ollama</p>
              <p class="text-xs text-gray-500">OLLAMA_URL</p>
            </div>
            <span class="text-xs font-mono text-gray-400"><%= @ollama_url %></span>
          </div>
        </div>
      </div>

      <!-- About -->
      <div class="bg-gray-900 border border-gray-800 rounded-xl">
        <div class="px-6 py-4 border-b border-gray-800">
          <h3 class="text-sm font-semibold text-white">About Nexora</h3>
        </div>
        <div class="p-6 space-y-3 text-sm">
          <div class="flex justify-between">
            <span class="text-gray-500">Version</span>
            <span class="text-gray-300">0.1.0</span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-500">Framework</span>
            <span class="text-gray-300">Phoenix <%= Application.spec(:phoenix, :vsn) %></span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-500">Runtime</span>
            <span class="text-gray-300">Elixir <%= System.version() %> / OTP <%= :erlang.system_info(:otp_release) %></span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-500">License</span>
            <span class="text-gray-300">MIT</span>
          </div>
          <div class="pt-3 border-t border-gray-800">
            <p class="text-xs text-gray-500">
              Nexora is an open-source AI agent command center built with Elixir and Phoenix.
              Leveraging the BEAM VM for native concurrency, fault tolerance, and real-time capabilities.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
