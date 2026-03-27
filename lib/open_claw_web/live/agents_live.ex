defmodule OpenClawWeb.AgentsLive do
  use OpenClawWeb, :live_view

  alias OpenClaw.Runtime.{AgentSupervisor, AgentProcess}
  alias OpenClaw.Runtime.LLMClient

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(OpenClaw.PubSub, "agents")
      :timer.send_interval(3000, self(), :refresh)
    end

    {:ok, assign(socket,
      page_title: "Agent Hub",
      active_tab: :agents,
      agents: AgentSupervisor.list_agents(),
      show_spawn: false,
      agent_name: "New Agent",
      agent_model: "claude-sonnet-4-6",
      agent_provider: "anthropic",
      providers: LLMClient.providers()
    )}
  end

  @impl true
  def handle_event("toggle_spawn", _params, socket) do
    {:noreply, assign(socket, show_spawn: !socket.assigns.show_spawn)}
  end

  def handle_event("spawn_agent", params, socket) do
    name = params["name"] || "New Agent"
    model = params["model"] || "claude-sonnet-4-6"
    provider = String.to_existing_atom(params["provider"] || "anthropic")

    case AgentSupervisor.spawn_agent(name: name, model: model, provider: provider) do
      {:ok, _id, _pid} ->
        {:noreply, socket
          |> assign(agents: AgentSupervisor.list_agents(), show_spawn: false)
          |> put_flash(:info, "Agent '#{name}' spawned successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to spawn agent: #{inspect(reason)}")}
    end
  end

  def handle_event("pause_agent", %{"id" => id}, socket) do
    AgentProcess.pause(id)
    {:noreply, assign(socket, agents: AgentSupervisor.list_agents())}
  end

  def handle_event("resume_agent", %{"id" => id}, socket) do
    AgentProcess.resume(id)
    {:noreply, assign(socket, agents: AgentSupervisor.list_agents())}
  end

  def handle_event("stop_agent", %{"id" => id}, socket) do
    AgentSupervisor.stop_agent(id)
    Process.sleep(100)
    {:noreply, assign(socket, agents: AgentSupervisor.list_agents())}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, agents: AgentSupervisor.list_agents())}
  end

  def handle_info({:agent_status, _id, _status, _state}, socket) do
    {:noreply, assign(socket, agents: AgentSupervisor.list_agents())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-xl font-bold text-white">Agent Hub</h2>
          <p class="text-sm text-gray-400 mt-1">Manage and monitor your AI agent processes</p>
        </div>
        <button phx-click="toggle_spawn" class="flex items-center gap-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium py-2.5 px-4 rounded-lg transition-colors">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
          </svg>
          Spawn Agent
        </button>
      </div>

      <!-- Spawn Form -->
      <div :if={@show_spawn} class="bg-gray-900 border border-gray-800 rounded-xl p-6">
        <h3 class="text-sm font-semibold text-white mb-4">Spawn New Agent</h3>
        <form phx-submit="spawn_agent" class="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div>
            <label class="block text-xs text-gray-500 mb-1">Name</label>
            <input type="text" name="name" value="New Agent" class="w-full bg-gray-800 border-gray-700 text-gray-200 text-sm rounded-lg focus:ring-emerald-500 focus:border-emerald-500 px-3 py-2" />
          </div>
          <div>
            <label class="block text-xs text-gray-500 mb-1">Provider</label>
            <select name="provider" class="w-full bg-gray-800 border-gray-700 text-gray-200 text-sm rounded-lg focus:ring-emerald-500 focus:border-emerald-500 px-3 py-2">
              <option value="anthropic">Anthropic</option>
              <option value="openai">OpenAI</option>
              <option value="google">Google</option>
              <option value="ollama">Ollama (Local)</option>
            </select>
          </div>
          <div>
            <label class="block text-xs text-gray-500 mb-1">Model</label>
            <input type="text" name="model" value="claude-sonnet-4-6" class="w-full bg-gray-800 border-gray-700 text-gray-200 text-sm rounded-lg focus:ring-emerald-500 focus:border-emerald-500 px-3 py-2" />
          </div>
          <div class="flex items-end">
            <button type="submit" class="w-full bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium py-2 px-4 rounded-lg transition-colors">
              Launch
            </button>
          </div>
        </form>
      </div>

      <!-- Agent Grid -->
      <div :if={@agents == []} class="bg-gray-900 border border-gray-800 rounded-xl p-12 text-center">
        <div class="w-20 h-20 mx-auto bg-gray-800 rounded-2xl flex items-center justify-center mb-4">
          <svg class="w-10 h-10 text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 3v1.5M4.5 8.25H3m18 0h-1.5M4.5 12H3m18 0h-1.5m-15 3.75H3m18 0h-1.5M8.25 19.5V21M12 3v1.5m0 15V21m3.75-18v1.5m0 15V21m-9-1.5h10.5a2.25 2.25 0 0 0 2.25-2.25V6.75a2.25 2.25 0 0 0-2.25-2.25H6.75A2.25 2.25 0 0 0 4.5 6.75v10.5a2.25 2.25 0 0 0 2.25 2.25Z" />
          </svg>
        </div>
        <p class="text-gray-400 text-lg font-medium">No agents running</p>
        <p class="text-gray-600 text-sm mt-2">Click "Spawn Agent" to create your first AI agent</p>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div :for={agent <- @agents} class="bg-gray-900 border border-gray-800 rounded-xl overflow-hidden">
          <!-- Agent Header -->
          <div class="px-5 py-4 border-b border-gray-800 flex items-center justify-between">
            <div class="flex items-center gap-3">
              <div class={[
                "w-3 h-3 rounded-full",
                agent.status == :running && "bg-emerald-500 animate-pulse",
                agent.status == :paused && "bg-amber-500",
                agent.status == :stopped && "bg-gray-500"
              ]} />
              <div>
                <p class="text-sm font-semibold text-white"><%= agent.name %></p>
                <p class="text-xs text-gray-500"><%= agent.id |> String.slice(0..7) %></p>
              </div>
            </div>
            <span class={[
              "text-[10px] font-medium px-2 py-0.5 rounded-full uppercase",
              agent.status == :running && "bg-emerald-500/20 text-emerald-400",
              agent.status == :paused && "bg-amber-500/20 text-amber-400",
              agent.status == :stopped && "bg-gray-500/20 text-gray-400"
            ]}>
              <%= agent.status %>
            </span>
          </div>

          <!-- Agent Info -->
          <div class="px-5 py-4 space-y-3">
            <div class="flex justify-between text-xs">
              <span class="text-gray-500">Model</span>
              <span class="text-gray-300 font-mono"><%= agent.model %></span>
            </div>
            <div class="flex justify-between text-xs">
              <span class="text-gray-500">Provider</span>
              <span class="text-gray-300"><%= agent.provider %></span>
            </div>
            <div class="flex justify-between text-xs">
              <span class="text-gray-500">Messages</span>
              <span class="text-gray-300"><%= agent.message_count %></span>
            </div>
            <div class="flex justify-between text-xs">
              <span class="text-gray-500">Tokens</span>
              <span class="text-gray-300"><%= agent.total_tokens %></span>
            </div>
            <div class="flex justify-between text-xs">
              <span class="text-gray-500">Cost</span>
              <span class="text-emerald-400 font-medium">$<%= Float.round(agent.total_cost, 4) %></span>
            </div>
          </div>

          <!-- Agent Actions -->
          <div class="px-5 py-3 border-t border-gray-800 flex gap-2">
            <button
              :if={agent.status == :running}
              phx-click="pause_agent"
              phx-value-id={agent.id}
              class="flex-1 text-xs text-amber-400 hover:text-amber-300 bg-amber-500/10 hover:bg-amber-500/20 py-1.5 rounded-lg transition-colors"
            >
              Pause
            </button>
            <button
              :if={agent.status == :paused}
              phx-click="resume_agent"
              phx-value-id={agent.id}
              class="flex-1 text-xs text-emerald-400 hover:text-emerald-300 bg-emerald-500/10 hover:bg-emerald-500/20 py-1.5 rounded-lg transition-colors"
            >
              Resume
            </button>
            <button
              phx-click="stop_agent"
              phx-value-id={agent.id}
              class="flex-1 text-xs text-red-400 hover:text-red-300 bg-red-500/10 hover:bg-red-500/20 py-1.5 rounded-lg transition-colors"
            >
              Stop
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
