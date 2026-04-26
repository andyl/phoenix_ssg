---
title: Static Site Export
slug: static-site-export
branch: feat/static-site-export
date: 2026-04-25
source: _spec/designs/260425_Intro.md
status: draft
---

# Static Site Export

## Summary

Port the working static-site-generation setup from `$HOME/src/Web/smartworks`
into the `phoenix_ssg` library so any Phoenix app can keep Phoenix in dev
(Tidewave, Claude Code, click-to-edit, PhoenixDebugger) while shipping
production as plain static HTML to a CDN/Pages host.

The core deliverable is a `mix phoenix_ssg.export` task that renders every
exportable route through the user's `Endpoint`, writes `index.html` per path
under a configured output directory, copies `priv/static`, and emits a
`sitemap.xml`. Secondary deliverables wire route enumeration, dynamic-path
discovery via a user-supplied MFA, and an Igniter installer that scaffolds a
sitemap controller and config stubs.

## Motivation

The user has a working static blog at `smartworks` with a hand-written export
task. He wants to extract the reusable parts into a library so:

- new Phoenix blog/marketing sites can opt into static export with one install
- the export pipeline is consistent across his projects
- the library can grow opinions about what is/isn't exportable without polluting consuming apps
- deployment stays free (Cloudflare Pages / GitHub Pages / Netlify / S3) and edge-cached

`smartworks` is the reference implementation but is read-only for this work. `$HOME/src/Web/testapp` is available as a sandbox for prototyping.

## Goals

- Provide `mix phoenix_ssg.export` that produces a self-contained directory of static HTML + assets + sitemap, suitable for direct upload to a static host.
- Discover exportable paths from the consuming app's router (`Phoenix.Router.routes/1`), filtered to `:get` and non-dynamic paths.
- Allow users to declare dynamic paths (e.g. `/posts/:id`) via a config-level MFA: `extra_paths: {Module, :fun, args}` returning a list of concrete path strings.
- Allow users to exclude paths matching glob/literal patterns (e.g. `"/dev/*"`, `"/health"`).
- Render each path through `Phoenix.ConnTest` against the configured `Endpoint`, asserting a 200 response, and write the body to `<output_dir>/<path>/index.html` (with `/` → `index.html`).
- Copy compiled static assets from the consuming app's `priv/static` into the output directory.
- Emit `sitemap.xml` covering all rendered paths, prefixed with a configured `base_url`.
- Provide a `mix phoenix_ssg.install` Igniter task that adds config stubs, a `SitemapController` + route via `Igniter.Libs.Phoenix.add_scope/4`, and (optionally) a `robots.txt` controller.
- Treat Igniter as an optional dependency so non-Igniter consumers can still use the export task.

## Non-Goals

- AST-based exportability scanning. Per the design rationale, static template scanning is a leaky proxy for "this page can't be static." Lint-style detection is deferred to a follow-up feature and, when built, should be render-time anomaly detection (non-200 responses, `<form method="post">`, CSRF tokens, session-setting responses), not AST analysis.
- LiveView export semantics. The first cut targets server-rendered controller views + NimblePublisher-backed blog content, matching the smartworks shape.
- Authoring helpers for posts, tags, or blog contexts. Users bring their own `Blog`/`Post` modules; the library only consumes them via the `extra_paths` MFA.
- Hosting/deploy automation. CI integration is documented, not implemented.
- Migration tooling for non-Phoenix apps.

## Scope

### In scope

1. **`Mix.Tasks.PhoenixSsg.Export`** — main mix task; orchestrates render, write, asset copy, and sitemap emission.
2. **`PhoenixSsg.Exporter`** — render-and-write core; isolates the `Phoenix.ConnTest` dispatch so it can be unit tested.
3. **`PhoenixSsg.RouteDiscovery`** — enumerates `:get`, non-dynamic paths from the user's router and merges in the `extra_paths` MFA result and `exclude` filters.
4. **`PhoenixSsg.Sitemap`** — generates `sitemap.xml` from a list of paths and a base URL.
5. **`Mix.Tasks.PhoenixSsg.Install`** — Igniter task to scaffold config + sitemap controller/route. Optional dep on Igniter.
6. **Configuration surface** in `config/config.exs`:
   - `endpoint` — the consuming app's `Endpoint` module
   - `output_dir` — defaults to `priv/static_site`
   - `base_url` — used for sitemap and absolute links
   - `extra_paths` — `{Module, :fun, args}` returning `[String.t()]`
   - `exclude` — list of literal paths or simple globs to skip
7. **Tests** that exercise render, route discovery (with an in-test router fixture), sitemap output, and the Mix task end-to-end against a minimal Phoenix endpoint.
8. **Documentation** in `README.md` covering install, config, the `MIX_ENV=prod mix assets.deploy && MIX_ENV=prod mix phoenix_ssg.export` deploy recipe, and the `Phoenix.ConnTest`-not-test-only constraint.

### Out of scope (explicit)

- Lint task (`mix phoenix_ssg.lint`).
- Robots.txt scaffolding beyond optional flag in installer.
- LiveView-aware rendering or session-stub injection.
- Cache-busting or asset rewriting beyond what `assets.deploy` already produces.

## User Stories

1. **As a Phoenix dev**, I run `mix igniter.install phoenix_ssg`, accept the prompts, and end up with a config block, a `SitemapController` mapped to `/sitemap.xml`, and a working baseline so I can run `mix phoenix_ssg.export` immediately afterward.
2. **As a blog author**, I add `extra_paths: {MyApp.Blog, :all_post_paths, []}` to config, run the export task, and find one rendered `index.html` per post under `priv/static_site/posts/<id>/`.
3. **As a deployer**, I run `MIX_ENV=prod mix assets.deploy && MIX_ENV=prod mix phoenix_ssg.export` and upload `priv/static_site` to Cloudflare Pages; the site loads with digested CSS/JS and a valid sitemap.
4. **As a careful user**, I see a clear warning when my router has `/posts/:id` but no `extra_paths` MFA matches it — telling me which dynamic routes won't be rendered.
5. **As a non-Igniter user**, I can still add `phoenix_ssg` to deps without `igniter`, edit config by hand, and get a working export.

## Acceptance Criteria

- `mix phoenix_ssg.export` exits 0 against a minimal Phoenix app with at least one static route, writes `index.html` for each discovered + extra path, copies `priv/static` contents, and writes a `sitemap.xml` whose `<loc>` entries are `base_url <> path`.
- `/` is written as `<output_dir>/index.html` (not `<output_dir>//index.html`).
- A path like `/posts/foo` is written as `<output_dir>/posts/foo/index.html`.
- Non-200 responses during export fail the task with a clear error naming the offending path and status code.
- `Phoenix.Router.routes/1` is the source of truth for static path discovery; dynamic paths (`:` or `*` segments) are not auto-discovered and require `extra_paths`.
- `exclude` patterns are honored and reported in the task's summary output.
- `PhoenixSsg.Sitemap.generate/2` returns valid XML against the sitemap schema for an arbitrary list of paths.
- The Igniter installer adds the sitemap route via `Igniter.Libs.Phoenix.add_scope/4` and is gated on Igniter being present.
- Tests pass under `mix test` and cover: route discovery filtering, sitemap rendering, export of a fixture endpoint, and `extra_paths` merging.
- `README.md` documents the deploy recipe and the `Phoenix.ConnTest`-not-`only: :test` constraint.

## Dependencies and Constraints

- **`Phoenix.ConnTest` at runtime.** Consuming apps must not have `:phoenix` (or whatever brings in `ConnTest`) restricted to `only: :test`. This is documented and ideally surfaced as a startup check.
- **Igniter is optional.** The installer task should compile-skip or noop with a friendly message if `igniter` is absent from the consuming app.
- **NimblePublisher is not a dep of this library.** The smartworks reference uses it, but `phoenix_ssg` does not assume it — content sources are entirely the consumer's concern.
- **Conventional Commits + `git_ops`** for releases (per project CLAUDE.md). Commits on this branch must use `feat:` / `fix:` / `chore:` etc.
- **`commit_hook` local path dep** is wired in; expect commit-message validation locally.
- Reference implementation lives at `$HOME/src/Web/smartworks` and is **read-only** — copy ideas and code, do not edit. `$HOME/src/Web/testapp` is the sandbox for prototyping integration.

## Open Questions

1. **Asset copy ordering.** Should `priv/static` be copied before or after rendering? (Before is simpler; after lets render output potentially overwrite same-named files. Suggest: before, with a warning on collision.)
2. **Trailing slash policy.** Does the exporter emit `/posts/foo/index.html` only, or also a `/posts/foo.html` flat variant? (Suggest: directory-style only — matches Cloudflare/Netlify defaults.)
3. **Endpoint lifecycle.** Should the task start the endpoint itself (`Mix.Task.run("app.start")`) or assume the user does? (Suggest: start it, mirroring smartworks.)
4. **Concurrency.** Is render-loop parallelism worth it for a v1 export? (Suggest: serial first; revisit if export time becomes an issue.)
5. **Error reporting format.** Plain `Mix.shell().error` vs structured summary at end. (Suggest: per-path log + final summary line.)
6. **Installer scope detail.** Should the installer also add a `live_reload` pattern for `priv/posts/**/*.md`, or is that too NimblePublisher-specific? (Suggest: skip — out of scope.)

## References

- Design rationale and walkthrough: `_spec/designs/260425_Intro.md`
- Reference implementation (read-only): `$HOME/src/Web/smartworks`
- Sandbox for prototyping: `$HOME/src/Web/testapp`
- Project guidance: `CLAUDE.md` (target architecture, release/commit conventions, deps of note)
- Phoenix APIs: `Phoenix.Router.routes/1`, `Phoenix.ConnTest`, `Igniter.Libs.Phoenix.add_scope/4`
