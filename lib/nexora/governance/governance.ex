defmodule Nexora.Governance do
  @moduledoc """
  Board-level governance and approval workflows.

  Implements Paperclip-style governance:
  - Proposals require board approval before execution
  - Configurable approval thresholds
  - Audit trail of all decisions
  - Role-based voting rights
  """
  use GenServer

  @table :governance

  defmodule Proposal do
    defstruct [
      :id,
      :title,
      :description,
      :type,            # :budget | :strategy | :hiring | :tool_access | :deployment | :custom
      :proposer_id,
      :status,          # :pending | :approved | :rejected | :expired
      :required_approvals,
      :expires_at,
      votes: [],        # list of %{voter_id, vote, timestamp, reason}
      metadata: %{},
      created_at: nil,
      decided_at: nil
    ]
  end

  # --- Client API ---

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def propose(attrs), do: GenServer.call(__MODULE__, {:propose, attrs})
  def vote(proposal_id, voter_id, decision, reason \\ nil), do: GenServer.call(__MODULE__, {:vote, proposal_id, voter_id, decision, reason})
  def get(id), do: GenServer.call(__MODULE__, {:get, id})
  def list, do: GenServer.call(__MODULE__, :list)
  def list_pending, do: GenServer.call(__MODULE__, :pending)
  def list_by_type(type), do: GenServer.call(__MODULE__, {:by_type, type})
  def cancel(id), do: GenServer.call(__MODULE__, {:cancel, id})

  # --- Server ---

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, %{counter: 0}}
  end

  @impl true
  def handle_call({:propose, attrs}, _from, %{counter: c} = state) do
    id = "GOV-#{c + 1}"
    now = DateTime.utc_now()
    proposal = %Proposal{
      id: id,
      title: attrs[:title] || "Untitled Proposal",
      description: attrs[:description] || "",
      type: attrs[:type] || :custom,
      proposer_id: attrs[:proposer_id] || "system",
      status: :pending,
      required_approvals: attrs[:required_approvals] || 1,
      expires_at: attrs[:expires_at] || DateTime.add(now, 7 * 86400, :second),
      metadata: attrs[:metadata] || %{},
      created_at: now
    }

    :ets.insert(@table, {id, proposal})
    broadcast({:proposal_created, proposal})
    {:reply, {:ok, proposal}, %{state | counter: c + 1}}
  end

  def handle_call({:vote, proposal_id, voter_id, decision, reason}, _from, state) do
    case :ets.lookup(@table, proposal_id) do
      [{_, proposal}] when proposal.status == :pending ->
        already_voted = Enum.any?(proposal.votes, &(&1.voter_id == voter_id))
        if already_voted do
          {:reply, {:error, :already_voted}, state}
        else
          vote = %{voter_id: voter_id, vote: decision, timestamp: DateTime.utc_now(), reason: reason}
          updated_votes = proposal.votes ++ [vote]

          approvals = Enum.count(updated_votes, &(&1.vote == :approve))
          rejections = Enum.count(updated_votes, &(&1.vote == :reject))

          new_status = cond do
            approvals >= proposal.required_approvals -> :approved
            rejections >= proposal.required_approvals -> :rejected
            true -> :pending
          end

          decided_at = if new_status != :pending, do: DateTime.utc_now(), else: nil

          updated = %{proposal |
            votes: updated_votes,
            status: new_status,
            decided_at: decided_at
          }

          :ets.insert(@table, {proposal_id, updated})

          case new_status do
            :approved -> broadcast({:proposal_approved, updated})
            :rejected -> broadcast({:proposal_rejected, updated})
            :pending -> broadcast({:proposal_voted, updated})
          end

          {:reply, {:ok, updated}, state}
        end

      [{_, _proposal}] ->
        {:reply, {:error, :not_pending}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:get, id}, _from, state) do
    case :ets.lookup(@table, id) do
      [{_, p}] -> {:reply, p, state}
      [] -> {:reply, nil, state}
    end
  end

  def handle_call(:list, _from, state) do
    proposals = :ets.tab2list(@table) |> Enum.map(fn {_, p} -> p end)
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
    {:reply, proposals, state}
  end

  def handle_call(:pending, _from, state) do
    proposals = :ets.tab2list(@table)
      |> Enum.map(fn {_, p} -> p end)
      |> Enum.filter(&(&1.status == :pending))
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
    {:reply, proposals, state}
  end

  def handle_call({:by_type, type}, _from, state) do
    proposals = :ets.tab2list(@table)
      |> Enum.map(fn {_, p} -> p end)
      |> Enum.filter(&(&1.type == type))
    {:reply, proposals, state}
  end

  def handle_call({:cancel, id}, _from, state) do
    case :ets.lookup(@table, id) do
      [{_, proposal}] when proposal.status == :pending ->
        updated = %{proposal | status: :expired, decided_at: DateTime.utc_now()}
        :ets.insert(@table, {id, updated})
        broadcast({:proposal_cancelled, updated})
        {:reply, {:ok, updated}, state}
      [{_, _}] ->
        {:reply, {:error, :not_pending}, state}
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  # --- Private ---

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(Nexora.PubSub, "governance", event)
  end
end
