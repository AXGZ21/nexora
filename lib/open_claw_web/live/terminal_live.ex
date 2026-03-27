defmodule OpenClawWeb.TerminalLive do
  use OpenClawWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      page_title: "Terminal",
      active_tab: :terminal,
      history: [
        %{type: :system, content: "OpenClaw Terminal v0.1.0"},
        %{type: :system, content: "Elixir #{System.version()} / OTP #{:erlang.system_info(:otp_release)}"},
        %{type: :system, content: "Type a command and press Enter. Use 'help' for available commands."},
        %{type: :system, content: ""}
      ],
      input: "",
      cwd: File.cwd!()
    )}
  end

  @impl true
  def handle_event("execute", %{"command" => command}, socket) when byte_size(command) > 0 do
    prompt_line = %{type: :prompt, content: "#{socket.assigns.cwd}$ #{command}"}

    {output, new_cwd} = execute_command(command, socket.assigns.cwd)

    output_lines = String.split(output, "\n")
    |> Enum.map(fn line -> %{type: :output, content: line} end)

    history = socket.assigns.history ++ [prompt_line] ++ output_lines

    {:noreply, assign(socket, history: history, input: "", cwd: new_cwd)}
  end

  def handle_event("execute", _params, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"command" => command}, socket) do
    {:noreply, assign(socket, input: command)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, history: [])}
  end

  defp execute_command("help", cwd) do
    output = """
    Available commands:
      help          - Show this help message
      clear         - Clear terminal
      ls [path]     - List files
      pwd           - Print working directory
      cat <file>    - Display file contents
      cd <dir>      - Change directory
      echo <text>   - Echo text
      agents        - List running agents
      system        - Show system info
      mix <cmd>     - Run mix command
      elixir <expr> - Evaluate Elixir expression
    """
    {String.trim(output), cwd}
  end

  defp execute_command("clear", cwd), do: {"", cwd}

  defp execute_command("pwd", cwd), do: {cwd, cwd}

  defp execute_command("agents", cwd) do
    agents = OpenClaw.Runtime.AgentSupervisor.list_agents()
    if agents == [] do
      {"No agents running.", cwd}
    else
      lines = Enum.map(agents, fn a ->
        status = case a.status do
          :running -> "[RUNNING]"
          :paused -> "[PAUSED] "
          _ -> "[STOPPED]"
        end
        "  #{status} #{a.name} (#{a.model}) - #{a.message_count} msgs, $#{Float.round(a.total_cost, 4)}"
      end)
      {Enum.join(["Agents:" | lines], "\n"), cwd}
    end
  end

  defp execute_command("system", cwd) do
    info = """
    System Information:
      Elixir:      #{System.version()}
      OTP:         #{:erlang.system_info(:otp_release)}
      Schedulers:  #{:erlang.system_info(:schedulers_online)}
      Processes:   #{:erlang.system_info(:process_count)}
      Memory:      #{Float.round(:erlang.memory(:total) / 1_048_576, 1)} MB
      Atoms:       #{:erlang.system_info(:atom_count)}
      Ports:       #{length(:erlang.ports())}
    """
    {String.trim(info), cwd}
  end

  defp execute_command("cd " <> dir, cwd) do
    target = Path.expand(dir, cwd)
    if File.dir?(target) do
      {"", target}
    else
      {"cd: no such directory: #{dir}", cwd}
    end
  end

  defp execute_command("ls" <> rest, cwd) do
    target = case String.trim(rest) do
      "" -> cwd
      path -> Path.expand(path, cwd)
    end

    case File.ls(target) do
      {:ok, files} ->
        sorted = Enum.sort(files)
        {Enum.join(sorted, "  "), cwd}
      {:error, reason} ->
        {"ls: #{reason}", cwd}
    end
  end

  defp execute_command("cat " <> file, cwd) do
    path = Path.expand(String.trim(file), cwd)
    case File.read(path) do
      {:ok, content} -> {content, cwd}
      {:error, reason} -> {"cat: #{reason}: #{file}", cwd}
    end
  end

  defp execute_command("echo " <> text, cwd), do: {text, cwd}

  defp execute_command(cmd, cwd) do
    try do
      case System.cmd("sh", ["-c", cmd], cd: cwd, stderr_to_stdout: true) do
        {output, 0} -> {String.trim(output), cwd}
        {output, code} -> {"Exit code #{code}: #{String.trim(output)}", cwd}
      end
    rescue
      e -> {"Error: #{Exception.message(e)}", cwd}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-[calc(100vh-8rem)] flex flex-col">
      <div class="bg-gray-900 border border-gray-800 rounded-xl flex-1 flex flex-col overflow-hidden">
        <!-- Terminal Header -->
        <div class="flex items-center justify-between px-4 py-2.5 border-b border-gray-800 bg-gray-900/80">
          <div class="flex items-center gap-3">
            <div class="flex gap-1.5">
              <div class="w-3 h-3 rounded-full bg-red-500/80"></div>
              <div class="w-3 h-3 rounded-full bg-amber-500/80"></div>
              <div class="w-3 h-3 rounded-full bg-emerald-500/80"></div>
            </div>
            <span class="text-xs text-gray-500 font-mono">openclaw ~ terminal</span>
          </div>
          <div class="flex items-center gap-2">
            <button phx-click="clear" class="text-xs text-gray-500 hover:text-gray-300 px-2 py-1 rounded hover:bg-gray-800 transition-colors">
              Clear
            </button>
          </div>
        </div>

        <!-- Terminal Output -->
        <div class="flex-1 overflow-y-auto p-4 font-mono text-sm" id="terminal-output" phx-hook="ScrollBottom">
          <div :for={line <- @history} class={[
            "leading-6",
            line.type == :system && "text-gray-500",
            line.type == :prompt && "text-emerald-400",
            line.type == :output && "text-gray-300"
          ]}>
            <pre class="whitespace-pre-wrap"><%= line.content %></pre>
          </div>
        </div>

        <!-- Terminal Input -->
        <div class="border-t border-gray-800 px-4 py-3 flex items-center gap-2">
          <span class="text-emerald-400 font-mono text-sm shrink-0"><%= Path.basename(@cwd) %>$</span>
          <form phx-submit="execute" class="flex-1">
            <input
              type="text"
              name="command"
              value={@input}
              phx-change="update_input"
              class="w-full bg-transparent border-0 text-gray-200 font-mono text-sm focus:ring-0 p-0 placeholder-gray-600"
              placeholder="Enter command..."
              autocomplete="off"
              autofocus
            />
          </form>
        </div>
      </div>
    </div>
    """
  end
end
