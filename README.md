# PhoenixSsg

Render any Phoenix app to a static HTML site via `mix phoenix_ssg.export`.

Keep Phoenix in dev (Tidewave, Claude Code, click-to-edit, hot reload)
while shipping production as plain static files to a CDN or Pages host
(Cloudflare Pages, GitHub Pages, Netlify, S3, …).

See `_spec/features/260425_static-site-export.md` for the full spec and
`_spec/designs/260425_Intro.md` for the design rationale.

## Installation

Add `phoenix_ssg` to your deps:

```elixir
def deps do
  [
    {:phoenix_ssg, "~> 0.0.1"}
  ]
end
```

If you use [Igniter](https://hex.pm/packages/igniter), the installer
will scaffold config and a sitemap controller for you:

```bash
mix igniter.install phoenix_ssg
```

Otherwise, see the [Manual install](#manual-install) section below.

## Configuration

Under `:phoenix_ssg`:

```elixir
config :phoenix_ssg,
  endpoint: MyAppWeb.Endpoint,
  base_url: "https://example.com",
  output_dir: "priv/static_site",
  # extras for routes the router cannot enumerate (dynamic shows):
  extra_paths: {MyApp.Blog, :all_post_paths, []},
  # paths to skip:
  exclude: ["/dev/*", "/health"]
```

| Key | Required | Default | Notes |
| --- | --- | --- | --- |
| `:endpoint` | yes | — | The Phoenix endpoint to render against. |
| `:base_url` | yes | — | Used as the prefix in `sitemap.xml`. |
| `:router` | no | inferred from endpoint | e.g. `MyAppWeb.Endpoint` → `MyAppWeb.Router`. Set explicitly if your router lives elsewhere. |
| `:output_dir` | no | `"priv/static_site"` | Cleared and recreated on every export. |
| `:extra_paths` | no | `nil` | `{Module, :function, args}` returning a list of `String.t()` paths starting with `"/"`. |
| `:exclude` | no | `[]` | Literal paths or trailing-`*` glob patterns (e.g. `"/dev/*"`). |

## Deploy recipe

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix phoenix_ssg.export
# upload priv/static_site/ to your static host
```

The two steps are intentionally separate — `phoenix_ssg.export` does
not run `assets.deploy` for you.

### CLI overrides

```bash
mix phoenix_ssg.export --output build/site --base-url https://staging.example.com
```

## Important runtime constraint

`phoenix_ssg` calls `Phoenix.ConnTest` at mix-task time. That means the
consuming app's `:phoenix` dependency **must not be `only: :test`**:

```elixir
# good
{:phoenix, "~> 1.7"}

# breaks the export task
{:phoenix, "~> 1.7", only: :test}
```

If `:phoenix` is restricted to `:test`, the export task will fail to
load `Phoenix.ConnTest` outside of `mix test`.

## What gets exported

* **Static GET routes** discovered from `Phoenix.Router.routes/1`,
  filtered to paths that contain no `:` or `*` segments.
* **Dynamic GET routes** — only those covered by your `:extra_paths`
  MFA. The task warns if your router has `/posts/:id` but no extras
  entry plausibly covers it.
* **`priv/static`** — copied into the output directory. If a rendered
  HTML path collides with a copied asset filename, the render wins and
  a warning is logged.
* **`sitemap.xml`** — `base_url <> path` for every rendered page.

URLs are written directory-style: `/` → `index.html`, `/about` →
`about/index.html`. This matches the defaults of Cloudflare Pages,
Netlify and GitHub Pages.

## Strict failure on non-200

Any path that returns anything other than HTTP 200 fails the task with
the path, status, and a body excerpt. Silent skipping is how a broken
site ships.

## Manual install

Without Igniter, copy the config block above into `config/config.exs`
and (optionally) add a sitemap route + controller to your app:

```elixir
# lib/my_app_web/controllers/sitemap_controller.ex
defmodule MyAppWeb.SitemapController do
  use Phoenix.Controller, formats: []

  def show(conn, _params) do
    {:ok, config} = PhoenixSsg.Config.load()
    {:ok, paths} = PhoenixSsg.RouteDiscovery.all_paths(config)
    xml = PhoenixSsg.Sitemap.generate(paths, config.base_url)

    conn
    |> Plug.Conn.put_resp_content_type("application/xml")
    |> Plug.Conn.send_resp(200, xml)
  end
end
```

```elixir
# lib/my_app_web/router.ex
scope "/", MyAppWeb do
  pipe_through :browser
  get "/sitemap.xml", SitemapController, :show
end
```

## Hosts

`priv/static_site/` is plain HTML + assets. Any of the following work
without further configuration:

* Cloudflare Pages
* GitHub Pages
* Netlify
* AWS S3 + CloudFront
* Any static-file webserver

## Status

Early-stage. v0.0.1. The export pipeline is migrated from a working
implementation at `$HOME/src/Web/smartworks`.
