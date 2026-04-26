defmodule PhoenixSsg.Exporter do
  @moduledoc """
  The render-and-write core of `phoenix_ssg`. Given a fully-resolved
  `%PhoenixSsg.Config{}`, clears + recreates the output directory,
  copies the consuming app's `priv/static`, dispatches each path
  through `Phoenix.ConnTest`, writes per the trailing-slash policy
  (`/` → `index.html`; `/x/y` → `x/y/index.html`), and writes
  `sitemap.xml`.

  Strict 200 check: a non-200 response raises `PhoenixSsg.RenderError`
  with the path, status, and a brief body excerpt. The mix task catches
  this for clean reporting.

  This module takes data, not config — the mix task builds the config
  via `PhoenixSsg.Config.load/1` and hands it in. Easier to test in
  isolation against a fixture endpoint.
  """

  alias PhoenixSsg.{Config, RouteDiscovery, Sitemap}

  defmodule RenderError do
    defexception [:path, :status, :body_excerpt]

    @impl true
    def message(%{path: path, status: status, body_excerpt: excerpt}) do
      "render of #{path} returned status #{status} (expected 200)\n\nbody excerpt:\n#{excerpt}"
    end
  end

  @type summary :: %{
          rendered: non_neg_integer(),
          assets_copied: boolean(),
          asset_collisions: [String.t()],
          sitemap: String.t(),
          output_dir: String.t(),
          paths: [String.t()]
        }

  @spec export(Config.t()) :: {:ok, summary()} | {:error, term()}
  def export(%Config{} = config) do
    with {:ok, paths} <- RouteDiscovery.all_paths(config) do
      output = config.output_dir
      File.rm_rf!(output)
      File.mkdir_p!(output)

      {assets_copied, copied_files} = copy_static(config, output)

      try do
        Enum.each(paths, fn path ->
          html = dispatch!(config.endpoint, path)
          write_html(output, path, html)
        end)

        sitemap_path = Path.join(output, "sitemap.xml")
        File.write!(sitemap_path, Sitemap.generate(paths, config.base_url))

        rendered_files = MapSet.new(Enum.map(paths, &rendered_file_for/1))

        collisions =
          copied_files |> MapSet.new() |> MapSet.intersection(rendered_files) |> MapSet.to_list()

        {:ok,
         %{
           rendered: length(paths),
           assets_copied: assets_copied,
           asset_collisions: collisions,
           sitemap: sitemap_path,
           output_dir: output,
           paths: paths
         }}
      rescue
        e in RenderError -> {:error, e}
      end
    end
  end

  defp dispatch!(endpoint, path) do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.dispatch(endpoint, :get, path)

    case conn.status do
      200 ->
        conn.resp_body

      status ->
        raise RenderError,
          path: path,
          status: status,
          body_excerpt: String.slice(to_string(conn.resp_body || ""), 0, 200)
    end
  end

  defp write_html(output, "/", html) do
    File.write!(Path.join(output, "index.html"), html)
  end

  defp write_html(output, path, html) do
    rel = String.trim_leading(path, "/")
    dir = Path.join(output, rel)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), html)
  end

  defp rendered_file_for("/"), do: "index.html"

  defp rendered_file_for(path),
    do: Path.join(String.trim_leading(path, "/"), "index.html")

  defp copy_static(%Config{endpoint: endpoint}, output) do
    otp_app = otp_app_for_endpoint(endpoint)
    src = Application.app_dir(otp_app, "priv/static")

    if File.dir?(src) do
      File.cp_r!(src, output)
      files = collect_relative_files(src)
      {true, files}
    else
      Mix.shell().info(
        "[phoenix_ssg] priv/static not found at #{src} — skipping asset copy. Run `mix assets.deploy` first."
      )

      {false, []}
    end
  end

  defp collect_relative_files(root) do
    root
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, root))
  end

  defp otp_app_for_endpoint(endpoint) do
    cond do
      function_exported?(endpoint, :config, 1) ->
        endpoint.config(:otp_app) || infer_otp_app(endpoint)

      true ->
        infer_otp_app(endpoint)
    end
  end

  defp infer_otp_app(endpoint) do
    Application.loaded_applications()
    |> Enum.find_value(fn {app, _, _} ->
      case :application.get_key(app, :modules) do
        {:ok, mods} -> if endpoint in mods, do: app, else: nil
        _ -> nil
      end
    end) ||
      raise ArgumentError,
            "could not determine the OTP app for endpoint #{inspect(endpoint)}; set it in your endpoint config"
  end
end
