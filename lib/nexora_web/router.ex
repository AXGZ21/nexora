defmodule NexoraWeb.Router do
  use NexoraWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NexoraWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", NexoraWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/chat", ChatLive, :index
    live "/agents", AgentsLive, :index
    live "/terminal", TerminalLive, :index
    live "/analytics", AnalyticsLive, :index
    live "/skills", SkillsLive, :index
    live "/settings", SettingsLive, :index
    live "/providers", ProvidersLive, :index
    live "/org", OrgChartLive, :index
    live "/goals", GoalsLive, :index
    live "/tickets", TicketsLive, :index
    live "/governance", GovernanceLive, :index
  end

  scope "/api", NexoraWeb do
    pipe_through :api

    # Future: REST API for external clients
  end
end
