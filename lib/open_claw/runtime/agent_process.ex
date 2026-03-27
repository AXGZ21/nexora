defmodule OpenClaw.Runtime.AgentProcess do
  @moduledoc """
  GenServer representing a single running AI agent.

  Each agent process manages:
  - Connection to an LLM provider
  - Conversation state and message history
  - Tool execution and streaming responses
  - Cost tracking per request
  """
  use GenServer
  require Logger

  alias OpenClaw.Billing.CostTracker
  alias OpenClaw.Runtime.LLMClient

  defstruct [
    :id,
    :name,
    :model,
    :provider,
    :status,
    :system_prompt,
    :created_at,
    :started_at,
    messages: [],
    total_tokens: 0,
    total_cost: 0.0,
    metadata: %{}
  ]

  # --- Client API ---

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(id))
  end

  def send_message(agent_id, content, opts \\ []) do
    GenServer.call(via_tuple(agent_id), {:send_message, content, opts}, 120_000)
  end

  def stream_message(agent_id, content, reply_to, opts \\ []) do
    GenServer.cast(via_tuple(agent_id), {:stream_message, content, reply_to, opts})
  end

  def get_state(agent_id) do
    GenServer.call(via_tuple(agent_id), :get_state)
  end

  def stop(agent_id) do
    GenServer.call(via_tuple(agent_id), :stop)
  end

  def pause(agent_id) do
    GenServer.call(via_tuple(agent_id), :pause)
  end

  def resume(agent_id) do
    GenServer.call(via_tuple(agent_id), :resume)
  end

  def get_messages(agent_id) do
    GenServer.call(via_tuple(agent_id), :get_messages)
  end

  def clear_messages(agent_id) do
    GenServer.call(via_tuple(agent_id), :clear_messages)
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    name = Keyword.get(opts, :name, "Agent #{id}")
    model = Keyword.get(opts, :model, "claude-sonnet-4-6")
    provider = Keyword.get(opts, :provider, :anthropic)
    system_prompt = Keyword.get(opts, :system_prompt, default_system_prompt())

    state = %__MODULE__{
      id: id,
      name: name,
      model: model,
      provider: provider,
      status: :running,
      system_prompt: system_prompt,
      created_at: DateTime.utc_now(),
      started_at: DateTime.utc_now(),
      messages: [],
      metadata: Keyword.get(opts, :metadata, %{})
    }

    Logger.info("Agent #{id} (#{name}) started with model #{model}")
    broadcast_status(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:send_message, _content, _opts}, _from, %{status: :paused} = state) do
    {:reply, {:error, :agent_paused}, state}
  end

  def handle_call({:send_message, content, opts}, _from, state) do
    user_msg = %{role: "user", content: content, timestamp: DateTime.utc_now()}
    messages = state.messages ++ [user_msg]

    case LLMClient.chat(state.provider, state.model, messages, state.system_prompt, opts) do
      {:ok, response} ->
        assistant_msg = %{
          role: "assistant",
          content: response.content,
          timestamp: DateTime.utc_now(),
          tokens: response.tokens,
          cost: response.cost
        }

        new_state = %{state |
          messages: messages ++ [assistant_msg],
          total_tokens: state.total_tokens + (response.tokens || 0),
          total_cost: state.total_cost + (response.cost || 0.0)
        }

        CostTracker.record(state.id, state.provider, state.model, response.tokens, response.cost)
        broadcast_message(new_state, assistant_msg)
        {:reply, {:ok, response}, new_state}

      {:error, reason} ->
        Logger.error("Agent #{state.id} LLM error: #{inspect(reason)}")
        {:reply, {:error, reason}, %{state | messages: messages}}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state_to_map(state), state}
  end

  def handle_call(:get_messages, _from, state) do
    {:reply, state.messages, state}
  end

  def handle_call(:clear_messages, _from, state) do
    new_state = %{state | messages: []}
    {:reply, :ok, new_state}
  end

  def handle_call(:pause, _from, state) do
    new_state = %{state | status: :paused}
    broadcast_status(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:resume, _from, state) do
    new_state = %{state | status: :running}
    broadcast_status(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:stop, _from, state) do
    new_state = %{state | status: :stopped}
    broadcast_status(new_state)
    {:stop, :normal, :ok, new_state}
  end

  @impl true
  def handle_cast({:stream_message, content, reply_to, opts}, state) do
    user_msg = %{role: "user", content: content, timestamp: DateTime.utc_now()}
    messages = state.messages ++ [user_msg]

    broadcast_message(state, user_msg)

    # Stream in a separate task to not block the GenServer
    agent_id = state.id
    provider = state.provider
    model = state.model
    system_prompt = state.system_prompt

    Task.start(fn ->
      case LLMClient.stream(provider, model, messages, system_prompt, opts) do
        {:ok, stream} ->
          full_content = stream_to_client(agent_id, reply_to, stream)

          assistant_msg = %{
            role: "assistant",
            content: full_content,
            timestamp: DateTime.utc_now()
          }

          GenServer.cast(via_tuple(agent_id), {:append_message, assistant_msg})

        {:error, reason} ->
          send(reply_to, {:stream_error, agent_id, reason})
      end
    end)

    {:noreply, %{state | messages: messages}}
  end

  def handle_cast({:append_message, msg}, state) do
    {:noreply, %{state | messages: state.messages ++ [msg]}}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Agent #{state.id} terminated: #{inspect(reason)}")
    broadcast_status(%{state | status: :stopped})
    :ok
  end

  # --- Private ---

  defp via_tuple(id), do: {:via, Registry, {OpenClaw.AgentRegistry, id}}

  defp broadcast_status(state) do
    Phoenix.PubSub.broadcast(
      OpenClaw.PubSub,
      "agents",
      {:agent_status, state.id, state.status, state_to_map(state)}
    )
  end

  defp broadcast_message(state, message) do
    Phoenix.PubSub.broadcast(
      OpenClaw.PubSub,
      "agent:#{state.id}",
      {:agent_message, state.id, message}
    )
  end

  defp stream_to_client(agent_id, reply_to, chunks) when is_list(chunks) do
    Enum.reduce(chunks, "", fn chunk, acc ->
      send(reply_to, {:stream_chunk, agent_id, chunk})
      acc <> chunk
    end)
  end

  defp stream_to_client(_agent_id, _reply_to, content) when is_binary(content) do
    content
  end

  defp state_to_map(state) do
    %{
      id: state.id,
      name: state.name,
      model: state.model,
      provider: state.provider,
      status: state.status,
      system_prompt: state.system_prompt,
      created_at: state.created_at,
      started_at: state.started_at,
      message_count: length(state.messages),
      total_tokens: state.total_tokens,
      total_cost: state.total_cost,
      metadata: state.metadata
    }
  end

  defp default_system_prompt do
    "You are a helpful AI assistant running inside OpenClaw. Be concise, accurate, and helpful."
  end
end
