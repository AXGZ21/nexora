defmodule Nexora.Billing.BudgetEnforcer do
  @moduledoc """
  Per-agent budget enforcement with auto-pause capabilities.

  Monitors spending against configured limits and can:
  - Warn at 80% budget utilization
  - Auto-pause agents at 100% budget
  - Track daily/weekly/monthly budgets
  - Provide real-time budget status
  """
  use GenServer

  @table :budgets

  defmodule Budget do
    defstruct [
      :id,
      :agent_id,
      :limit,           # dollar amount
      :period,          # :daily | :weekly | :monthly | :total
      :spent,
      :status,          # :ok | :warning | :exceeded | :paused
      :warn_threshold,  # percentage (0-100), default 80
      :hard_limit,      # auto-pause at this percentage, default 100
      enabled: true,
      history: [],
      created_at: nil,
      updated_at: nil
    ]
  end

  # --- Client API ---

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def set_budget(attrs), do: GenServer.call(__MODULE__, {:set_budget, attrs})
  def remove_budget(id), do: GenServer.call(__MODULE__, {:remove, id})
  def record_spend(agent_id, amount), do: GenServer.call(__MODULE__, {:spend, agent_id, amount})
  def get_budget(id), do: GenServer.call(__MODULE__, {:get, id})
  def get_agent_budget(agent_id), do: GenServer.call(__MODULE__, {:by_agent, agent_id})
  def list, do: GenServer.call(__MODULE__, :list)
  def check_allowance(agent_id), do: GenServer.call(__MODULE__, {:check, agent_id})
  def reset_budget(id), do: GenServer.call(__MODULE__, {:reset, id})

  # --- Server ---

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:set_budget, attrs}, _from, state) do
    budget = %Budget{
      id: attrs[:id] || generate_id(),
      agent_id: attrs[:agent_id],
      limit: attrs[:limit] || 10.0,
      period: attrs[:period] || :monthly,
      spent: attrs[:spent] || 0.0,
      status: :ok,
      warn_threshold: attrs[:warn_threshold] || 80,
      hard_limit: attrs[:hard_limit] || 100,
      enabled: Map.get(attrs, :enabled, true),
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    :ets.insert(@table, {budget.id, budget})
    broadcast({:budget_set, budget})
    {:reply, {:ok, budget}, state}
  end

  def handle_call({:remove, id}, _from, state) do
    :ets.delete(@table, id)
    {:reply, :ok, state}
  end

  def handle_call({:spend, agent_id, amount}, _from, state) do
    budgets = :ets.tab2list(@table)
      |> Enum.map(fn {_, b} -> b end)
      |> Enum.filter(&(&1.agent_id == agent_id and &1.enabled))

    results = Enum.map(budgets, fn budget ->
      new_spent = budget.spent + amount
      pct = if budget.limit > 0, do: new_spent / budget.limit * 100, else: 0

      new_status = cond do
        pct >= budget.hard_limit -> :exceeded
        pct >= budget.warn_threshold -> :warning
        true -> :ok
      end

      entry = %{amount: amount, timestamp: DateTime.utc_now(), running_total: new_spent}
      updated = %{budget |
        spent: new_spent,
        status: new_status,
        history: [entry | Enum.take(budget.history, 99)],
        updated_at: DateTime.utc_now()
      }

      :ets.insert(@table, {budget.id, updated})

      if new_status == :exceeded and budget.status != :exceeded do
        broadcast({:budget_exceeded, updated})
      end

      if new_status == :warning and budget.status == :ok do
        broadcast({:budget_warning, updated})
      end

      updated
    end)

    {:reply, {:ok, results}, state}
  end

  def handle_call({:get, id}, _from, state) do
    case :ets.lookup(@table, id) do
      [{_, b}] -> {:reply, b, state}
      [] -> {:reply, nil, state}
    end
  end

  def handle_call({:by_agent, agent_id}, _from, state) do
    budgets = :ets.tab2list(@table)
      |> Enum.map(fn {_, b} -> b end)
      |> Enum.filter(&(&1.agent_id == agent_id))
    {:reply, budgets, state}
  end

  def handle_call(:list, _from, state) do
    budgets = :ets.tab2list(@table) |> Enum.map(fn {_, b} -> b end)
    {:reply, budgets, state}
  end

  def handle_call({:check, agent_id}, _from, state) do
    budgets = :ets.tab2list(@table)
      |> Enum.map(fn {_, b} -> b end)
      |> Enum.filter(&(&1.agent_id == agent_id and &1.enabled))

    blocked = Enum.any?(budgets, &(&1.status == :exceeded))
    {:reply, if(blocked, do: {:denied, :budget_exceeded}, else: :allowed), state}
  end

  def handle_call({:reset, id}, _from, state) do
    case :ets.lookup(@table, id) do
      [{_, budget}] ->
        updated = %{budget | spent: 0.0, status: :ok, updated_at: DateTime.utc_now()}
        :ets.insert(@table, {id, updated})
        broadcast({:budget_reset, updated})
        {:reply, {:ok, updated}, state}
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  # --- Private ---

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(Nexora.PubSub, "budgets", event)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false) |> String.downcase()
  end
end
