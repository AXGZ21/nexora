defmodule OpenClawWeb.GovernanceLive do
  use OpenClawWeb, :live_view

  alias OpenClaw.Governance

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(OpenClaw.PubSub, "governance")
    end

    proposals = Governance.list()
    pending = Governance.list_pending()

    socket = socket
      |> assign(:active_tab, :governance)
      |> assign(:page_title, "Governance")
      |> assign(:proposals, proposals)
      |> assign(:pending_count, length(pending))
      |> assign(:show_form, false)
      |> assign(:selected_proposal, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("show_form", _params, socket) do
    {:noreply, assign(socket, :show_form, true)}
  end

  def handle_event("hide_form", _params, socket) do
    {:noreply, assign(socket, :show_form, false)}
  end

  def handle_event("create_proposal", %{"proposal" => params}, socket) do
    {approvals, _} = Integer.parse(params["required_approvals"] || "1")
    attrs = [
      title: params["title"],
      description: params["description"],
      type: String.to_existing_atom(params["type"]),
      proposer_id: "board",
      required_approvals: approvals
    ]

    case Governance.propose(attrs) do
      {:ok, _proposal} ->
        {:noreply, socket |> refresh_data() |> assign(:show_form, false) |> put_flash(:info, "Proposal submitted")}
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to create proposal")}
    end
  end

  def handle_event("select_proposal", %{"id" => id}, socket) do
    proposal = Governance.get(id)
    {:noreply, assign(socket, :selected_proposal, proposal)}
  end

  def handle_event("vote", %{"id" => id, "decision" => decision}, socket) do
    vote = String.to_existing_atom(decision)
    case Governance.vote(id, "board", vote, "Board decision") do
      {:ok, updated} ->
        {:noreply, socket |> refresh_data() |> assign(:selected_proposal, updated)}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Vote failed: #{inspect(reason)}")}
    end
  end

  def handle_event("cancel_proposal", %{"id" => id}, socket) do
    Governance.cancel(id)
    {:noreply, refresh_data(socket) |> assign(:selected_proposal, nil) |> put_flash(:info, "Proposal cancelled")}
  end

  @impl true
  def handle_info({:proposal_created, _}, socket), do: {:noreply, refresh_data(socket)}
  def handle_info({:proposal_approved, _}, socket), do: {:noreply, refresh_data(socket)}
  def handle_info({:proposal_rejected, _}, socket), do: {:noreply, refresh_data(socket)}
  def handle_info({:proposal_voted, _}, socket), do: {:noreply, refresh_data(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  defp refresh_data(socket) do
    proposals = Governance.list()
    pending = Governance.list_pending()
    socket |> assign(:proposals, proposals) |> assign(:pending_count, length(pending))
  end

  defp status_color(:pending), do: "bg-yellow-500/20 text-yellow-400"
  defp status_color(:approved), do: "bg-emerald-500/20 text-emerald-400"
  defp status_color(:rejected), do: "bg-red-500/20 text-red-400"
  defp status_color(:expired), do: "bg-gray-700 text-gray-500"
  defp status_color(_), do: "bg-gray-700 text-gray-400"

  defp type_color(:budget), do: "bg-green-500/20 text-green-400"
  defp type_color(:strategy), do: "bg-blue-500/20 text-blue-400"
  defp type_color(:hiring), do: "bg-purple-500/20 text-purple-400"
  defp type_color(:tool_access), do: "bg-cyan-500/20 text-cyan-400"
  defp type_color(:deployment), do: "bg-orange-500/20 text-orange-400"
  defp type_color(:custom), do: "bg-gray-700 text-gray-300"
  defp type_color(_), do: "bg-gray-700 text-gray-400"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-2xl font-bold text-white">Governance</h2>
          <p class="text-sm text-gray-400 mt-1">Board-level approval workflows and decision tracking</p>
        </div>
        <div class="flex items-center gap-3">
          <%= if @pending_count > 0 do %>
            <span class="px-3 py-1 bg-yellow-500/20 text-yellow-400 rounded-lg text-sm font-medium">
              <%= @pending_count %> pending
            </span>
          <% end %>
          <button phx-click="show_form" class="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg transition-colors">
            + New Proposal
          </button>
        </div>
      </div>

      <!-- Create Proposal Form -->
      <%= if @show_form do %>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h3 class="text-lg font-semibold text-white mb-4">Submit Proposal</h3>
          <form phx-submit="create_proposal" class="space-y-4">
            <div class="grid grid-cols-3 gap-4">
              <div class="col-span-2">
                <label class="block text-sm font-medium text-gray-300 mb-1">Title</label>
                <input type="text" name="proposal[title]" required class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Type</label>
                <select name="proposal[type]" class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500">
                  <option value="budget">Budget</option>
                  <option value="strategy">Strategy</option>
                  <option value="hiring">Hiring</option>
                  <option value="tool_access">Tool Access</option>
                  <option value="deployment">Deployment</option>
                  <option value="custom">Custom</option>
                </select>
              </div>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">Description</label>
              <textarea name="proposal[description]" rows="3" class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500"></textarea>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">Required Approvals</label>
              <input type="number" name="proposal[required_approvals]" value="1" min="1" max="10" class="w-32 bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
            </div>
            <div class="flex gap-3">
              <button type="submit" class="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg">Submit</button>
              <button type="button" phx-click="hide_form" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-gray-300 text-sm font-medium rounded-lg">Cancel</button>
            </div>
          </form>
        </div>
      <% end %>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Proposals List -->
        <div class="space-y-3">
          <h3 class="text-sm font-semibold text-gray-400 uppercase tracking-wider">All Proposals</h3>
          <%= if @proposals == [] do %>
            <div class="bg-gray-900/50 border border-dashed border-gray-700 rounded-xl p-8 text-center">
              <p class="text-gray-500">No proposals yet.</p>
            </div>
          <% else %>
            <%= for proposal <- @proposals do %>
              <div class={"bg-gray-900 border rounded-lg p-4 cursor-pointer hover:border-gray-700 transition-colors #{if @selected_proposal && @selected_proposal.id == proposal.id, do: "border-emerald-700", else: "border-gray-800"}"}
                   phx-click="select_proposal" phx-value-id={proposal.id}>
                <div class="flex items-center justify-between mb-1">
                  <div class="flex items-center gap-2">
                    <span class="text-xs font-mono text-emerald-400"><%= proposal.id %></span>
                    <span class={["px-2 py-0.5 rounded text-xs font-medium", type_color(proposal.type)]}><%= proposal.type %></span>
                  </div>
                  <span class={["px-2 py-0.5 rounded text-xs font-medium", status_color(proposal.status)]}>
                    <%= proposal.status %>
                  </span>
                </div>
                <h4 class="text-sm font-medium text-white"><%= proposal.title %></h4>
                <div class="flex items-center gap-3 mt-2 text-xs text-gray-500">
                  <span><%= length(proposal.votes) %> / <%= proposal.required_approvals %> votes</span>
                  <span>by <%= proposal.proposer_id %></span>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

        <!-- Proposal Detail -->
        <div>
          <%= if @selected_proposal do %>
            <div class="bg-gray-900 border border-gray-800 rounded-xl p-5">
              <div class="flex items-center justify-between mb-3">
                <div>
                  <div class="flex items-center gap-2 mb-1">
                    <span class="text-xs font-mono text-emerald-400"><%= @selected_proposal.id %></span>
                    <span class={["px-2 py-0.5 rounded text-xs font-medium", type_color(@selected_proposal.type)]}><%= @selected_proposal.type %></span>
                    <span class={["px-2 py-0.5 rounded text-xs font-medium", status_color(@selected_proposal.status)]}><%= @selected_proposal.status %></span>
                  </div>
                  <h3 class="text-lg font-semibold text-white"><%= @selected_proposal.title %></h3>
                </div>
              </div>

              <%= if @selected_proposal.description && @selected_proposal.description != "" do %>
                <p class="text-sm text-gray-400 mb-4"><%= @selected_proposal.description %></p>
              <% end %>

              <!-- Vote Progress -->
              <div class="mb-4">
                <div class="flex items-center justify-between text-xs text-gray-400 mb-1">
                  <span>Votes: <%= length(@selected_proposal.votes) %> / <%= @selected_proposal.required_approvals %> required</span>
                </div>
                <div class="h-2 bg-gray-800 rounded-full overflow-hidden">
                  <% approve_count = Enum.count(@selected_proposal.votes, &(&1.vote == :approve)) %>
                  <% pct = if @selected_proposal.required_approvals > 0, do: min(100, approve_count / @selected_proposal.required_approvals * 100), else: 0 %>
                  <div class="h-full bg-emerald-500 rounded-full transition-all" style={"width: #{pct}%"}></div>
                </div>
              </div>

              <!-- Votes -->
              <%= if @selected_proposal.votes != [] do %>
                <div class="space-y-2 mb-4">
                  <h4 class="text-xs font-semibold text-gray-400 uppercase">Votes Cast</h4>
                  <%= for vote <- @selected_proposal.votes do %>
                    <div class="flex items-center gap-2 text-sm">
                      <span class={if vote.vote == :approve, do: "text-emerald-400", else: "text-red-400"}>
                        <%= if vote.vote == :approve, do: "[Y]", else: "[N]" %>
                      </span>
                      <span class="text-gray-300"><%= vote.voter_id %></span>
                      <%= if vote.reason do %>
                        <span class="text-gray-600">- <%= vote.reason %></span>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <!-- Actions -->
              <%= if @selected_proposal.status == :pending do %>
                <div class="flex gap-2 pt-3 border-t border-gray-800">
                  <button phx-click="vote" phx-value-id={@selected_proposal.id} phx-value-decision="approve"
                    class="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg transition-colors">
                    Approve
                  </button>
                  <button phx-click="vote" phx-value-id={@selected_proposal.id} phx-value-decision="reject"
                    class="px-4 py-2 bg-red-900/50 hover:bg-red-800/50 text-red-400 text-sm font-medium rounded-lg transition-colors">
                    Reject
                  </button>
                  <button phx-click="cancel_proposal" phx-value-id={@selected_proposal.id}
                    class="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-gray-300 text-sm font-medium rounded-lg transition-colors ml-auto">
                    Cancel
                  </button>
                </div>
              <% end %>
            </div>
          <% else %>
            <div class="bg-gray-900/50 border border-dashed border-gray-700 rounded-xl p-12 text-center">
              <p class="text-gray-500">Select a proposal to view details</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
