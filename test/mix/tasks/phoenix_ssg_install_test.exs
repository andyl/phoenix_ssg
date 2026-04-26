defmodule Mix.Tasks.PhoenixSsg.InstallTest do
  use ExUnit.Case, async: true

  if Code.ensure_loaded?(Igniter.Test) do
    import Igniter.Test

    test "adds phoenix_ssg config keys" do
      [app_name: :test_app]
      |> phx_test_project()
      |> Igniter.compose_task("phoenix_ssg.install", [])
      |> assert_has_patch("config/config.exs", """
      + |  base_url: "https://example.com",
      """)
    end

    test "creates a SitemapController and adds the sitemap.xml route" do
      project =
        [app_name: :test_app]
        |> phx_test_project()
        |> Igniter.compose_task("phoenix_ssg.install", [])

      assert_creates(project, "lib/test_app_web/controllers/sitemap_controller.ex")

      assert_has_patch(project, "lib/test_app_web/router.ex", """
      + |    get("/sitemap.xml", SitemapController, :show)
      """)
    end
  else
    @tag :skip
    test "installer requires igniter (skipped)" do
      :ok
    end
  end
end
