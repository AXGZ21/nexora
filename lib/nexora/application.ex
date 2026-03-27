defmodule Nexora.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      NexoraWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:nexora, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Nexora.PubSub},
      {Registry, keys: :unique, name: Nexora.AgentRegistry},
      Nexora.Runtime.ProviderConfig,
      Nexora.Billing.CostTracker,
      Nexora.Billing.BudgetEnforcer,
      Nexora.Skills.SkillRegistry,
      Nexora.Runtime.CustomProvider,
      Nexora.Runtime.Heartbeat,
      Nexora.Org.OrgChart,
      Nexora.Goals.GoalTracker,
      Nexora.Tickets.TicketSystem,
      Nexora.Governance,
      Nexora.Runtime.AgentSupervisor,
      NexoraWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Nexora.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    NexoraWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
