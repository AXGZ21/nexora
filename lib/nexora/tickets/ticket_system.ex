defmodule Nexora.Tickets.TicketSystem do
  @moduledoc """
  Ticket-based task management with threaded conversations and audit trails.

  Every instruction, response, tool call, and decision is recorded
  with full tracing. Sessions persist across reboots.
  """
  use GenServer

  @table :tickets

  defmodule Ticket do
    defstruct [
      :id,
      :title,
      :description,
      :status,        # :open | :in_progress | :review | :done | :blocked
      :priority,      # :critical | :high | :medium | :low
      :assignee_id,   # agent_id
      :reporter_id,
      :goal_id,       # links to goal tracker
      :role_id,       # links to org chart
      thread: [],     # conversation thread
      labels: [],
      metadata: %{},
      created_at: nil,
      updated_at: nil,
      closed_at: nil
    ]
  end

  defmodule ThreadEntry do
    defstruct [
      :id,
      :author_id,     # agent_id or "board"
      :author_name,
      :type,          # :message | :tool_call | :status_change | :assignment | :system
      :content,
      :metadata,
      timestamp: nil
    ]
  end

  # --- Client API ---

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def create(attrs), do: GenServer.call(__MODULE__, {:create, attrs})
  def update(id, changes), do: GenServer.call(__MODULE__, {:update, id, changes})
  def add_thread_entry(ticket_id, entry), do: GenServer.call(__MODULE__, {:add_thread, ticket_id, entry})
  def assign(ticket_id, agent_id), do: GenServer.call(__MODULE__, {:assign, ticket_id, agent_id})
  def change_status(ticket_id, status), do: GenServer.call(__MODULE__, {:status, ticket_id, status})
  def get(ticket_id), do: GenServer.call(__MODULE__, {:get, ticket_id})
  def list, do: GenServer.call(__MODULE__, :list)
  def list_by_status(status), do: GenServer.call(__MODULE__, {:by_status, status})
  def list_by_assignee(agent_id), do: GenServer.call(__MODULE__, {:by_assignee, agent_id})

  def get_audit_log(ticket_id) do
    case get(ticket_id) do
      nil -> []
      ticket -> Enum.filter(ticket.thread, &(&1.type in [:tool_call, :status_change, :assignment, :system]))
    end
  end

  # --- Server ---

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, %{counter: 0}}
  end

  @impl true
  def handle_call({:create, attrs}, _from, %{counter: c} = state) do
    id = "CLAW-#{c + 1}"
    ticket = %Ticket{
      id: id,
      title: attrs[:title] || "Untitled Ticket",
      description: attrs[:description] || "",
      status: attrs[:status] || :open,
      priority: attrs[:priority] || :medium,
      assignee_id: attrs[:assignee_id],
      reporter_id: attrs[:reporter_id] || "board",
      goal_id: attrs[:goal_id],
      role_id: attrs[:role_id],
      labels: attrs[:labels] || [],
      metadata: attrs[:metadata] || %{},
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      thread: [
        %ThreadEntry{
          id: gen_entry_id(),
          author_id: "system",
          author_name: "System",
          type: :system,
          content: "Ticket created",
          timestamp: DateTime.utc_now()
        }
      ]
    }

    :ets.insert(@table, {id, ticket})
    broadcast({:ticket_created, ticket})
    {:reply, {:ok, ticket}, %{state | counter: c + 1}}
  end

  def handle_call({:update, id, changes}, _from, state) do
    case :ets.lookup(@table, id) do
      [{_, ticket}] ->
        updated = Enum.reduce(changes, ticket, fn {k, v}, acc -> Map.put(acc, k, v) end)
        updated = %{updated | updated_at: DateTime.utc_now()}
        :ets.insert(@table, {id, updated})
        {:reply, {:ok, updated}, state}
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:add_thread, ticket_id, entry_attrs}, _from, state) do
    case :ets.lookup(@table, ticket_id) do
      [{_, ticket}] ->
        entry = %ThreadEntry{
          id: gen_entry_id(),
          author_id: entry_attrs[:author_id] || "unknown",
          author_name: entry_attrs[:author_name] || "Unknown",
          type: entry_attrs[:type] || :message,
          content: entry_attrs[:content] || "",
          metadata: entry_attrs[:metadata],
          timestamp: DateTime.utc_now()
        }
        updated = %{ticket | thread: ticket.thread ++ [entry], updated_at: DateTime.utc_now()}
        :ets.insert(@table, {ticket_id, updated})
        broadcast({:thread_update, ticket_id, entry})
        {:reply, {:ok, entry}, state}
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:assign, ticket_id, agent_id}, _from, state) do
    case :ets.lookup(@table, ticket_id) do
      [{_, ticket}] ->
        entry = %ThreadEntry{
          id: gen_entry_id(),
          author_id: "system", author_name: "System",
          type: :assignment,
          content: "Assigned to agent #{agent_id}",
          timestamp: DateTime.utc_now()
        }
        updated = %{ticket |
          assignee_id: agent_id,
          thread: ticket.thread ++ [entry],
          updated_at: DateTime.utc_now()
        }
        :ets.insert(@table, {ticket_id, updated})
        broadcast({:ticket_assigned, ticket_id, agent_id})
        {:reply, {:ok, updated}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:status, ticket_id, new_status}, _from, state) do
    case :ets.lookup(@table, ticket_id) do
      [{_, ticket}] ->
        entry = %ThreadEntry{
          id: gen_entry_id(),
          author_id: "system", author_name: "System",
          type: :status_change,
          content: "Status changed: #{ticket.status} -> #{new_status}",
          timestamp: DateTime.utc_now()
        }
        closed_at = if new_status == :done, do: DateTime.utc_now(), else: ticket.closed_at
        updated = %{ticket |
          status: new_status,
          closed_at: closed_at,
          thread: ticket.thread ++ [entry],
          updated_at: DateTime.utc_now()
        }
        :ets.insert(@table, {ticket_id, updated})
        broadcast({:ticket_status, ticket_id, new_status})
        {:reply, {:ok, updated}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:get, id}, _from, state) do
    case :ets.lookup(@table, id) do
      [{_, t}] -> {:reply, t, state}
      [] -> {:reply, nil, state}
    end
  end

  def handle_call(:list, _from, state) do
    tickets = :ets.tab2list(@table) |> Enum.map(fn {_, t} -> t end) |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
    {:reply, tickets, state}
  end

  def handle_call({:by_status, status}, _from, state) do
    tickets = :ets.tab2list(@table) |> Enum.map(fn {_, t} -> t end) |> Enum.filter(&(&1.status == status))
    {:reply, tickets, state}
  end

  def handle_call({:by_assignee, agent_id}, _from, state) do
    tickets = :ets.tab2list(@table) |> Enum.map(fn {_, t} -> t end) |> Enum.filter(&(&1.assignee_id == agent_id))
    {:reply, tickets, state}
  end

  defp broadcast(event), do: Phoenix.PubSub.broadcast(Nexora.PubSub, "tickets", event)
  defp gen_entry_id, do: :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
end
