defmodule PhoenixSsg.ConfigTest do
  use ExUnit.Case, async: true

  alias PhoenixSsg.Config

  describe "load/1" do
    test "applies defaults and returns a struct" do
      env = [endpoint: SomeEndpoint, router: SomeRouter, base_url: "https://example.com"]

      assert {:ok, config} = Config.load(env)
      assert %Config{} = config
      assert config.endpoint == SomeEndpoint
      assert config.base_url == "https://example.com"
      assert config.output_dir == "priv/static_site"
      assert config.exclude == []
      assert config.extra_paths == nil
    end

    test "trims trailing slash from base_url" do
      env = [endpoint: E, router: R, base_url: "https://example.com/"]
      assert {:ok, %Config{base_url: "https://example.com"}} = Config.load(env)
    end

    test "errors when endpoint is missing" do
      assert {:error, msg} = Config.load(base_url: "https://example.com")
      assert msg =~ "endpoint"
    end

    test "errors when base_url is missing" do
      assert {:error, msg} = Config.load(endpoint: E, router: R)
      assert msg =~ "base_url"
    end

    test "infers router from endpoint module convention" do
      env = [
        endpoint: PhoenixSsg.TestSupport.Endpoint,
        base_url: "https://x"
      ]

      assert {:ok, %Config{router: PhoenixSsg.TestSupport.Router}} = Config.load(env)
    end

    test "errors when router cannot be inferred and is not provided" do
      env = [endpoint: NoSuchModule.Endpoint, base_url: "https://x"]
      assert {:error, msg} = Config.load(env)
      assert msg =~ "router"
    end

    test "validates extra_paths is an MFA tuple" do
      env = [endpoint: E, router: R, base_url: "https://x", extra_paths: :not_an_mfa]
      assert {:error, msg} = Config.load(env)
      assert msg =~ "extra_paths"
    end

    test "accepts a valid MFA tuple" do
      env = [endpoint: E, router: R, base_url: "https://x", extra_paths: {Mod, :fun, []}]
      assert {:ok, %Config{extra_paths: {Mod, :fun, []}}} = Config.load(env)
    end

    test "validates exclude is a list of strings" do
      env = [endpoint: E, router: R, base_url: "https://x", exclude: [:not_a_string]]
      assert {:error, msg} = Config.load(env)
      assert msg =~ "exclude"
    end
  end
end
