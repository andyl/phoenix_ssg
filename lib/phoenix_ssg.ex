defmodule PhoenixSsg do
  @moduledoc """
  `phoenix_ssg` renders a Phoenix application to a static HTML site.

  Keep `Phoenix` in dev (Tidewave, Claude Code, click-to-edit, hot
  reload) while shipping production as plain static files to a CDN or
  Pages host.

  ## Usage

  Configure under `:phoenix_ssg`:

      config :phoenix_ssg,
        endpoint: MyAppWeb.Endpoint,
        base_url: "https://example.com",
        output_dir: "priv/static_site",
        extra_paths: {MyApp.Blog, :all_post_paths, []},
        exclude: ["/dev/*", "/health"]

  Then:

      MIX_ENV=prod mix assets.deploy
      MIX_ENV=prod mix phoenix_ssg.export

  See `Mix.Tasks.PhoenixSsg.Export` for CLI options and
  `PhoenixSsg.Config` for the full configuration surface.

  ## Runtime constraint

  The exporter calls `Phoenix.ConnTest` at mix-task time, so the
  consuming app must keep its `:phoenix` dependency outside `only:
  :test`.
  """

  @doc """
  Run the static-site export against the loaded `:phoenix_ssg`
  application env (or an explicit keyword override).

  Equivalent to running `mix phoenix_ssg.export` programmatically. The
  consuming application must already be started.
  """
  @spec export(keyword() | nil) :: {:ok, PhoenixSsg.Exporter.summary()} | {:error, term()}
  def export(env \\ nil) do
    case PhoenixSsg.Config.load(env) do
      {:ok, config} -> PhoenixSsg.Exporter.export(config)
      {:error, _} = err -> err
    end
  end
end
