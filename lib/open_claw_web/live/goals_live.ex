defmodule OpenClawWeb.GoalsLive do
  use OpenClawWeb, :live_view

  alias OpenClaw.Goals.GoalTracker

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(OpenClaw.PubSub, "goals")
    end

    goals = GoalTracker.list()
    tree = GoalTracker.get_tree()

    socket = socket
      |> assign(:active_tab, :goals)
      |> assign(:page_title, "Goals")
      |> assign(:goals, goals)
      |> assign(:tree, tree)
      |> assign(:filter_type, :all)
      |> assign(:show_form, false)
      |> assign(:selected_goal, nil)
      |> assign(:ancestry, [])

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", %{"type" => type}, socket) do
    filter = if type == "all", do: :all, else: String.to_existing_atom(type)
    goals = if filter == :all, do: GoalTracker.list(), else: GoalTracker.list_by_type(filter)
    {:noreply, assign(socket, filter_type: filter, goals: goals)}
  end

  def handle_event("show_form", _params, socket) do
    {:noreply, assign(socket, :show_form, true)}
  end

  def handle_event("hide_form", _params, socket) do
    {:noreply, assign(socket, :show_form, false)}
  end

  def handle_event("create_goal", %{"goal" => params}, socket) do
    attrs = [
      title: params["title"],
      description: params["description"],
      type: String.to_existing_atom(params["type"]),
      priority: String.to_existing_atom(params["priority"]),
      parent_id: if(params["parent_id"] == "", do: nil, else: params["parent_id"])
    ]

    case GoalTracker.create(attrs) do
      {:ok, _goal} ->
        {:noreply, socket |> refresh_data() |> assign(:show_form, false) |> put_flash(:info, "Goal created")}
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to create goal")}
    end
  end

  def handle_event("select_goal", %{"id" => id}, socket) do
    goal = GoalTracker.get(id)
    ancestry = GoalTracker.get_ancestry(id)
    {:noreply, assign(socket, selected_goal: goal, ancestry: ancestry)}
  end

  def handle_event("update_progress", %{"id" => id, "progress" => progress}, socket) do
    {prog, _} = Integer.parse(progress)
    GoalTracker.update(id, progress: prog)
    {:noreply, refresh_data(socket)}
  end

  def handle_event("complete_goal", %{"id" => id}, socket) do
    GoalTracker.update(id, status: :completed, progress: 100)
    {:noreply, refresh_data(socket) |> put_flash(:info, "Goal completed")}
  end

  def handle_event("delete_goal", %{"id" => id}, socket) do
    GoalTracker.delete(id)
    {:noreply, refresh_data(socket) |> assign(:selected_goal, nil) |> put_flash(:info, "Goal deleted")}
  end

  @impl true
  def handle_info({:goal_created, _}, socket), do: {:noreply, refresh_data(socket)}
  def handle_info({:goal_updated, _}, socket), do: {:noreply, refresh_data(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  defp refresh_data(socket) do
    filter = socket.assigns.filter_type
    goals = if filter == :all, do: GoalTracker.list(), else: GoalTracker.list_by_type(filter)
    socket |> assign(:goals, goals) |> assign(:tree, GoalTracker.get_tree())
  end

  defp type_color(:mission), do: "bg-purple-500/20 text-purple-400"
  defp type_color(:objective), do: "bg-blue-500/20 text-blue-400"
  defp type_color(:key_result), do: "bg-cyan-500/20 text-cyan-400"
  defp type_color(:task), do: "bg-gray-700 text-gray-300"
  defp type_color(_), do: "bg-gray-700 text-gray-400"

  defp priority_color(:critical), do: "text-red-400"
  defp priority_color(:high), do: "text-orange-400"
  defp priority_color(:medium), do: "text-yellow-400"
  defp priority_color(:low), do: "text-gray-400"
  defp priority_color(_), do: "text-gray-500"

  defp status_color(:active), do: "bg-emerald-500/20 text-emerald-400"
  defp status_color(:completed), do: "bg-blue-500/20 text-blue-400"
  defp status_color(:blocked), do: "bg-red-500/20 text-red-400"
  defp status_color(:cancelled), do: "bg-gray-700 text-gray-500"
  defp status_color(_), do: "bg-gray-700 text-gray-400"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-2xl font-bold text-white">Goal Tracker</h2>
          <p class="text-sm text-gray-400 mt-1">Mission-aligned goal hierarchy with ancestry tracing</p>
        </div>
        <button phx-click="show_form" class="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg transition-colors">
          + New Goal
        </button>
      </div>

      <!-- Add Goal Form -->
      <%= if @show_form do %>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h3 class="text-lg font-semibold text-white mb-4">Create Goal</h3>
          <form phx-submit="create_goal" class="space-y-4">
            <div class="grid grid-cols-3 gap-4">
              <div class="col-span-2">
                <label class="block text-sm font-medium text-gray-300 mb-1">Title</label>
                <input type="text" name="goal[title]" required class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Type</label>
                <select name="goal[type]" class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500">
                  <option value="mission">Mission</option>
                  <option value="objective">Objective</option>
                  <option value="key_result">Key Result</option>
                  <option value="task" selected>Task</option>
                </select>
              </div>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">Description</label>
              <input type="text" name="goal[description]" class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500" />
            </div>
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Priority</label>
                <select name="goal[priority]" class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500">
                  <option value="critical">Critical</option>
                  <option value="high">High</option>
                  <option value="medium" selected>Medium</option>
                  <option value="low">Low</option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Parent Goal</label>
                <select name="goal[parent_id]" class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500">
                  <option value="">None (Top Level)</option>
                  <%= for g <- GoalTracker.list() do %>
                    <option value={g.id}><%= g.title %> (<%= g.type %>)</option>
                  <% end %>
                </select>
              </div>
            </div>
            <div class="flex gap-3">
              <button type="submit" class="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg">Create</button>
              <button type="button" phx-click="hide_form" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-gray-300 text-sm font-medium rounded-lg">Cancel</button>
            </div>
          </form>
        </div>
      <% end %>

      <!-- Filters -->
      <div class="flex gap-2">
        <%= for {label, value} <- [{"All", "all"}, {"Missions", "mission"}, {"Objectives", "objective"}, {"Key Results", "key_result"}, {"Tasks", "task"}] do %>
          <button phx-click="filter" phx-value-type={value} class={[
            "px-3 py-1.5 text-xs font-medium rounded-lg transition-colors",
            to_string(@filter_type) == value && "bg-emerald-600 text-white",
            to_string(@filter_type) != value && "bg-gray-800 text-gray-400 hover:text-white"
          ]}>
            <%= label %>
          </button>
        <% end %>
      </div>

      <!-- Goal Ancestry (when selected) -->
      <%= if @selected_goal && @ancestry != [] do %>
        <div class="bg-gray-900 border border-emerald-800/50 rounded-xl p-4">
          <h4 class="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2">Goal Ancestry</h4>
          <div class="flex items-center gap-2 flex-wrap">
            <%= for {ancestor, i} <- Enum.with_index(@ancestry) do %>
              <%= if i > 0 do %>
                <span class="text-gray-600">-></span>
              <% end %>
              <span class={["px-2 py-1 rounded text-xs font-medium", type_color(ancestor.type)]}>
                <%= ancestor.title %>
              </span>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Goals List -->
      <div class="space-y-3">
        <%= for goal <- @goals do %>
          <div class={"bg-gray-900 border rounded-xl p-4 cursor-pointer hover:border-gray-700 transition-colors #{if @selected_goal && @selected_goal.id == goal.id, do: "border-emerald-700", else: "border-gray-800"}"}
               phx-click="select_goal" phx-value-id={goal.id}>
            <div class="flex items-center justify-between mb-2">
              <div class="flex items-center gap-2">
                <span class={["px-2 py-0.5 rounded text-xs font-medium", type_color(goal.type)]}>
                  <%= goal.type %>
                </span>
                <h4 class="text-sm font-semibold text-white"><%= goal.title %></h4>
              </div>
              <div class="flex items-center gap-2">
                <span class={["text-xs font-medium", priority_color(goal.priority)]}>
                  <%= goal.priority %>
                </span>
                <span class={["px-2 py-0.5 rounded text-xs font-medium", status_color(goal.status)]}>
                  <%= goal.status %>
                </span>
              </div>
            </div>
            <%= if goal.description && goal.description != "" do %>
              <p class="text-xs text-gray-500 mb-2"><%= goal.description %></p>
            <% end %>
            <!-- Progress Bar -->
            <div class="flex items-center gap-3">
              <div class="flex-1 h-1.5 bg-gray-800 rounded-full overflow-hidden">
                <div class="h-full bg-emerald-500 rounded-full transition-all" style={"width: #{goal.progress}%"}></div>
              </div>
              <span class="text-xs text-gray-400 font-mono w-8 text-right"><%= goal.progress %>%</span>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Goal Tree -->
      <div class="bg-gray-900 border border-gray-800 rounded-xl p-6">
        <h3 class="text-lg font-semibold text-white mb-4">Goal Hierarchy</h3>
        <%= for node <- @tree do %>
          <.goal_tree_node node={node} depth={0} />
        <% end %>
      </div>
    </div>
    """
  end

  defp goal_tree_node(assigns) do
    ~H"""
    <div style={"margin-left: #{@depth * 20}px"} class="py-1">
      <div class="flex items-center gap-2 text-sm">
        <div class={"w-2 h-2 rounded-full #{if @node.goal.status == :completed, do: "bg-blue-500", else: "bg-emerald-500"}"}></div>
        <span class={["px-1.5 py-0.5 rounded text-xs", type_color(@node.goal.type)]}><%= @node.goal.type %></span>
        <span class="text-white font-medium"><%= @node.goal.title %></span>
        <span class="text-gray-500 text-xs"><%= @node.goal.progress %>%</span>
      </div>
      <%= for child <- @node.children do %>
        <.goal_tree_node node={child} depth={@depth + 1} />
      <% end %>
    </div>
    """
  end
end
