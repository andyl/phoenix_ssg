defmodule PhoenixSsg.ExporterTest do
  use ExUnit.Case, async: false

  alias PhoenixSsg.{Config, Exporter}
  alias PhoenixSsg.TestSupport.{Endpoint, Router}

  defmodule Extras do
    def post_paths, do: ["/posts/foo", "/posts/bar"]
  end

  @moduletag :tmp_dir

  defp base_config(tmp_dir, opts \\ []) do
    %Config{
      endpoint: Endpoint,
      router: Router,
      base_url: "https://example.com",
      output_dir: tmp_dir,
      extra_paths: Keyword.get(opts, :extra_paths),
      exclude: Keyword.get(opts, :exclude, ["/boom", "/health", "/dev/*"])
    }
  end

  test "renders static + extra paths to index.html files", %{tmp_dir: tmp_dir} do
    config = base_config(tmp_dir, extra_paths: {Extras, :post_paths, []})

    assert {:ok, summary} = Exporter.export(config)
    assert summary.rendered == 4
    assert "/" in summary.paths
    assert "/about" in summary.paths
    assert "/posts/foo" in summary.paths

    assert File.exists?(Path.join(tmp_dir, "index.html"))
    assert File.read!(Path.join(tmp_dir, "index.html")) =~ "<h1>Home</h1>"
    assert File.exists?(Path.join(tmp_dir, "about/index.html"))
    assert File.exists?(Path.join(tmp_dir, "posts/foo/index.html"))
    assert File.read!(Path.join(tmp_dir, "posts/foo/index.html")) =~ "<h1>Post foo</h1>"
  end

  test "writes a sitemap covering all rendered paths", %{tmp_dir: tmp_dir} do
    config = base_config(tmp_dir)

    assert {:ok, summary} = Exporter.export(config)
    sitemap = File.read!(summary.sitemap)

    assert sitemap =~ "<loc>https://example.com/</loc>"
    assert sitemap =~ "<loc>https://example.com/about</loc>"
  end

  test "fails on non-200 responses with path + status in the error", %{tmp_dir: tmp_dir} do
    config = base_config(tmp_dir, exclude: ["/health", "/dev/*"])

    assert {:error, %Exporter.RenderError{} = err} = Exporter.export(config)
    assert err.path == "/boom"
    assert err.status == 500
    assert Exception.message(err) =~ "/boom"
    assert Exception.message(err) =~ "500"
  end

  test "copies priv/static when present", %{tmp_dir: tmp_dir} do
    config = base_config(tmp_dir)
    assert {:ok, _summary} = Exporter.export(config)
    assert File.exists?(Path.join(tmp_dir, "app.css"))
  end
end
