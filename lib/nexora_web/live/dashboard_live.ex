defmodule NexoraWeb.DashboardLive do
  use NexoraWeb, :live_view

  alias Nexora.Runtime.AgentSupervisor
  alias Nexora.Billing.CostTracker

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Nexora.PubSub, "agents")
      Phoenix.PubSub.subscribe(Nexora.PubSub, "costs")
      :timer.send_interval(5000, self(), :refresh)
    end

    {:ok, assign_stats(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign_stats(socket)}
  end

  def handle_info({:agent_status, _id, _status, _state}, socket) do
    {:noreply, assign_stats(socket)}
  end

  def handle_info({:cost_entry, _entry}, socket) do
    {:noreply, assign_stats(socket)}
  end

  defp assign_stats(socket) do
    agents = AgentSupervisor.list_agents()
    running = Enum.count(agents, &(&1.status == :running))
    paused = Enum.count(agents, &(&1.status == :paused))

    assign(socket,
      page_title: "Dashboard",
      active_tab: :dashboard,
      total_agents: length(agents),
      running_agents: running,
      paused_agents: paused,
      total_cost: CostTracker.get_total_cost(),
      total_tokens: CostTracker.get_total_tokens(),
      recent_agents: Enum.take(agents, 5),
      cost_by_provider: CostTracker.get_cost_by_provider(),
      uptime: System.system_time(:second) - System.convert_time_unit(System.monotonic_time(), :native, :second)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Stats Grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <.stat_card title="Active Agents" value={@running_agents} subtitle={"#{@total_agents} total"} color="emerald" icon="agents" />
        <.stat_card title="Total Tokens" value={format_number(@total_tokens)} subtitle="across all agents" color="blue" icon="tokens" />
        <.stat_card title="Total Cost" value={"$#{Float.round(@total_cost, 4)}"} subtitle="current session" color="amber" icon="cost" />
        <.stat_card title="System Status" value="Online" subtitle="BEAM OTP supervised" color="green" icon="status" />
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Agent Activity -->
        <div class="lg:col-span-2 bg-gray-900 border border-gray-800 rounded-xl">
          <div class="px-6 py-4 border-b border-gray-800 flex items-center justify-between">
            <h2 class="text-sm font-semibold text-white">Agent Activity</h2>
            <.link navigate={~p"/agents"} class="text-xs text-emerald-400 hover:text-emerald-300">
              View All &rarr;
            </.link>
          </div>
          <div class="p-6">
            <div :if={@recent_agents == []} class="text-center py-12">
              <div class="w-16 h-16 mx-auto bg-gray-800 rounded-full flex items-center justify-center mb-4">
                <svg class="w-8 h-8 text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 3v1.5M4.5 8.25H3m18 0h-1.5M4.5 12H3m18 0h-1.5m-15 3.75H3m18 0h-1.5M8.25 19.5V21M12 3v1.5m0 15V21m3.75-18v1.5m0 15V21m-9-1.5h10.5a2.25 2.25 0 0 0 2.25-2.25V6.75a2.25 2.25 0 0 0-2.25-2.25H6.75A2.25 2.25 0 0 0 4.5 6.75v10.5a2.25 2.25 0 0 0 2.25 2.25Z" />
                </svg>
              </div>
              <p class="text-gray-400 text-sm">No agents running</p>
              <p class="text-gray-600 text-xs mt-1">Go to Agent Hub to spawn your first agent</p>
            </div>
            <div :if={@recent_agents != []} class="space-y-3">
              <div :for={agent <- @recent_agents} class="flex items-center justify-between p-3 bg-gray-800/50 rounded-lg">
                <div class="flex items-center gap-3">
                  <div class={[
                    "w-2.5 h-2.5 rounded-full",
                    agent.status == :running && "bg-emerald-500 animate-pulse",
                    agent.status == :paused && "bg-amber-500",
                    agent.status == :stopped && "bg-gray-500"
                  ]} />
                  <div>
                    <p class="text-sm font-medium text-white"><%= agent.name %></p>
                    <p class="text-xs text-gray-500"><%= agent.model %></p>
                  </div>
                </div>
                <div class="text-right">
                  <p class="text-xs text-gray-400"><%= agent.message_count %> messages</p>
                  <p class="text-xs text-gray-600">$<%= Float.round(agent.total_cost, 4) %></p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Quick Actions & System Info -->
        <div class="space-y-6">
          <!-- Quick Actions -->
          <div class="bg-gray-900 border border-gray-800 rounded-xl">
            <div class="px-6 py-4 border-b border-gray-800">
              <h2 class="text-sm font-semibold text-white">Quick Actions</h2>
            </div>
            <div class="p-4 space-y-2">
              <.link navigate={~p"/agents"} class="flex items-center gap-3 p-3 rounded-lg bg-gray-800/50 hover:bg-gray-800 transition-colors group">
                <div class="w-8 h-8 bg-emerald-500/20 rounded-lg flex items-center justify-center">
                  <svg class="w-4 h-4 text-emerald-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                  </svg>
                </div>
                <span class="text-sm text-gray-300 group-hover:text-white">Spawn New Agent</span>
              </.link>
              <.link navigate={~p"/chat"} class="flex items-center gap-3 p-3 rounded-lg bg-gray-800/50 hover:bg-gray-800 transition-colors group">
                <div class="w-8 h-8 bg-blue-500/20 rounded-lg flex items-center justify-center">
                  <svg class="w-4 h-4 text-blue-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M7.5 8.25h9m-9 3H12m-9.75 1.51c0 1.6 1.123 2.994 2.707 3.227 1.087.16 2.185.283 3.293.369V21l4.076-4.076a1.526 1.526 0 0 1 1.037-.443 48.282 48.282 0 0 0 5.68-.494c1.584-.233 2.707-1.626 2.707-3.228V6.741c0-1.602-1.123-2.995-2.707-3.228A48.394 48.394 0 0 0 12 3c-2.392 0-4.744.175-7.043.513C3.373 3.746 2.25 5.14 2.25 6.741v6.018Z" />
                  </svg>
                </div>
                <span class="text-sm text-gray-300 group-hover:text-white">Open Chat</span>
              </.link>
              <.link navigate={~p"/terminal"} class="flex items-center gap-3 p-3 rounded-lg bg-gray-800/50 hover:bg-gray-800 transition-colors group">
                <div class="w-8 h-8 bg-purple-500/20 rounded-lg flex items-center justify-center">
                  <svg class="w-4 h-4 text-purple-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m6.75 7.5 3 2.25-3 2.25m4.5 0h3m-9 8.25h13.5A2.25 2.25 0 0 0 21 18V6a2.25 2.25 0 0 0-2.25-2.25H5.25A2.25 2.25 0 0 0 3 6v12a2.25 2.25 0 0 0 2.25 2.25Z" />
                  </svg>
                </div>
                <span class="text-sm text-gray-300 group-hover:text-white">Open Terminal</span>
              </.link>
            </div>
          </div>

          <!-- System Info -->
          <div class="bg-gray-900 border border-gray-800 rounded-xl">
            <div class="px-6 py-4 border-b border-gray-800">
              <h2 class="text-sm font-semibold text-white">System Info</h2>
            </div>
            <div class="p-4 space-y-3 text-xs">
              <div class="flex justify-between">
                <span class="text-gray-500">Runtime</span>
                <span class="text-gray-300">Erlang/OTP <%= :erlang.system_info(:otp_release) %></span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-500">Elixir</span>
                <span class="text-gray-300"><%= System.version() %></span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-500">Phoenix</span>
                <span class="text-gray-300"><%= Application.spec(:phoenix, :vsn) %></span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-500">Schedulers</span>
                <span class="text-gray-300"><%= :erlang.system_info(:schedulers_online) %></span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-500">Processes</span>
                <span class="text-gray-300"><%= :erlang.system_info(:process_count) %></span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-500">Memory</span>
                <span class="text-gray-300"><%= Float.round(:erlang.memory(:total) / 1_048_576, 1) %> MB</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Components ---

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-gray-900 border border-gray-800 rounded-xl p-5">
      <div class="flex items-center justify-between mb-3">
        <span class="text-xs font-medium text-gray-500 uppercase tracking-wider"><%= @title %></span>
        <div class={[
          "w-8 h-8 rounded-lg flex items-center justify-center",
          @color == "emerald" && "bg-emerald-500/20",
          @color == "blue" && "bg-blue-500/20",
          @color == "amber" && "bg-amber-500/20",
          @color == "green" && "bg-green-500/20"
        ]}>
          <div class={[
            "w-2 h-2 rounded-full",
            @color == "emerald" && "bg-emerald-500",
            @color == "blue" && "bg-blue-500",
            @color == "amber" && "bg-amber-500",
            @color == "green" && "bg-green-500 animate-pulse"
          ]} />
        </div>
      </div>
      <p class="text-2xl font-bold text-white"><%= @value %></p>
      <p class="text-xs text-gray-500 mt-1"><%= @subtitle %></p>
    </div>
    """
  end

  defp format_number(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_number(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_number(n), do: "#{n}"
end
