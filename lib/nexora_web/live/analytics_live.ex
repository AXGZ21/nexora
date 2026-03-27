defmodule NexoraWeb.AnalyticsLive do
  use NexoraWeb, :live_view

  alias Nexora.Billing.CostTracker

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Nexora.PubSub, "costs")
      :timer.send_interval(10_000, self(), :refresh)
    end

    {:ok, assign_data(socket)}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, assign_data(socket)}
  def handle_info({:cost_entry, _}, socket), do: {:noreply, assign_data(socket)}

  defp assign_data(socket) do
    assign(socket,
      page_title: "Cost Analytics",
      active_tab: :analytics,
      total_cost: CostTracker.get_total_cost(),
      total_tokens: CostTracker.get_total_tokens(),
      by_provider: CostTracker.get_cost_by_provider(),
      by_agent: CostTracker.get_cost_by_agent(),
      daily: CostTracker.get_daily_costs(7),
      entries: CostTracker.get_entries() |> Enum.take(20)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Summary Cards -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-5">
          <p class="text-xs text-gray-500 uppercase tracking-wider">Total Spend</p>
          <p class="text-3xl font-bold text-white mt-2">$<%= Float.round(@total_cost, 4) %></p>
          <p class="text-xs text-gray-500 mt-1">Current session</p>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-5">
          <p class="text-xs text-gray-500 uppercase tracking-wider">Total Tokens</p>
          <p class="text-3xl font-bold text-white mt-2"><%= format_number(@total_tokens) %></p>
          <p class="text-xs text-gray-500 mt-1">Input + Output</p>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-5">
          <p class="text-xs text-gray-500 uppercase tracking-wider">Avg Cost / Request</p>
          <p class="text-3xl font-bold text-white mt-2">
            $<%= if length(@entries) > 0, do: Float.round(@total_cost / length(@entries), 6), else: "0.00" %>
          </p>
          <p class="text-xs text-gray-500 mt-1"><%= length(@entries) %> total requests</p>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- By Provider -->
        <div class="bg-gray-900 border border-gray-800 rounded-xl">
          <div class="px-6 py-4 border-b border-gray-800">
            <h2 class="text-sm font-semibold text-white">Cost by Provider</h2>
          </div>
          <div class="p-6">
            <div :if={@by_provider == []} class="text-center py-8 text-gray-500 text-sm">
              No cost data yet
            </div>
            <div :if={@by_provider != []} class="space-y-4">
              <div :for={p <- @by_provider} class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <div class={[
                    "w-3 h-3 rounded-full",
                    p.provider == :anthropic && "bg-orange-500",
                    p.provider == :openai && "bg-green-500",
                    p.provider == :google && "bg-blue-500",
                    p.provider == :ollama && "bg-purple-500"
                  ]} />
                  <div>
                    <p class="text-sm text-white capitalize"><%= p.provider %></p>
                    <p class="text-xs text-gray-500"><%= p.requests %> requests</p>
                  </div>
                </div>
                <div class="text-right">
                  <p class="text-sm font-medium text-white">$<%= Float.round(p.cost, 4) %></p>
                  <p class="text-xs text-gray-500"><%= format_number(p.tokens) %> tokens</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- By Agent -->
        <div class="bg-gray-900 border border-gray-800 rounded-xl">
          <div class="px-6 py-4 border-b border-gray-800">
            <h2 class="text-sm font-semibold text-white">Cost by Agent</h2>
          </div>
          <div class="p-6">
            <div :if={@by_agent == []} class="text-center py-8 text-gray-500 text-sm">
              No cost data yet
            </div>
            <div :if={@by_agent != []} class="space-y-4">
              <div :for={a <- @by_agent} class="flex items-center justify-between">
                <div>
                  <p class="text-sm text-white font-mono"><%= String.slice(a.agent_id, 0..11) %></p>
                  <p class="text-xs text-gray-500"><%= a.requests %> requests</p>
                </div>
                <div class="text-right">
                  <p class="text-sm font-medium text-white">$<%= Float.round(a.cost, 4) %></p>
                  <p class="text-xs text-gray-500"><%= format_number(a.tokens) %> tokens</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Recent Activity -->
      <div class="bg-gray-900 border border-gray-800 rounded-xl">
        <div class="px-6 py-4 border-b border-gray-800">
          <h2 class="text-sm font-semibold text-white">Recent Requests</h2>
        </div>
        <div class="overflow-x-auto">
          <table :if={@entries != []} class="w-full">
            <thead>
              <tr class="text-xs text-gray-500 uppercase border-b border-gray-800">
                <th class="text-left px-6 py-3 font-medium">Time</th>
                <th class="text-left px-6 py-3 font-medium">Agent</th>
                <th class="text-left px-6 py-3 font-medium">Provider</th>
                <th class="text-left px-6 py-3 font-medium">Model</th>
                <th class="text-right px-6 py-3 font-medium">Tokens</th>
                <th class="text-right px-6 py-3 font-medium">Cost</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={entry <- @entries} class="border-b border-gray-800/50 text-sm">
                <td class="px-6 py-3 text-gray-400 font-mono text-xs">
                  <%= Calendar.strftime(entry.timestamp, "%H:%M:%S") %>
                </td>
                <td class="px-6 py-3 text-gray-300 font-mono text-xs">
                  <%= String.slice(to_string(entry.agent_id), 0..7) %>
                </td>
                <td class="px-6 py-3 text-gray-300 capitalize"><%= entry.provider %></td>
                <td class="px-6 py-3 text-gray-400 font-mono text-xs"><%= entry.model %></td>
                <td class="px-6 py-3 text-gray-300 text-right"><%= entry.tokens %></td>
                <td class="px-6 py-3 text-emerald-400 text-right font-medium">$<%= Float.round(entry.cost || 0.0, 6) %></td>
              </tr>
            </tbody>
          </table>
          <div :if={@entries == []} class="p-12 text-center text-gray-500 text-sm">
            No requests recorded yet. Start chatting with an agent to see cost data.
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_number(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_number(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_number(n), do: "#{n}"
end
