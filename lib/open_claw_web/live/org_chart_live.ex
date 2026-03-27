defmodule OpenClawWeb.OrgChartLive do
  use OpenClawWeb, :live_view

  alias OpenClaw.Org.OrgChart

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(OpenClaw.PubSub, "org")
    end

    roles = OrgChart.list_roles()
    departments = OrgChart.get_departments()
    hierarchy = OrgChart.get_hierarchy()

    socket = socket
      |> assign(:active_tab, :org)
      |> assign(:page_title, "Org Chart")
      |> assign(:roles, roles)
      |> assign(:departments, departments)
      |> assign(:hierarchy, hierarchy)
      |> assign(:show_form, false)
      |> assign(:selected_role, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("show_add_role", _params, socket) do
    {:noreply, assign(socket, :show_form, true)}
  end

  def handle_event("hide_form", _params, socket) do
    {:noreply, assign(socket, :show_form, false)}
  end

  def handle_event("add_role", %{"role" => params}, socket) do
    attrs = [
      title: params["title"],
      department: params["department"],
      description: params["description"],
      reports_to: if(params["reports_to"] == "", do: nil, else: params["reports_to"])
    ]

    case OrgChart.add_role(attrs) do
      {:ok, _role} ->
        {:noreply, socket |> refresh_data() |> assign(:show_form, false) |> put_flash(:info, "Role added")}
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to add role")}
    end
  end

  def handle_event("remove_role", %{"id" => id}, socket) do
    OrgChart.remove_role(id)
    {:noreply, refresh_data(socket) |> put_flash(:info, "Role removed")}
  end

  def handle_event("select_role", %{"id" => id}, socket) do
    role = OrgChart.get_role(id)
    {:noreply, assign(socket, :selected_role, role)}
  end

  @impl true
  def handle_info({:role_added, _}, socket), do: {:noreply, refresh_data(socket)}
  def handle_info({:role_removed, _}, socket), do: {:noreply, refresh_data(socket)}
  def handle_info({:agent_assigned, _, _}, socket), do: {:noreply, refresh_data(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  defp refresh_data(socket) do
    socket
    |> assign(:roles, OrgChart.list_roles())
    |> assign(:departments, OrgChart.get_departments())
    |> assign(:hierarchy, OrgChart.get_hierarchy())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-2xl font-bold text-white">Organization Chart</h2>
          <p class="text-sm text-gray-400 mt-1">Agent roles, departments, and reporting lines</p>
        </div>
        <button phx-click="show_add_role" class="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg transition-colors">
          + Add Role
        </button>
      </div>

      <!-- Add Role Form -->
      <%= if @show_form do %>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h3 class="text-lg font-semibold text-white mb-4">Add New Role</h3>
          <form phx-submit="add_role" class="space-y-4">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Title</label>
                <input type="text" name="role[title]" required placeholder="e.g. Lead Engineer"
                  class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Department</label>
                <input type="text" name="role[department]" required placeholder="e.g. Engineering"
                  class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
              </div>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">Description</label>
              <input type="text" name="role[description]" placeholder="Role description"
                class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">Reports To</label>
              <select name="role[reports_to]" class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500">
                <option value="">None (Top Level)</option>
                <%= for role <- @roles do %>
                  <option value={role.id}><%= role.title %> (<%= role.id %>)</option>
                <% end %>
              </select>
            </div>
            <div class="flex gap-3">
              <button type="submit" class="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg">Save</button>
              <button type="button" phx-click="hide_form" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-gray-300 text-sm font-medium rounded-lg">Cancel</button>
            </div>
          </form>
        </div>
      <% end %>

      <!-- Department Summary -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
        <%= for dept <- @departments do %>
          <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
            <h4 class="text-sm font-semibold text-emerald-400"><%= dept.name %></h4>
            <p class="text-2xl font-bold text-white mt-1"><%= dept.count %></p>
            <p class="text-xs text-gray-500">roles</p>
          </div>
        <% end %>
      </div>

      <!-- Hierarchy Tree -->
      <div class="bg-gray-900 border border-gray-800 rounded-xl p-6">
        <h3 class="text-lg font-semibold text-white mb-4">Hierarchy</h3>
        <div class="space-y-2">
          <%= for node <- @hierarchy do %>
            <.tree_node node={node} depth={0} />
          <% end %>
        </div>
      </div>

      <!-- Role Detail -->
      <%= if @selected_role do %>
        <div class="bg-gray-900 border border-emerald-800/50 rounded-xl p-6">
          <h3 class="text-lg font-semibold text-white mb-2"><%= @selected_role.title %></h3>
          <div class="grid grid-cols-2 gap-4 text-sm">
            <div><span class="text-gray-500">ID:</span> <span class="text-gray-300 font-mono"><%= @selected_role.id %></span></div>
            <div><span class="text-gray-500">Department:</span> <span class="text-gray-300"><%= @selected_role.department %></span></div>
            <div><span class="text-gray-500">Reports To:</span> <span class="text-gray-300 font-mono"><%= @selected_role.reports_to || "None" %></span></div>
            <div><span class="text-gray-500">Agent:</span> <span class="text-gray-300 font-mono"><%= @selected_role.agent_id || "Unassigned" %></span></div>
          </div>
          <p class="text-sm text-gray-400 mt-3"><%= @selected_role.description %></p>
        </div>
      <% end %>
    </div>
    """
  end

  defp tree_node(assigns) do
    ~H"""
    <div style={"margin-left: #{@depth * 24}px"}>
      <div class="flex items-center gap-2 py-1.5 px-3 rounded-lg hover:bg-gray-800/50 cursor-pointer group"
           phx-click="select_role" phx-value-id={@node.role.id}>
        <%= if @depth > 0 do %>
          <span class="text-gray-600">|--</span>
        <% end %>
        <div class="w-2 h-2 rounded-full bg-emerald-500"></div>
        <span class="text-sm font-medium text-white"><%= @node.role.title %></span>
        <span class="text-xs text-gray-500"><%= @node.role.department %></span>
        <%= if @node.role.agent_id do %>
          <span class="text-xs px-1.5 py-0.5 bg-emerald-500/20 text-emerald-400 rounded font-mono"><%= @node.role.agent_id %></span>
        <% end %>
      </div>
      <%= for child <- @node.children do %>
        <.tree_node node={child} depth={@depth + 1} />
      <% end %>
    </div>
    """
  end
end
