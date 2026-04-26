if Code.ensure_loaded?(Igniter.Mix.Task) do
  defmodule Mix.Tasks.PhoenixSsg.Install do
    @shortdoc "Install phoenix_ssg config + sitemap controller into a Phoenix app"

    @moduledoc """
    Igniter installer for `phoenix_ssg`.

    Adds:

    * a `:phoenix_ssg` config block to `config/config.exs`
    * `<AppWeb>.SitemapController` with a `show/2` action
    * a `/sitemap.xml` route via `Igniter.Libs.Phoenix.add_scope/4`

    ## Options

      * `--with-robots` — also generate a `RobotsController` stub
        served at `/robots.txt`
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :phoenix_ssg,
        schema: [with_robots: :boolean],
        defaults: [with_robots: false]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app = Igniter.Project.Application.app_name(igniter)
      web_module = Igniter.Libs.Phoenix.web_module(igniter)
      endpoint_module = Module.concat(web_module, "Endpoint")
      sitemap_controller = Module.concat(web_module, "SitemapController")

      igniter
      |> add_config(app, endpoint_module)
      |> add_sitemap_controller(sitemap_controller)
      |> add_sitemap_route(web_module)
      |> maybe_add_robots(igniter.args.options[:with_robots], web_module)
    end

    defp add_config(igniter, _app, endpoint_module) do
      igniter
      |> Igniter.Project.Config.configure(
        "config.exs",
        :phoenix_ssg,
        [:endpoint],
        endpoint_module
      )
      |> Igniter.Project.Config.configure(
        "config.exs",
        :phoenix_ssg,
        [:base_url],
        "https://example.com"
      )
      |> Igniter.Project.Config.configure(
        "config.exs",
        :phoenix_ssg,
        [:output_dir],
        "priv/static_site"
      )
    end

    defp add_sitemap_controller(igniter, controller) do
      contents = """
      defmodule #{inspect(controller)} do
        use Phoenix.Controller, formats: []

        def show(conn, _params) do
          {:ok, config} = PhoenixSsg.Config.load()
          {:ok, paths} = PhoenixSsg.RouteDiscovery.all_paths(config)
          xml = PhoenixSsg.Sitemap.generate(paths, config.base_url)

          conn
          |> Plug.Conn.put_resp_content_type("application/xml")
          |> Plug.Conn.send_resp(200, xml)
        end
      end
      """

      Igniter.Project.Module.create_module(igniter, controller, contents)
    end

    defp add_sitemap_route(igniter, web_module) do
      Igniter.Libs.Phoenix.add_scope(
        igniter,
        "/",
        """
        pipe_through :browser
        get "/sitemap.xml", SitemapController, :show
        """,
        arg2: web_module
      )
    end

    defp maybe_add_robots(igniter, true, web_module) do
      controller = Module.concat(web_module, "RobotsController")

      contents = """
      defmodule #{inspect(controller)} do
        use Phoenix.Controller, formats: []

        def show(conn, _params) do
          conn
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.send_resp(200, "User-agent: *\\nAllow: /\\n")
        end
      end
      """

      igniter
      |> Igniter.Project.Module.create_module(controller, contents)
      |> Igniter.Libs.Phoenix.add_scope(
        "/",
        """
        pipe_through :browser
        get "/robots.txt", RobotsController, :show
        """,
        arg2: web_module
      )
    end

    defp maybe_add_robots(igniter, _false, _web_module), do: igniter
  end
else
  defmodule Mix.Tasks.PhoenixSsg.Install do
    @shortdoc "Install phoenix_ssg (requires the optional :igniter dependency)"

    @moduledoc """
    `mix phoenix_ssg.install` requires the `:igniter` dependency. Add it to
    your project's `mix.exs`:

        {:igniter, "~> 0.6", only: [:dev]}

    then run `mix deps.get` and re-run this task. Or configure
    `phoenix_ssg` by hand — see the README for the minimum config block.
    """
    use Mix.Task

    @impl Mix.Task
    def run(_args) do
      Mix.shell().error("""
      mix phoenix_ssg.install requires the optional :igniter dependency.

      Add `{:igniter, "~> 0.6", only: [:dev]}` to your mix.exs deps and
      run `mix deps.get`, or configure phoenix_ssg by hand following the
      README.
      """)
    end
  end
end
