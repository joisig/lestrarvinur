defmodule LestrarvinurPhoenixWeb.Router do
  use LestrarvinurPhoenixWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LestrarvinurPhoenixWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LestrarvinurPhoenixWeb do
    pipe_through :browser

    live "/", AuthLive
    live "/dashboard", DashboardLive
    live "/game", GameLive
    live "/admin", AdminLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", LestrarvinurPhoenixWeb do
  #   pipe_through :api
  # end
end
