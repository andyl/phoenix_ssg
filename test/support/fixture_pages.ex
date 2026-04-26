defmodule PhoenixSsg.TestSupport.Pages do
  @moduledoc false
  use Phoenix.Controller, formats: []
  import Plug.Conn

  def home(conn, _params) do
    body = "<!doctype html><html><body><h1>Home</h1></body></html>"

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, body)
  end

  def about(conn, _params) do
    body = "<!doctype html><html><body><h1>About</h1></body></html>"

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, body)
  end

  def post_show(conn, %{"id" => id}) do
    body = "<!doctype html><html><body><h1>Post #{id}</h1></body></html>"

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, body)
  end

  def boom(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(500, "<html><body>boom</body></html>")
  end

  def healthcheck(conn, _params) do
    send_resp(conn, 200, "ok")
  end
end
