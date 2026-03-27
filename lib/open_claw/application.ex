defmodule OpenClaw.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      OpenClawWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:open_claw, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: OpenClaw.PubSub},
      {Registry, keys: :unique, name: OpenClaw.AgentRegistry},
      OpenClaw.Billing.CostTracker,
      OpenClaw.Billing.BudgetEnforcer,
      OpenClaw.Skills.SkillRegistry,
      OpenClaw.Runtime.CustomProvider,
      OpenClaw.Runtime.Heartbeat,
      OpenClaw.Org.OrgChart,
      OpenClaw.Goals.GoalTracker,
      OpenClaw.Tickets.TicketSystem,
      OpenClaw.Governance,
      OpenClaw.Runtime.AgentSupervisor,
      OpenClawWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: OpenClaw.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    OpenClawWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
