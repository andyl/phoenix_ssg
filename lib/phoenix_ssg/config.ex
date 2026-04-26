defmodule PhoenixSsg.Config do
  @moduledoc """
  Loads, normalizes and validates `:phoenix_ssg` application env into a
  `%PhoenixSsg.Config{}` struct used by the rest of the library.

  Reads from `Application.get_all_env(:phoenix_ssg)` by default. Tests and
  the mix task may pass an explicit keyword list to `load/1`.
  """

  defstruct [
    :endpoint,
    :router,
    :base_url,
    :output_dir,
    :extra_paths,
    :exclude
  ]

  @type mfa_tuple :: {module(), atom(), [term()]}
  @type t :: %__MODULE__{
          endpoint: module(),
          router: module(),
          base_url: String.t(),
          output_dir: String.t(),
          extra_paths: mfa_tuple() | nil,
          exclude: [String.t()]
        }

  @defaults [
    output_dir: "priv/static_site",
    exclude: [],
    extra_paths: nil
  ]

  @spec load(keyword() | nil) :: {:ok, t()} | {:error, String.t()}
  def load(env \\ nil) do
    env = env || Application.get_all_env(:phoenix_ssg)
    merged = Keyword.merge(@defaults, env)

    with {:ok, endpoint} <- fetch(merged, :endpoint),
         {:ok, base_url} <- fetch(merged, :base_url),
         {:ok, extra_paths} <- validate_extra_paths(Keyword.get(merged, :extra_paths)),
         {:ok, exclude} <- validate_exclude(Keyword.get(merged, :exclude)),
         {:ok, router} <- resolve_router(merged, endpoint) do
      {:ok,
       %__MODULE__{
         endpoint: endpoint,
         router: router,
         base_url: String.trim_trailing(base_url, "/"),
         output_dir: Keyword.get(merged, :output_dir),
         extra_paths: extra_paths,
         exclude: exclude
       }}
    end
  end

  defp resolve_router(env, endpoint) do
    case Keyword.get(env, :router) do
      nil ->
        case infer_router(endpoint) do
          nil ->
            {:error,
             "could not infer router for endpoint #{inspect(endpoint)}; set :router under :phoenix_ssg"}

          mod ->
            {:ok, mod}
        end

      mod when is_atom(mod) ->
        {:ok, mod}

      other ->
        {:error, "router must be a module atom, got: #{inspect(other)}"}
    end
  end

  defp infer_router(endpoint) do
    base = endpoint |> Module.split() |> List.delete_at(-1) |> Module.concat()
    candidate = Module.concat(base, "Router")

    if Code.ensure_loaded?(candidate), do: candidate, else: nil
  end

  @spec load!(keyword() | nil) :: t()
  def load!(env \\ nil) do
    case load(env) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, "Invalid phoenix_ssg config: #{reason}"
    end
  end

  defp fetch(env, key) do
    case Keyword.get(env, key) do
      nil ->
        {:error, "missing required config key :#{key} under :phoenix_ssg"}

      value ->
        {:ok, value}
    end
  end

  defp validate_extra_paths(nil), do: {:ok, nil}

  defp validate_extra_paths({m, f, a}) when is_atom(m) and is_atom(f) and is_list(a),
    do: {:ok, {m, f, a}}

  defp validate_extra_paths(other),
    do: {:error, "extra_paths must be an {Module, :function, args} tuple, got: #{inspect(other)}"}

  defp validate_exclude(nil), do: {:ok, []}

  defp validate_exclude(list) when is_list(list) do
    if Enum.all?(list, &is_binary/1) do
      {:ok, list}
    else
      {:error, "exclude must be a list of strings, got: #{inspect(list)}"}
    end
  end

  defp validate_exclude(other),
    do: {:error, "exclude must be a list of strings, got: #{inspect(other)}"}
end
