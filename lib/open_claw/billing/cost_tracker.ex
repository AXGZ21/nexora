defmodule OpenClaw.Billing.CostTracker do
  @moduledoc """
  Tracks costs per agent, provider, and model.

  Uses an ETS table for fast in-memory tracking with periodic
  snapshots. Publishes cost events via PubSub for real-time
  dashboard updates.
  """
  use GenServer
  require Logger

  @table :open_claw_costs

  defstruct entries: [], total_cost: 0.0, total_tokens: 0

  # --- Client API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def record(agent_id, provider, model, tokens, cost) do
    entry = %{
      agent_id: agent_id,
      provider: provider,
      model: model,
      tokens: tokens || 0,
      cost: cost || 0.0,
      timestamp: DateTime.utc_now()
    }

    :ets.insert(@table, {System.unique_integer([:positive]), entry})

    Phoenix.PubSub.broadcast(
      OpenClaw.PubSub,
      "costs",
      {:cost_entry, entry}
    )
  end

  def get_entries do
    :ets.tab2list(@table)
    |> Enum.map(fn {_id, entry} -> entry end)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  def get_total_cost do
    get_entries()
    |> Enum.reduce(0.0, fn entry, acc -> acc + (entry.cost || 0.0) end)
  end

  def get_total_tokens do
    get_entries()
    |> Enum.reduce(0, fn entry, acc -> acc + (entry.tokens || 0) end)
  end

  def get_cost_by_provider do
    get_entries()
    |> Enum.group_by(& &1.provider)
    |> Enum.map(fn {provider, entries} ->
      %{
        provider: provider,
        cost: Enum.reduce(entries, 0.0, fn e, acc -> acc + (e.cost || 0.0) end),
        tokens: Enum.reduce(entries, 0, fn e, acc -> acc + (e.tokens || 0) end),
        requests: length(entries)
      }
    end)
  end

  def get_cost_by_agent do
    get_entries()
    |> Enum.group_by(& &1.agent_id)
    |> Enum.map(fn {agent_id, entries} ->
      %{
        agent_id: agent_id,
        cost: Enum.reduce(entries, 0.0, fn e, acc -> acc + (e.cost || 0.0) end),
        tokens: Enum.reduce(entries, 0, fn e, acc -> acc + (e.tokens || 0) end),
        requests: length(entries)
      }
    end)
  end

  def get_daily_costs(days \\ 7) do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -days * 86400, :second)

    get_entries()
    |> Enum.filter(fn e -> DateTime.compare(e.timestamp, cutoff) == :gt end)
    |> Enum.group_by(fn e -> DateTime.to_date(e.timestamp) end)
    |> Enum.map(fn {date, entries} ->
      %{
        date: date,
        cost: Enum.reduce(entries, 0.0, fn e, acc -> acc + (e.cost || 0.0) end),
        tokens: Enum.reduce(entries, 0, fn e, acc -> acc + (e.tokens || 0) end)
      }
    end)
    |> Enum.sort_by(& &1.date)
  end

  def clear do
    :ets.delete_all_objects(@table)
  end

  # --- Server ---

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :bag])
    {:ok, %__MODULE__{}}
  end
end
