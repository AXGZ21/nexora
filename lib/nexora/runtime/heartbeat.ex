defmodule Nexora.Runtime.Heartbeat do
  @moduledoc """
  Heartbeat scheduling for agent wake cycles.

  Manages periodic check-ins and scheduled task execution.
  Agents can register heartbeat intervals and the system
  will wake them at the specified frequency.
  """
  use GenServer

  @table :heartbeats

  defmodule Schedule do
    defstruct [
      :id,
      :agent_id,
      :interval_ms,      # heartbeat interval in milliseconds
      :callback_type,     # :health_check | :task_poll | :report | :custom
      :last_beat,
      :next_beat,
      :miss_count,        # consecutive missed heartbeats
      :max_misses,        # threshold before alert
      enabled: true,
      metadata: %{},
      created_at: nil
    ]
  end

  # --- Client API ---

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def register(attrs), do: GenServer.call(__MODULE__, {:register, attrs})
  def unregister(id), do: GenServer.call(__MODULE__, {:unregister, id})
  def list, do: GenServer.call(__MODULE__, :list)
  def get(id), do: GenServer.call(__MODULE__, {:get, id})
  def record_beat(id), do: GenServer.call(__MODULE__, {:beat, id})
  def get_agent_schedules(agent_id), do: GenServer.call(__MODULE__, {:by_agent, agent_id})
  def get_overdue, do: GenServer.call(__MODULE__, :overdue)

  # --- Server ---

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    schedule_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, attrs}, _from, state) do
    now = DateTime.utc_now()
    interval = attrs[:interval_ms] || 60_000
    schedule = %Schedule{
      id: attrs[:id] || generate_id(),
      agent_id: attrs[:agent_id],
      interval_ms: interval,
      callback_type: attrs[:callback_type] || :health_check,
      last_beat: now,
      next_beat: DateTime.add(now, interval, :millisecond),
      miss_count: 0,
      max_misses: attrs[:max_misses] || 3,
      enabled: Map.get(attrs, :enabled, true),
      metadata: attrs[:metadata] || %{},
      created_at: now
    }

    :ets.insert(@table, {schedule.id, schedule})
    broadcast({:heartbeat_registered, schedule})
    {:reply, {:ok, schedule}, state}
  end

  def handle_call({:unregister, id}, _from, state) do
    :ets.delete(@table, id)
    {:reply, :ok, state}
  end

  def handle_call(:list, _from, state) do
    schedules = :ets.tab2list(@table) |> Enum.map(fn {_, s} -> s end)
    {:reply, schedules, state}
  end

  def handle_call({:get, id}, _from, state) do
    case :ets.lookup(@table, id) do
      [{_, s}] -> {:reply, s, state}
      [] -> {:reply, nil, state}
    end
  end

  def handle_call({:beat, id}, _from, state) do
    case :ets.lookup(@table, id) do
      [{_, schedule}] ->
        now = DateTime.utc_now()
        updated = %{schedule |
          last_beat: now,
          next_beat: DateTime.add(now, schedule.interval_ms, :millisecond),
          miss_count: 0
        }
        :ets.insert(@table, {id, updated})
        broadcast({:heartbeat_received, updated})
        {:reply, {:ok, updated}, state}
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:by_agent, agent_id}, _from, state) do
    schedules = :ets.tab2list(@table)
      |> Enum.map(fn {_, s} -> s end)
      |> Enum.filter(&(&1.agent_id == agent_id))
    {:reply, schedules, state}
  end

  def handle_call(:overdue, _from, state) do
    now = DateTime.utc_now()
    overdue = :ets.tab2list(@table)
      |> Enum.map(fn {_, s} -> s end)
      |> Enum.filter(fn s ->
        s.enabled and DateTime.compare(now, s.next_beat) == :gt
      end)
    {:reply, overdue, state}
  end

  @impl true
  def handle_info(:tick, state) do
    check_heartbeats()
    schedule_tick()
    {:noreply, state}
  end

  # --- Private ---

  defp check_heartbeats do
    now = DateTime.utc_now()
    :ets.tab2list(@table)
    |> Enum.each(fn {id, schedule} ->
      if schedule.enabled and DateTime.compare(now, schedule.next_beat) == :gt do
        updated = %{schedule |
          miss_count: schedule.miss_count + 1,
          next_beat: DateTime.add(now, schedule.interval_ms, :millisecond)
        }
        :ets.insert(@table, {id, updated})

        if updated.miss_count >= updated.max_misses do
          broadcast({:heartbeat_alert, updated})
        else
          broadcast({:heartbeat_missed, updated})
        end
      end
    end)
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, 10_000)
  end

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(Nexora.PubSub, "heartbeats", event)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false) |> String.downcase()
  end
end
