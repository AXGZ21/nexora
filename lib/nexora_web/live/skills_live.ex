defmodule NexoraWeb.SkillsLive do
  use NexoraWeb, :live_view

  alias Nexora.Skills.SkillRegistry

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      page_title: "Skills",
      active_tab: :skills,
      installed: SkillRegistry.list_skills(),
      marketplace: marketplace_skills()
    )}
  end

  defp marketplace_skills do
    [
      %{id: "image-gen", name: "Image Generation", description: "Generate images using DALL-E, Stable Diffusion", version: "1.2.0", author: "Nexora", downloads: 12400},
      %{id: "pdf-reader", name: "PDF Reader", description: "Extract and analyze PDF documents", version: "2.0.1", author: "Community", downloads: 8200},
      %{id: "git-ops", name: "Git Operations", description: "Manage git repositories and automate workflows", version: "1.5.0", author: "Nexora", downloads: 15600},
      %{id: "slack-bot", name: "Slack Integration", description: "Send and receive Slack messages", version: "1.1.0", author: "Community", downloads: 6800},
      %{id: "db-query", name: "Database Query", description: "Query PostgreSQL, MySQL, and SQLite databases", version: "1.3.0", author: "Nexora", downloads: 9400},
      %{id: "email-send", name: "Email Sender", description: "Compose and send emails via SMTP", version: "1.0.0", author: "Community", downloads: 4200}
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h2 class="text-xl font-bold text-white">Skills</h2>
        <p class="text-sm text-gray-400 mt-1">Extend agent capabilities with installable skills</p>
      </div>

      <!-- Installed Skills -->
      <div class="bg-gray-900 border border-gray-800 rounded-xl">
        <div class="px-6 py-4 border-b border-gray-800 flex items-center justify-between">
          <h3 class="text-sm font-semibold text-white">Installed Skills</h3>
          <span class="text-xs text-gray-500"><%= length(@installed) %> installed</span>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-px bg-gray-800">
          <div :for={skill <- @installed} class="bg-gray-900 p-5">
            <div class="flex items-start justify-between">
              <div>
                <div class="flex items-center gap-2">
                  <p class="text-sm font-medium text-white"><%= skill.name %></p>
                  <span class="text-[10px] px-1.5 py-0.5 bg-emerald-500/20 text-emerald-400 rounded font-mono"><%= skill.version %></span>
                </div>
                <p class="text-xs text-gray-500 mt-1"><%= skill.description %></p>
              </div>
              <div class={[
                "w-2 h-2 rounded-full mt-1",
                skill.enabled && "bg-emerald-500",
                !skill.enabled && "bg-gray-500"
              ]} />
            </div>
          </div>
        </div>
      </div>

      <!-- Marketplace -->
      <div class="bg-gray-900 border border-gray-800 rounded-xl">
        <div class="px-6 py-4 border-b border-gray-800">
          <h3 class="text-sm font-semibold text-white">Marketplace</h3>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-px bg-gray-800">
          <div :for={skill <- @marketplace} class="bg-gray-900 p-5">
            <div class="flex items-start justify-between">
              <div>
                <p class="text-sm font-medium text-white"><%= skill.name %></p>
                <p class="text-xs text-gray-500 mt-1"><%= skill.description %></p>
                <div class="flex items-center gap-3 mt-3">
                  <span class="text-[10px] text-gray-600 font-mono">v<%= skill.version %></span>
                  <span class="text-[10px] text-gray-600"><%= format_downloads(skill.downloads) %> installs</span>
                </div>
              </div>
            </div>
            <button class="mt-3 w-full text-xs text-emerald-400 bg-emerald-500/10 hover:bg-emerald-500/20 py-1.5 rounded-lg transition-colors font-medium">
              Install
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_downloads(n) when n >= 1000, do: "#{Float.round(n / 1000, 1)}k"
  defp format_downloads(n), do: "#{n}"
end
