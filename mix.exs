defmodule PhoenixSsg.MixProject do
  use Mix.Project

  @version "0.0.1"
  @source_url "https://github.com/andyl/phoenix_ssg"

  def project do
    [
      app: :phoenix_ssg,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:git_ops, "~> 2.0", only: [:dev], runtime: false},
      {:igniter, "~> 0.6", optional: true},
      {:commit_hook, path: "/home/aleak/src/Tool/commit_hook"},
      {:phoenix, "~> 1.7", only: :test},
      {:plug_cowboy, "~> 2.7", only: :test}
    ]
  end

  defp description do
    "Render any Phoenix app to static HTML via mix phoenix_ssg.export."
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
