defmodule PhoenixSsg.Sitemap do
  @moduledoc """
  Builds a `sitemap.xml` body from a list of paths and a base URL.

  Output is hand-rolled XML — no templating dep — with `&`, `<`, `>`,
  `'`, `"` escaped in `<loc>` content. Paths are sorted for deterministic
  output.
  """

  @doc """
  Returns the sitemap XML body for the given paths and base URL.
  """
  @spec generate([String.t()], String.t()) :: String.t()
  def generate(paths, base_url) do
    base = String.trim_trailing(base_url, "/")

    urls =
      paths
      |> Enum.sort()
      |> Enum.map_join("\n", fn path ->
        "  <url><loc>#{escape(base <> path)}</loc></url>"
      end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{urls}
    </urlset>
    """
  end

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
