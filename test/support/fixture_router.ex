defmodule PhoenixSsg.TestSupport.Router do
  @moduledoc false
  use Phoenix.Router

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  scope "/" do
    pipe_through(:browser)

    get("/", PhoenixSsg.TestSupport.Pages, :home)
    get("/about", PhoenixSsg.TestSupport.Pages, :about)
    get("/posts/:id", PhoenixSsg.TestSupport.Pages, :post_show)
    get("/boom", PhoenixSsg.TestSupport.Pages, :boom)
    get("/health", PhoenixSsg.TestSupport.Pages, :healthcheck)
    get("/dev/dashboard", PhoenixSsg.TestSupport.Pages, :healthcheck)
  end
end
