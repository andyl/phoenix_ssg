defmodule Mix.Tasks.PhoenixSsg.ExportTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup do
    on_exit(fn ->
      Application.delete_env(:phoenix_ssg, :endpoint)
      Application.delete_env(:phoenix_ssg, :router)
      Application.delete_env(:phoenix_ssg, :base_url)
      Application.delete_env(:phoenix_ssg, :exclude)
      Application.delete_env(:phoenix_ssg, :extra_paths)
      Application.delete_env(:phoenix_ssg, :output_dir)
    end)

    :ok
  end

  test "exports the configured endpoint into the given output dir", %{tmp_dir: tmp_dir} do
    Application.put_env(:phoenix_ssg, :endpoint, PhoenixSsg.TestSupport.Endpoint)
    Application.put_env(:phoenix_ssg, :router, PhoenixSsg.TestSupport.Router)
    Application.put_env(:phoenix_ssg, :base_url, "https://example.com")
    Application.put_env(:phoenix_ssg, :exclude, ["/boom", "/health", "/dev/*"])

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Task.rerun("phoenix_ssg.export", ["--output", tmp_dir])
      end)

    assert output =~ "rendered /"
    assert output =~ "rendered /about"
    assert output =~ "sitemap"
    assert File.exists?(Path.join(tmp_dir, "index.html"))
    assert File.exists?(Path.join(tmp_dir, "about/index.html"))
    assert File.exists?(Path.join(tmp_dir, "sitemap.xml"))
    assert File.read!(Path.join(tmp_dir, "sitemap.xml")) =~ "https://example.com/about"
  end

  test "honors --base-url override", %{tmp_dir: tmp_dir} do
    Application.put_env(:phoenix_ssg, :endpoint, PhoenixSsg.TestSupport.Endpoint)
    Application.put_env(:phoenix_ssg, :router, PhoenixSsg.TestSupport.Router)
    Application.put_env(:phoenix_ssg, :base_url, "https://wrong.test")
    Application.put_env(:phoenix_ssg, :exclude, ["/boom", "/health", "/dev/*", "/posts/:id"])

    ExUnit.CaptureIO.capture_io(fn ->
      Mix.Task.rerun(
        "phoenix_ssg.export",
        ["--output", tmp_dir, "--base-url", "https://right.test"]
      )
    end)

    assert File.read!(Path.join(tmp_dir, "sitemap.xml")) =~ "https://right.test/"
    refute File.read!(Path.join(tmp_dir, "sitemap.xml")) =~ "wrong.test"
  end
end
