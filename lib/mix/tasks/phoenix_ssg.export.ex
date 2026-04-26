defmodule Mix.Tasks.PhoenixSsg.Export do
  @shortdoc "Export the configured Phoenix app to a static HTML site"

  @moduledoc """
  Render every exportable route in the consuming Phoenix app to static
  HTML, copy `priv/static`, and emit `sitemap.xml`.

  ## Usage

      mix phoenix_ssg.export

      # production-shaped run:
      MIX_ENV=prod mix assets.deploy
      MIX_ENV=prod mix phoenix_ssg.export

  ## Options

    * `--output DIR` — override the configured `:output_dir`
    * `--base-url URL` — override the configured `:base_url`

  ## Configuration

  See `PhoenixSsg.Config`. Minimum required keys under `:phoenix_ssg`:

      config :phoenix_ssg,
        endpoint: MyAppWeb.Endpoint,
        base_url: "https://example.com"

  Optional: `output_dir`, `extra_paths` (an `{M, F, A}` MFA returning
  a list of path strings), and `exclude` (literal paths or trailing-`*`
  prefix patterns).
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [output: :string, base_url: :string]
      )

    case PhoenixSsg.Config.load() do
      {:ok, config} ->
        config = apply_overrides(config, opts)

        config
        |> PhoenixSsg.RouteDiscovery.warnings()
        |> Enum.each(&Mix.shell().info("[phoenix_ssg] WARNING: #{&1}"))

        case PhoenixSsg.Exporter.export(config) do
          {:ok, summary} ->
            print_summary(summary)

          {:error, %PhoenixSsg.Exporter.RenderError{} = err} ->
            Mix.raise(Exception.message(err))

          {:error, reason} ->
            Mix.raise("phoenix_ssg export failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        Mix.raise(reason)
    end
  end

  defp apply_overrides(config, opts) do
    config
    |> maybe_put(:output_dir, opts[:output])
    |> maybe_put(:base_url, opts[:base_url] && String.trim_trailing(opts[:base_url], "/"))
  end

  defp maybe_put(config, _key, nil), do: config
  defp maybe_put(config, key, value), do: Map.put(config, key, value)

  defp print_summary(%{
         rendered: n,
         sitemap: sitemap,
         output_dir: out,
         asset_collisions: collisions,
         paths: paths
       }) do
    Enum.each(paths, &Mix.shell().info("[phoenix_ssg] rendered #{&1}"))

    Enum.each(collisions, fn file ->
      Mix.shell().info("[phoenix_ssg] WARNING: rendered #{file} overwrote a copied static asset")
    end)

    Mix.shell().info("[phoenix_ssg] #{n} rendered, sitemap → #{sitemap}, output → #{out}")
  end
end
