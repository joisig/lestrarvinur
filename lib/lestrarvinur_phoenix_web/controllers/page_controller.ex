defmodule LestrarvinurPhoenixWeb.PageController do
  use LestrarvinurPhoenixWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
