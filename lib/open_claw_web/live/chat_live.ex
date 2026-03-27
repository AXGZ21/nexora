defmodule OpenClawWeb.ChatLive do
  use OpenClawWeb, :live_view

  alias OpenClaw.Runtime.{AgentSupervisor, AgentProcess}

  @impl true
  def mount(_params, _session, socket) do
    agents = AgentSupervisor.list_agents()

    {:ok, assign(socket,
      page_title: "Chat",
      active_tab: :chat,
      agents: agents,
      selected_agent: nil,
      messages: [],
      input: "",
      streaming: false,
      selected_model: "claude-sonnet-4-6",
      selected_provider: :anthropic,
      models: available_models()
    )}
  end

  @impl true
  def handle_event("select_agent", %{"id" => id}, socket) do
    messages = AgentProcess.get_messages(id)
    agent = AgentProcess.get_state(id)

    Phoenix.PubSub.subscribe(OpenClaw.PubSub, "agent:#{id}")

    {:noreply, assign(socket,
      selected_agent: agent,
      messages: messages
    )}
  end

  def handle_event("spawn_and_chat", _params, socket) do
    {:ok, id, _pid} = AgentSupervisor.spawn_agent(
      name: "Chat Agent",
      model: socket.assigns.selected_model,
      provider: socket.assigns.selected_provider
    )

    agent = AgentProcess.get_state(id)
    Phoenix.PubSub.subscribe(OpenClaw.PubSub, "agent:#{id}")

    {:noreply, assign(socket,
      selected_agent: agent,
      messages: [],
      agents: AgentSupervisor.list_agents()
    )}
  end

  def handle_event("send_message", %{"message" => message}, socket) when byte_size(message) > 0 do
    agent = socket.assigns.selected_agent

    if agent do
      # Add user message immediately
      user_msg = %{role: "user", content: message, timestamp: DateTime.utc_now()}
      messages = socket.assigns.messages ++ [user_msg]

      # Send to agent asynchronously
      AgentProcess.stream_message(agent.id, message, self())

      {:noreply, assign(socket, messages: messages, input: "", streaming: true)}
    else
      {:noreply, put_flash(socket, :error, "No agent selected. Spawn one first.")}
    end
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, input: message)}
  end

  def handle_event("select_model", %{"model" => model, "provider" => provider}, socket) do
    {:noreply, assign(socket,
      selected_model: model,
      selected_provider: String.to_existing_atom(provider)
    )}
  end

  def handle_event("clear_chat", _params, socket) do
    if socket.assigns.selected_agent do
      AgentProcess.clear_messages(socket.assigns.selected_agent.id)
    end
    {:noreply, assign(socket, messages: [])}
  end

  @impl true
  def handle_info({:agent_message, _id, message}, socket) do
    messages = socket.assigns.messages ++ [message]
    {:noreply, assign(socket, messages: messages, streaming: false)}
  end

  def handle_info({:stream_chunk, _id, chunk}, socket) do
    # Accumulate streaming chunks
    messages = socket.assigns.messages
    last = List.last(messages)

    messages = if last && last.role == "assistant_stream" do
      List.replace_at(messages, -1, %{last | content: last.content <> chunk})
    else
      messages ++ [%{role: "assistant_stream", content: chunk, timestamp: DateTime.utc_now()}]
    end

    {:noreply, assign(socket, messages: messages)}
  end

  def handle_info({:stream_error, _id, reason}, socket) do
    {:noreply, socket |> assign(streaming: false) |> put_flash(:error, "Stream error: #{inspect(reason)}")}
  end

  defp available_models do
    [
      %{provider: :anthropic, model: "claude-sonnet-4-6", label: "Claude Sonnet 4.6"},
      %{provider: :anthropic, model: "claude-opus-4-6", label: "Claude Opus 4.6"},
      %{provider: :anthropic, model: "claude-haiku-4-5", label: "Claude Haiku 4.5"},
      %{provider: :openai, model: "gpt-4.1", label: "GPT-4.1"},
      %{provider: :openai, model: "gpt-4.1-mini", label: "GPT-4.1 Mini"},
      %{provider: :google, model: "gemini-2.5-pro", label: "Gemini 2.5 Pro"},
      %{provider: :ollama, model: "llama3.1:8b", label: "Llama 3.1 8B (Local)"}
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-[calc(100vh-8rem)] gap-4">
      <!-- Sidebar: sessions -->
      <div class="w-64 bg-gray-900 border border-gray-800 rounded-xl flex flex-col shrink-0">
        <div class="p-4 border-b border-gray-800">
          <button phx-click="spawn_and_chat" class="w-full flex items-center justify-center gap-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium py-2.5 px-4 rounded-lg transition-colors">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
            New Chat
          </button>
        </div>

        <!-- Model selector -->
        <div class="p-3 border-b border-gray-800">
          <select
            phx-change="select_model"
            name="model_select"
            class="w-full bg-gray-800 border-gray-700 text-gray-300 text-xs rounded-lg focus:ring-emerald-500 focus:border-emerald-500"
          >
            <%= for m <- @models do %>
              <option
                value={"#{m.model}|#{m.provider}"}
                selected={m.model == @selected_model}
              >
                <%= m.label %>
              </option>
            <% end %>
          </select>
        </div>

        <!-- Agent list -->
        <div class="flex-1 overflow-y-auto p-2 space-y-1">
          <div
            :for={agent <- @agents}
            phx-click="select_agent"
            phx-value-id={agent.id}
            class={[
              "p-3 rounded-lg cursor-pointer transition-colors",
              @selected_agent && @selected_agent.id == agent.id && "bg-gray-800",
              !(@selected_agent && @selected_agent.id == agent.id) && "hover:bg-gray-800/50"
            ]}
          >
            <div class="flex items-center gap-2">
              <div class={[
                "w-2 h-2 rounded-full",
                agent.status == :running && "bg-emerald-500",
                agent.status != :running && "bg-gray-500"
              ]} />
              <p class="text-sm text-gray-300 truncate"><%= agent.name %></p>
            </div>
            <p class="text-xs text-gray-600 mt-1 truncate"><%= agent.model %></p>
          </div>
        </div>
      </div>

      <!-- Chat area -->
      <div class="flex-1 bg-gray-900 border border-gray-800 rounded-xl flex flex-col">
        <!-- Messages -->
        <div class="flex-1 overflow-y-auto p-6 space-y-4" id="chat-messages" phx-hook="ScrollBottom">
          <div :if={@messages == [] && @selected_agent} class="flex flex-col items-center justify-center h-full">
            <div class="w-16 h-16 bg-gradient-to-br from-emerald-500/20 to-cyan-500/20 rounded-2xl flex items-center justify-center mb-4">
              <svg class="w-8 h-8 text-emerald-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
                <path stroke-linecap="round" stroke-linejoin="round" d="M7.5 8.25h9m-9 3H12m-9.75 1.51c0 1.6 1.123 2.994 2.707 3.227 1.087.16 2.185.283 3.293.369V21l4.076-4.076a1.526 1.526 0 0 1 1.037-.443 48.282 48.282 0 0 0 5.68-.494c1.584-.233 2.707-1.626 2.707-3.228V6.741c0-1.602-1.123-2.995-2.707-3.228A48.394 48.394 0 0 0 12 3c-2.392 0-4.744.175-7.043.513C3.373 3.746 2.25 5.14 2.25 6.741v6.018Z" />
              </svg>
            </div>
            <p class="text-gray-400 text-sm">Start a conversation</p>
            <p class="text-gray-600 text-xs mt-1">Using <span class="text-emerald-400"><%= @selected_agent.model %></span></p>
          </div>

          <div :if={!@selected_agent} class="flex flex-col items-center justify-center h-full">
            <p class="text-gray-500 text-sm">Click "New Chat" to spawn an agent</p>
          </div>

          <div :for={msg <- @messages} class={[
            "flex",
            msg.role == "user" && "justify-end",
            msg.role != "user" && "justify-start"
          ]}>
            <div class={[
              "max-w-[70%] rounded-2xl px-4 py-3",
              msg.role == "user" && "bg-emerald-600 text-white",
              msg.role in ["assistant", "assistant_stream"] && "bg-gray-800 text-gray-200"
            ]}>
              <p class="text-sm whitespace-pre-wrap"><%= msg.content %></p>
              <p :if={msg[:tokens]} class="text-xs opacity-50 mt-1"><%= msg.tokens %> tokens</p>
            </div>
          </div>

          <div :if={@streaming} class="flex justify-start">
            <div class="bg-gray-800 rounded-2xl px-4 py-3">
              <div class="flex gap-1">
                <div class="w-2 h-2 bg-emerald-500 rounded-full animate-bounce" style="animation-delay: 0ms"></div>
                <div class="w-2 h-2 bg-emerald-500 rounded-full animate-bounce" style="animation-delay: 150ms"></div>
                <div class="w-2 h-2 bg-emerald-500 rounded-full animate-bounce" style="animation-delay: 300ms"></div>
              </div>
            </div>
          </div>
        </div>

        <!-- Input -->
        <div class="p-4 border-t border-gray-800">
          <form phx-submit="send_message" class="flex gap-3">
            <input
              type="text"
              name="message"
              value={@input}
              phx-change="update_input"
              placeholder={if @selected_agent, do: "Type a message...", else: "Spawn an agent first..."}
              disabled={!@selected_agent}
              class="flex-1 bg-gray-800 border-gray-700 text-gray-200 placeholder-gray-500 rounded-xl px-4 py-3 text-sm focus:ring-emerald-500 focus:border-emerald-500 disabled:opacity-50"
              autocomplete="off"
            />
            <button
              type="submit"
              disabled={!@selected_agent || @streaming}
              class="bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 disabled:cursor-not-allowed text-white px-5 py-3 rounded-xl transition-colors"
            >
              <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 12 3.269 3.125A59.769 59.769 0 0 1 21.485 12 59.768 59.768 0 0 1 3.27 20.875L5.999 12Zm0 0h7.5" />
              </svg>
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
