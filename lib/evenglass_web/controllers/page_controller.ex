defmodule EvenglassWeb.PageController do
  use EvenglassWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
