defmodule Nexora.Skills.SkillRegistry do
  @moduledoc """
  Manages installed skills (extensions) for agents.
  Skills are stored in-memory and can be loaded from disk.
  """
  use GenServer

  defstruct skills: %{}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def list_skills do
    GenServer.call(__MODULE__, :list_skills)
  end

  def get_skill(id) do
    GenServer.call(__MODULE__, {:get_skill, id})
  end

  def install_skill(skill) do
    GenServer.call(__MODULE__, {:install_skill, skill})
  end

  def uninstall_skill(id) do
    GenServer.call(__MODULE__, {:uninstall_skill, id})
  end

  # --- Server ---

  @impl true
  def init(_) do
    skills = %{
      "web-search" => %{
        id: "web-search",
        name: "Web Search",
        description: "Search the web using multiple engines",
        version: "1.0.0",
        author: "Nexora",
        installed: true,
        enabled: true
      },
      "code-exec" => %{
        id: "code-exec",
        name: "Code Execution",
        description: "Execute code in sandboxed environments",
        version: "1.0.0",
        author: "Nexora",
        installed: true,
        enabled: true
      },
      "file-manager" => %{
        id: "file-manager",
        name: "File Manager",
        description: "Read, write, and manage files",
        version: "1.0.0",
        author: "Nexora",
        installed: true,
        enabled: true
      },
      "browser" => %{
        id: "browser",
        name: "Browser Control",
        description: "Control a headless browser for web automation",
        version: "1.0.0",
        author: "Nexora",
        installed: true,
        enabled: true
      }
    }

    {:ok, %__MODULE__{skills: skills}}
  end

  @impl true
  def handle_call(:list_skills, _from, state) do
    {:reply, Map.values(state.skills), state}
  end

  def handle_call({:get_skill, id}, _from, state) do
    {:reply, Map.get(state.skills, id), state}
  end

  def handle_call({:install_skill, skill}, _from, state) do
    skills = Map.put(state.skills, skill.id, skill)
    {:reply, :ok, %{state | skills: skills}}
  end

  def handle_call({:uninstall_skill, id}, _from, state) do
    skills = Map.delete(state.skills, id)
    {:reply, :ok, %{state | skills: skills}}
  end
end
