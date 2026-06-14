defmodule AyumiWeb.PageController do
  use AyumiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
