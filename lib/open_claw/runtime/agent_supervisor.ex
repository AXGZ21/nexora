defmodule OpenClaw.Runtime.AgentSupervisor do
  @moduledoc """
  DynamicSupervisor for managing agent processes.

  Provides the core agent lifecycle management:
  - Spawn new agents with custom configurations
  - List all running agents
  - Stop/restart individual agents
  - Automatic restart on crash via OTP supervision
  """
  use DynamicSupervisor
  require Logger

  alias OpenClaw.Runtime.AgentProcess

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Spawn a new agent process with the given options."
  def spawn_agent(opts) do
    id = Keyword.get_lazy(opts, :id, fn -> generate_id() end)
    opts = Keyword.put(opts, :id, id)

    spec = {AgentProcess, opts}

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        Logger.info("Spawned agent #{id} (pid: #{inspect(pid)})")
        {:ok, id, pid}

      {:error, {:already_started, pid}} ->
        {:ok, id, pid}

      {:error, reason} ->
        Logger.error("Failed to spawn agent #{id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Stop a running agent."
  def stop_agent(agent_id) do
    case Registry.lookup(OpenClaw.AgentRegistry, agent_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        {:error, :not_found}
    end
  end

  @doc "List all running agents with their current state."
  def list_agents do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.filter(fn {_, pid, _, _} -> is_pid(pid) end)
    |> Enum.map(fn {_, pid, _, _} ->
      try do
        GenServer.call(pid, :get_state, 5000)
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Count running agents."
  def count do
    DynamicSupervisor.count_children(__MODULE__)
    |> Map.get(:active, 0)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8)
    |> Base.url_encode64(padding: false)
  end
end
