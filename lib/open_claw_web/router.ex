defmodule OpenClawWeb.Router do
  use OpenClawWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {OpenClawWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", OpenClawWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/chat", ChatLive, :index
    live "/agents", AgentsLive, :index
    live "/terminal", TerminalLive, :index
    live "/analytics", AnalyticsLive, :index
    live "/skills", SkillsLive, :index
    live "/settings", SettingsLive, :index
  end

  scope "/api", OpenClawWeb do
    pipe_through :api

    # Future: REST API for external clients
  end
end
