defmodule PhoenixSsg.RouteDiscovery do
  @moduledoc """
  Enumerates exportable paths from the consuming app's `Phoenix.Router`,
  merges in user-supplied `extra_paths`, applies `exclude` filters, and
  surfaces warnings for dynamic routes that no extras plausibly cover.

  `Phoenix.Router.routes/1` is the source of truth: only `:get` routes
  with no `:` or `*` segments are auto-discovered. Dynamic routes are the
  user's job via the `extra_paths` MFA.
  """

  alias PhoenixSsg.Config

  @doc """
  Returns the list of static GET paths defined on the router.
  """
  @spec discoverable_paths(module()) :: [String.t()]
  def discoverable_paths(router) do
    router
    |> all_get_routes()
    |> Enum.reject(&dynamic_path?/1)
    |> Enum.uniq()
  end

  @doc """
  Returns the list of dynamic GET paths on the router. Used to drive the
  "uncovered dynamic route" warning.
  """
  @spec dynamic_paths(module()) :: [String.t()]
  def dynamic_paths(router) do
    router
    |> all_get_routes()
    |> Enum.filter(&dynamic_path?/1)
    |> Enum.uniq()
  end

  @doc """
  Returns the merged + filtered + deduped list of paths to render.
  """
  @spec all_paths(Config.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def all_paths(%Config{} = config) do
    static = discoverable_paths(config.router)

    with {:ok, extras} <- resolve_extras(config.extra_paths) do
      paths =
        (static ++ extras)
        |> Enum.uniq()
        |> Enum.reject(&excluded?(&1, config.exclude))
        |> Enum.sort()

      {:ok, paths}
    end
  end

  @doc """
  Returns warning strings for the given config (e.g. dynamic routes that
  no extras MFA appears to cover).
  """
  @spec warnings(Config.t()) :: [String.t()]
  def warnings(%Config{} = config) do
    dyn = dynamic_paths(config.router)

    case dyn do
      [] ->
        []

      paths ->
        extras =
          case resolve_extras(config.extra_paths) do
            {:ok, list} -> list
            _ -> []
          end

        Enum.flat_map(paths, fn dyn_path ->
          if uncovered?(dyn_path, extras) do
            [
              "Router has dynamic GET route #{dyn_path} but no extra_paths entry appears to cover it."
            ]
          else
            []
          end
        end)
    end
  end

  defp all_get_routes(router) do
    router.__routes__()
    |> Enum.filter(&(&1.verb == :get))
    |> Enum.map(& &1.path)
  end

  defp dynamic_path?(path), do: String.contains?(path, ":") or String.contains?(path, "*")

  defp resolve_extras(nil), do: {:ok, []}

  defp resolve_extras({m, f, a}) do
    result = apply(m, f, a)

    cond do
      not is_list(result) ->
        {:error, "extra_paths #{inspect({m, f, a})} returned non-list: #{inspect(result)}"}

      not Enum.all?(result, &valid_path?/1) ->
        {:error,
         "extra_paths #{inspect({m, f, a})} must return a list of strings starting with '/', got: #{inspect(result)}"}

      true ->
        {:ok, result}
    end
  end

  defp valid_path?(p) when is_binary(p), do: String.starts_with?(p, "/")
  defp valid_path?(_), do: false

  defp excluded?(path, patterns) do
    Enum.any?(patterns, fn pattern ->
      cond do
        String.ends_with?(pattern, "*") ->
          prefix = String.trim_trailing(pattern, "*")
          String.starts_with?(path, prefix)

        true ->
          path == pattern
      end
    end)
  end

  defp uncovered?(dyn_path, extras) do
    prefix = static_prefix(dyn_path)
    not Enum.any?(extras, &String.starts_with?(&1, prefix))
  end

  defp static_prefix(dyn_path) do
    dyn_path
    |> String.split("/")
    |> Enum.take_while(fn seg ->
      not (String.starts_with?(seg, ":") or String.starts_with?(seg, "*"))
    end)
    |> Enum.join("/")
  end
end
