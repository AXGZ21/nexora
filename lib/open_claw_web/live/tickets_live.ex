defmodule OpenClawWeb.TicketsLive do
  use OpenClawWeb, :live_view

  alias OpenClaw.Tickets.TicketSystem

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(OpenClaw.PubSub, "tickets")
    end

    tickets = TicketSystem.list()

    socket = socket
      |> assign(:active_tab, :tickets)
      |> assign(:page_title, "Tickets")
      |> assign(:tickets, tickets)
      |> assign(:filter, :all)
      |> assign(:show_form, false)
      |> assign(:selected_ticket, nil)
      |> assign(:new_message, "")

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    filter = if status == "all", do: :all, else: String.to_existing_atom(status)
    tickets = if filter == :all, do: TicketSystem.list(), else: TicketSystem.list_by_status(filter)
    {:noreply, assign(socket, filter: filter, tickets: tickets)}
  end

  def handle_event("show_form", _params, socket) do
    {:noreply, assign(socket, :show_form, true)}
  end

  def handle_event("hide_form", _params, socket) do
    {:noreply, assign(socket, :show_form, false)}
  end

  def handle_event("create_ticket", %{"ticket" => params}, socket) do
    attrs = [
      title: params["title"],
      description: params["description"],
      priority: String.to_existing_atom(params["priority"]),
      labels: params["labels"] |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    ]

    case TicketSystem.create(attrs) do
      {:ok, _ticket} ->
        {:noreply, socket |> refresh_data() |> assign(:show_form, false) |> put_flash(:info, "Ticket created")}
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to create ticket")}
    end
  end

  def handle_event("select_ticket", %{"id" => id}, socket) do
    ticket = TicketSystem.get(id)
    {:noreply, assign(socket, :selected_ticket, ticket)}
  end

  def handle_event("change_status", %{"id" => id, "status" => status}, socket) do
    TicketSystem.change_status(id, String.to_existing_atom(status))
    ticket = TicketSystem.get(id)
    {:noreply, socket |> refresh_data() |> assign(:selected_ticket, ticket)}
  end

  def handle_event("add_message", %{"message" => msg}, socket) do
    ticket = socket.assigns.selected_ticket
    if ticket && msg != "" do
      TicketSystem.add_thread_entry(ticket.id, [
        author_id: "board",
        author_name: "Board",
        type: :message,
        content: msg
      ])
      updated = TicketSystem.get(ticket.id)
      {:noreply, assign(socket, selected_ticket: updated, new_message: "")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:ticket_created, _}, socket), do: {:noreply, refresh_data(socket)}
  def handle_info({:ticket_status, id, _}, socket) do
    selected = socket.assigns.selected_ticket
    if selected && selected.id == id do
      {:noreply, socket |> refresh_data() |> assign(:selected_ticket, TicketSystem.get(id))}
    else
      {:noreply, refresh_data(socket)}
    end
  end
  def handle_info({:thread_update, id, _}, socket) do
    selected = socket.assigns.selected_ticket
    if selected && selected.id == id do
      {:noreply, assign(socket, :selected_ticket, TicketSystem.get(id))}
    else
      {:noreply, socket}
    end
  end
  def handle_info(_, socket), do: {:noreply, socket}

  defp refresh_data(socket) do
    filter = socket.assigns.filter
    tickets = if filter == :all, do: TicketSystem.list(), else: TicketSystem.list_by_status(filter)
    assign(socket, :tickets, tickets)
  end

  defp status_color(:open), do: "bg-blue-500/20 text-blue-400"
  defp status_color(:in_progress), do: "bg-yellow-500/20 text-yellow-400"
  defp status_color(:review), do: "bg-purple-500/20 text-purple-400"
  defp status_color(:done), do: "bg-emerald-500/20 text-emerald-400"
  defp status_color(:blocked), do: "bg-red-500/20 text-red-400"
  defp status_color(_), do: "bg-gray-700 text-gray-400"

  defp priority_icon(:critical), do: "!!"
  defp priority_icon(:high), do: "!"
  defp priority_icon(:medium), do: "-"
  defp priority_icon(:low), do: "."
  defp priority_icon(_), do: "-"

  defp thread_type_color(:message), do: "border-gray-700"
  defp thread_type_color(:tool_call), do: "border-cyan-800"
  defp thread_type_color(:status_change), do: "border-yellow-800"
  defp thread_type_color(:assignment), do: "border-purple-800"
  defp thread_type_color(:system), do: "border-gray-800"
  defp thread_type_color(_), do: "border-gray-700"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-2xl font-bold text-white">Ticket System</h2>
          <p class="text-sm text-gray-400 mt-1">Task management with threaded conversations and audit trails</p>
        </div>
        <button phx-click="show_form" class="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg transition-colors">
          + New Ticket
        </button>
      </div>

      <!-- Create Ticket Form -->
      <%= if @show_form do %>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h3 class="text-lg font-semibold text-white mb-4">Create Ticket</h3>
          <form phx-submit="create_ticket" class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">Title</label>
              <input type="text" name="ticket[title]" required class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">Description</label>
              <textarea name="ticket[description]" rows="3" class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500"></textarea>
            </div>
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Priority</label>
                <select name="ticket[priority]" class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500">
                  <option value="critical">Critical</option>
                  <option value="high">High</option>
                  <option value="medium" selected>Medium</option>
                  <option value="low">Low</option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Labels (comma-separated)</label>
                <input type="text" name="ticket[labels]" placeholder="bug, feature, docs" class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
              </div>
            </div>
            <div class="flex gap-3">
              <button type="submit" class="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg">Create</button>
              <button type="button" phx-click="hide_form" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-gray-300 text-sm font-medium rounded-lg">Cancel</button>
            </div>
          </form>
        </div>
      <% end %>

      <!-- Status Filters -->
      <div class="flex gap-2">
        <%= for {label, value} <- [{"All", "all"}, {"Open", "open"}, {"In Progress", "in_progress"}, {"Review", "review"}, {"Done", "done"}, {"Blocked", "blocked"}] do %>
          <button phx-click="filter" phx-value-status={value} class={[
            "px-3 py-1.5 text-xs font-medium rounded-lg transition-colors",
            to_string(@filter) == value && "bg-emerald-600 text-white",
            to_string(@filter) != value && "bg-gray-800 text-gray-400 hover:text-white"
          ]}>
            <%= label %>
          </button>
        <% end %>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Ticket List -->
        <div class="space-y-2">
          <%= if @tickets == [] do %>
            <div class="bg-gray-900/50 border border-dashed border-gray-700 rounded-xl p-8 text-center">
              <p class="text-gray-500">No tickets found.</p>
            </div>
          <% else %>
            <%= for ticket <- @tickets do %>
              <div class={"bg-gray-900 border rounded-lg p-4 cursor-pointer hover:border-gray-700 transition-colors #{if @selected_ticket && @selected_ticket.id == ticket.id, do: "border-emerald-700", else: "border-gray-800"}"}
                   phx-click="select_ticket" phx-value-id={ticket.id}>
                <div class="flex items-center justify-between mb-1">
                  <div class="flex items-center gap-2">
                    <span class="text-xs font-mono text-emerald-400"><%= ticket.id %></span>
                    <span class={["text-xs font-bold", if(ticket.priority in [:critical, :high], do: "text-red-400", else: "text-gray-500")]}>
                      <%= priority_icon(ticket.priority) %>
                    </span>
                  </div>
                  <span class={["px-2 py-0.5 rounded text-xs font-medium", status_color(ticket.status)]}>
                    <%= ticket.status %>
                  </span>
                </div>
                <h4 class="text-sm font-medium text-white"><%= ticket.title %></h4>
                <div class="flex items-center gap-2 mt-2">
                  <%= for label <- ticket.labels do %>
                    <span class="px-1.5 py-0.5 bg-gray-800 text-gray-400 rounded text-xs"><%= label %></span>
                  <% end %>
                  <span class="text-xs text-gray-600 ml-auto"><%= length(ticket.thread) %> entries</span>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

        <!-- Ticket Detail / Thread -->
        <div>
          <%= if @selected_ticket do %>
            <div class="bg-gray-900 border border-gray-800 rounded-xl p-5">
              <div class="flex items-center justify-between mb-3">
                <div>
                  <span class="text-xs font-mono text-emerald-400"><%= @selected_ticket.id %></span>
                  <h3 class="text-lg font-semibold text-white"><%= @selected_ticket.title %></h3>
                </div>
                <div class="flex gap-1">
                  <%= for status <- [:open, :in_progress, :review, :done, :blocked] do %>
                    <button phx-click="change_status" phx-value-id={@selected_ticket.id} phx-value-status={status}
                      class={["px-2 py-1 rounded text-xs transition-colors",
                        @selected_ticket.status == status && "bg-emerald-600 text-white",
                        @selected_ticket.status != status && "bg-gray-800 text-gray-500 hover:text-gray-300"
                      ]}>
                      <%= status %>
                    </button>
                  <% end %>
                </div>
              </div>

              <%= if @selected_ticket.description && @selected_ticket.description != "" do %>
                <p class="text-sm text-gray-400 mb-4"><%= @selected_ticket.description %></p>
              <% end %>

              <!-- Thread -->
              <div class="space-y-2 mb-4 max-h-96 overflow-y-auto">
                <%= for entry <- @selected_ticket.thread do %>
                  <div class={"border-l-2 pl-3 py-1 #{thread_type_color(entry.type)}"}>
                    <div class="flex items-center gap-2 mb-0.5">
                      <span class="text-xs font-medium text-gray-300"><%= entry.author_name %></span>
                      <span class="text-xs text-gray-600"><%= entry.type %></span>
                      <%= if entry.timestamp do %>
                        <span class="text-xs text-gray-700 ml-auto"><%= Calendar.strftime(entry.timestamp, "%H:%M:%S") %></span>
                      <% end %>
                    </div>
                    <p class="text-sm text-gray-400"><%= entry.content %></p>
                  </div>
                <% end %>
              </div>

              <!-- Add Message -->
              <form phx-submit="add_message" class="flex gap-2">
                <input type="text" name="message" value={@new_message} placeholder="Add a message..."
                  class="flex-1 bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
                <button type="submit" class="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg">Send</button>
              </form>
            </div>
          <% else %>
            <div class="bg-gray-900/50 border border-dashed border-gray-700 rounded-xl p-12 text-center">
              <p class="text-gray-500">Select a ticket to view details</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
