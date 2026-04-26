defmodule PhoenixSsg.RouteDiscoveryTest do
  use ExUnit.Case, async: true

  alias PhoenixSsg.{Config, RouteDiscovery}
  alias PhoenixSsg.TestSupport.{Endpoint, Router}

  defmodule Extras do
    def post_paths, do: ["/posts/foo", "/posts/bar"]
    def bad_non_list, do: :nope
    def bad_no_slash, do: ["foo"]
  end

  describe "discoverable_paths/1" do
    test "returns only static GET paths" do
      paths = RouteDiscovery.discoverable_paths(Router)

      assert "/" in paths
      assert "/about" in paths
      assert "/health" in paths
      refute Enum.any?(paths, &String.contains?(&1, ":"))
    end
  end

  describe "dynamic_paths/1" do
    test "returns paths with dynamic segments" do
      paths = RouteDiscovery.dynamic_paths(Router)
      assert "/posts/:id" in paths
    end
  end

  describe "all_paths/1" do
    test "merges router paths with extras and dedupes/sorts" do
      config = %Config{
        endpoint: Endpoint,
        router: Router,
        base_url: "https://x",
        output_dir: "tmp",
        extra_paths: {Extras, :post_paths, []},
        exclude: []
      }

      assert {:ok, paths} = RouteDiscovery.all_paths(config)
      assert "/" in paths
      assert "/posts/foo" in paths
      assert "/posts/bar" in paths
      assert paths == Enum.sort(paths)
      assert paths == Enum.uniq(paths)
    end

    test "applies literal exclude" do
      config = %Config{
        endpoint: Endpoint,
        router: Router,
        base_url: "https://x",
        output_dir: "tmp",
        extra_paths: nil,
        exclude: ["/health"]
      }

      assert {:ok, paths} = RouteDiscovery.all_paths(config)
      refute "/health" in paths
    end

    test "applies trailing-* glob exclude" do
      config = %Config{
        endpoint: Endpoint,
        router: Router,
        base_url: "https://x",
        output_dir: "tmp",
        extra_paths: nil,
        exclude: ["/dev/*"]
      }

      assert {:ok, paths} = RouteDiscovery.all_paths(config)
      refute "/dev/dashboard" in paths
    end

    test "errors when extra_paths returns a non-list" do
      config = %Config{
        endpoint: Endpoint,
        router: Router,
        base_url: "https://x",
        output_dir: "tmp",
        extra_paths: {Extras, :bad_non_list, []},
        exclude: []
      }

      assert {:error, msg} = RouteDiscovery.all_paths(config)
      assert msg =~ "non-list"
    end

    test "errors when extra_paths returns paths without leading slash" do
      config = %Config{
        endpoint: Endpoint,
        router: Router,
        base_url: "https://x",
        output_dir: "tmp",
        extra_paths: {Extras, :bad_no_slash, []},
        exclude: []
      }

      assert {:error, msg} = RouteDiscovery.all_paths(config)
      assert msg =~ "starting with"
    end
  end

  describe "warnings/1" do
    test "warns when a dynamic route has no plausible extras coverage" do
      config = %Config{
        endpoint: Endpoint,
        router: Router,
        base_url: "https://x",
        output_dir: "tmp",
        extra_paths: nil,
        exclude: []
      }

      warnings = RouteDiscovery.warnings(config)
      assert Enum.any?(warnings, &(&1 =~ "/posts/:id"))
    end

    test "no warning when extras cover the dynamic route" do
      config = %Config{
        endpoint: Endpoint,
        router: Router,
        base_url: "https://x",
        output_dir: "tmp",
        extra_paths: {Extras, :post_paths, []},
        exclude: []
      }

      warnings = RouteDiscovery.warnings(config)
      refute Enum.any?(warnings, &(&1 =~ "/posts/:id"))
    end
  end
end
