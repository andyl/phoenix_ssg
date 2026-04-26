# Implementation Plan: Static Site Export

**Spec:** `_spec/features/260425_static-site-export.md`
**Generated:** 2026-04-25

---

## Goal

Port the smartworks SSG pipeline into the `phoenix_ssg` library so any Phoenix
app can render its routes to static HTML via `mix phoenix_ssg.export`, with
router-driven discovery, an MFA hook for dynamic paths, sitemap emission, and
an optional Igniter installer.

## Scope

### In scope

- `Mix.Tasks.PhoenixSsg.Export` — orchestrating mix task
- `PhoenixSsg.Exporter` — render-and-write core (testable in isolation)
- `PhoenixSsg.RouteDiscovery` — router enumeration + extras + excludes
- `PhoenixSsg.Sitemap` — XML generation
- `PhoenixSsg.Config` — read/normalize config with sensible defaults and validation
- `Mix.Tasks.PhoenixSsg.Install` — Igniter installer (config stubs, sitemap controller + route)
- Test fixture endpoint/router for end-to-end coverage of the export task
- README updated with install/config/deploy recipe and the `Phoenix.ConnTest`-not-`only: :test` constraint

### Out of scope

- `mix phoenix_ssg.lint` (deferred follow-up; render-time anomaly detection, not AST scanning)
- LiveView-specific export semantics
- Robots.txt scaffolding beyond an installer flag stub
- NimblePublisher integration helpers (consumers bring their own content modules)
- CI/deploy automation
- Asset rewriting beyond what `mix assets.deploy` already produces

## Architecture & Design Decisions

**Library, not framework.** `phoenix_ssg` consumes the user's `Endpoint` + router and runs at mix-task time. It owns no runtime supervision tree and adds no app boot behavior in the consuming app.

**`Phoenix.ConnTest` at runtime.** Mirrors smartworks. Documented constraint: consumer's `:phoenix` dep must not be `only: :test`. Library does not depend on `:phoenix` itself — it calls `Phoenix.ConnTest` reflectively, and the consuming app brings Phoenix.

**Config-driven, not callback-driven.** All knobs live under `:phoenix_ssg` application env: `endpoint`, `output_dir`, `base_url`, `extra_paths` (`{M, F, A}`), `exclude` (list of literal paths or `String.contains?`-style globs with trailing `*`). One module, `PhoenixSsg.Config`, normalizes and validates. Config errors surface as task-level failures with actionable messages, not crashes deep in render.

**Router introspection via `Phoenix.Router.routes/1`.** Filter to `verb == :get`, drop dynamic segments (`:` or `*`). Dynamic routes are the user's job via `extra_paths`. We surface a warning when the router has dynamic GET routes that no `extra_paths` entry plausibly covers (heuristic: prefix match against returned paths).

**Exporter takes data, not config.** `PhoenixSsg.Exporter.export(opts)` accepts a fully-resolved struct/keyword. The mix task builds it from `Config`. This keeps the core pure-ish and easy to unit-test against a fixture endpoint without mucking with `Application.put_env`.

**Serial render in v1.** Simpler error handling and deterministic logs. Concurrency is a future optimization gated on real-world export times.

**Asset copy first, render writes second.** If a rendered path collides with a static asset filename, the render wins (later write). Log a warning on collision.

**Trailing-slash policy: directory-style only.** `/` → `<out>/index.html`; `/x/y` → `<out>/x/y/index.html`. Matches Cloudflare/Netlify/GitHub Pages defaults.

**Endpoint lifecycle: task starts the app.** `Mix.Task.run("app.start")` — matches smartworks. Saves users one footgun.

**Igniter is a soft dep.** `optional: true` (already in `mix.exs`). `Mix.Tasks.PhoenixSsg.Install` wraps `use Igniter.Mix.Task` behind a `Code.ensure_loaded?(Igniter.Mix.Task)` guard so the module compiles even when igniter is absent; if invoked without igniter it prints a friendly message and exits cleanly.

**Strict failure on non-200.** Render returning anything other than 200 fails the task with `path` + `status` + brief body excerpt. No silent skipping — silent skipping is how a broken site ships.

**Sitemap emits raw XML, not via a templating dep.** Small enough to hand-build; avoids dragging in a dep just to escape five characters. Use `Plug.HTML.html_escape/1` (already transitively present via Phoenix in consumers) — or a tiny local escape — for `<loc>` content.

## Implementation Steps

1. **Bootstrap the public API module**
   - Files: `lib/phoenix_ssg.ex`
   - Replace the `hello/0` placeholder with a thin facade: `PhoenixSsg.export/1` delegating to `PhoenixSsg.Exporter.export/1`, plus `@moduledoc` describing the library.

2. **Add `PhoenixSsg.Config`**
   - Files: `lib/phoenix_ssg/config.ex` (new)
   - Read `Application.get_all_env(:phoenix_ssg)`, merge with defaults (`output_dir: "priv/static_site"`, `exclude: []`, `extra_paths: nil`), validate required keys (`endpoint`, `base_url`), expand the `extra_paths` MFA on demand. Return a `%PhoenixSsg.Config{}` struct or `{:error, reason}`.

3. **Add `PhoenixSsg.RouteDiscovery`**
   - Files: `lib/phoenix_ssg/route_discovery.ex` (new)
   - `discoverable_paths(router)` — calls `router.__routes__()`, filters `verb == :get`, drops paths containing `:` or `*`.
   - `dynamic_paths(router)` — returns the dropped dynamic GET paths (used for the "uncovered dynamic route" warning).
   - `all_paths(config)` — merges discovered + `extra_paths` MFA result, applies `exclude` filter (literal match + trailing-`*` prefix match), dedupes, returns `{:ok, [path]}` or `{:error, reason}`.
   - `warnings(config)` — returns warning strings (e.g. dynamic routes with no plausible extras coverage).

4. **Add `PhoenixSsg.Sitemap`**
   - Files: `lib/phoenix_ssg/sitemap.ex` (new)
   - `generate(paths, base_url)` returns the XML string. Escape `&`, `<`, `>` in the joined URL. Stable ordering for deterministic output.

5. **Add `PhoenixSsg.Exporter`**
   - Files: `lib/phoenix_ssg/exporter.ex` (new)
   - `export(config)` — clears + recreates `output_dir`, copies `priv/static` from the consuming app (`Application.app_dir/2` keyed off `endpoint`'s OTP app), iterates paths, dispatches each via `Phoenix.ConnTest`, writes per the trailing-slash policy, writes `sitemap.xml`, returns `{:ok, summary}` or `{:error, reason}`.
   - Helpers: `dispatch/2`, `write_html/3`, `copy_static/2`, `otp_app_for_endpoint/1`. All private.
   - Strict 200 check; non-200 raises a tagged exception caught by the mix task for clean reporting.

6. **Add `Mix.Tasks.PhoenixSsg.Export`**
   - Files: `lib/mix/tasks/phoenix_ssg.export.ex` (new)
   - `use Mix.Task`, `@shortdoc`, `@impl Mix.Task def run(args)`.
   - `Mix.Task.run("app.start")` first.
   - Build config via `PhoenixSsg.Config.load/0`; emit warnings from `RouteDiscovery.warnings/1`; call `Exporter.export/1`; print per-path log + final summary (`N rendered, M assets copied, sitemap → ...`).
   - Accept `--output`, `--base-url` overrides for ad-hoc use; CLI flags win over config.

7. **Add `Mix.Tasks.PhoenixSsg.Install` (Igniter)**
   - Files: `lib/mix/tasks/phoenix_ssg.install.ex` (new), `lib/phoenix_ssg/install/sitemap_controller_template.ex` (or inline EEx string in installer)
   - Guard the whole module behind `if Code.ensure_loaded?(Igniter.Mix.Task)` so it compiles without igniter.
   - Steps inside `igniter/1`: add `:phoenix_ssg` config block to `config/config.exs`; create `<AppWeb>.SitemapController` with a `show/2` calling `PhoenixSsg.Sitemap.generate/2`; add the `/sitemap.xml` route via `Igniter.Libs.Phoenix.add_scope/4` against the app's web module.
   - Optional `--with-robots` flag adds a `RobotsController` stub (same pattern, plain text body).

8. **Wire up library config defaults and module documentation**
   - Files: `config/config.exs`
   - Leave consumer-facing `config :phoenix_ssg, ...` documented in README only; the library's own `config/config.exs` stays empty (it's a lib, not an app). No change needed beyond confirming tests don't require app env.

9. **Test fixture: minimal Phoenix endpoint + router**
   - Files: `test/support/fixture_endpoint.ex` (new), `test/support/fixture_router.ex` (new), `test/support/fixture_pages.ex` (new), `test/test_helper.exs`
   - Define a tiny `PhoenixSsg.TestSupport.Endpoint` with two static GET routes (`/` and `/about`) and one dynamic (`/items/:id`). Pages return small literal HTML strings via `Plug.Conn.send_resp/3`. Add `:phoenix` to deps (test-only is fine for the fixture; the library code itself doesn't `use` Phoenix).
   - Update `mix.exs` to compile `test/support/**.ex` in `:test` env; add `{:phoenix, "~> 1.7", only: :test}` and `{:plug_cowboy, "~> 2.7", only: :test}` (or whatever the current Phoenix tests need — minimal viable set).

10. **Unit tests**
    - Files: `test/phoenix_ssg/config_test.exs`, `test/phoenix_ssg/route_discovery_test.exs`, `test/phoenix_ssg/sitemap_test.exs`, `test/phoenix_ssg/exporter_test.exs`
    - Config: defaults + validation errors.
    - RouteDiscovery: filtering, dedupe, exclude globs, dynamic-route warning.
    - Sitemap: XML well-formed, escaping, ordering.
    - Exporter: render fixture endpoint into a `tmp_dir`, assert files exist, assert sitemap content.

11. **Mix-task integration test**
    - Files: `test/mix/tasks/phoenix_ssg_export_test.exs`
    - Use `ExUnit.CaseTemplate` + `Mix.Task.rerun/2`. Run the task against the fixture endpoint into a `tmp_dir` (set via CLI flag or `Application.put_env` in `setup`). Assert exit, files, summary log.

12. **Installer test**
    - Files: `test/mix/tasks/phoenix_ssg_install_test.exs`
    - Use `Igniter.Test.test_project/0` (per igniter test docs). Run the installer, assert config/controller/route additions.
    - Skip the test cleanly when igniter isn't loaded.

13. **README + module docs**
    - Files: `README.md`
    - Sections: install (with-Igniter and without), config reference, common recipe (`MIX_ENV=prod mix assets.deploy && MIX_ENV=prod mix phoenix_ssg.export`), the `Phoenix.ConnTest` constraint, deploy hosts (Cloudflare Pages, GitHub Pages, Netlify, S3), and a note linking to the spec.

14. **Update `mix.exs` metadata**
    - Files: `mix.exs`
    - Add `package/0`, `description/0` (no version bump — `git_ops` handles that). Add `:phoenix` and `:plug_cowboy` only-in-test deps. Add `elixirc_paths(:test)` to compile `test/support`.

## Dependencies & Ordering

- Steps 2–4 are independent siblings; do them in any order before step 5.
- Step 5 (Exporter) depends on 2, 3, 4.
- Step 6 (Export task) depends on 5.
- Step 7 (Installer) is independent of 5/6 but should land after 4 (uses `Sitemap` in the generated controller).
- Step 9 (test fixture) must precede 10–12 and likely needs to land in the same commit as step 14 (deps + elixirc_paths) or compilation will fail.
- Step 1 (facade) can be done last; it's just a re-export.
- README (13) goes last so it reflects the actual API.

## Edge Cases & Risks

- **Phoenix as a runtime dep:** library code never `use`s Phoenix, so we avoid forcing it in. Document loudly that consumers must keep `:phoenix` non-test-scoped because of `Phoenix.ConnTest`.
- **Endpoint not started:** `Mix.Task.run("app.start")` covers the common case but won't help if the consumer has a custom Application that opts out. Surface a clear error if `Endpoint.url/0` raises.
- **`priv/static` missing:** consumers who haven't run `assets.deploy` get an empty `priv/static`. Don't fail — log a warning.
- **Path collisions:** rendered HTML overwriting a copied static file. Detect and warn (compare sets after asset copy).
- **Endpoint with `script_name` (URL prefix):** smartworks creates a self-symlink to support this. Decide whether to port it; tentatively yes, behind a config flag (`url_prefix_symlink: true`), default off. Add as a follow-up if not in v1.
- **`extra_paths` returning bad data:** validate it returns a list of strings starting with `/`; otherwise raise with a pointer to the MFA.
- **Duplicate paths from extras + router:** dedupe deterministically.
- **Dynamic route warning false positives:** the heuristic is "router has `/posts/:id` but no extra path starts with `/posts/`" — coarse but cheap. Document the limitation rather than over-engineer.
- **Igniter version drift:** pin against `igniter ~> 0.6` (already there). Use only the documented `Igniter.Libs.Phoenix.add_scope/4` and `Igniter.Project.Config` helpers.
- **`commit_hook` local path dep** is wired in — commits during this work must be Conventional Commits or pre-commit will reject them.

## Testing Strategy

- **Unit:** `Config`, `RouteDiscovery`, `Sitemap`, plus `Exporter` against a tmp dir + fixture endpoint. ExUnit, no external services.
- **Integration:** `Mix.Tasks.PhoenixSsg.Export` end-to-end against the fixture endpoint; assert the on-disk tree and `sitemap.xml` content.
- **Installer:** `Igniter.Test` project assertions; gated on igniter presence.
- **Manual smoke:** in `$HOME/src/Web/testapp`, add `phoenix_ssg` as a path dep, configure, run `mix phoenix_ssg.export`, open `priv/static_site/index.html` in a browser. (Sandbox per spec; smartworks remains read-only.)
- **Regression check before release:** run the export against `testapp` after each non-trivial change; compare output diff.

## Open Questions

- [x] Port the `script_name` self-symlink behavior from smartworks for hosts that serve the app under a path prefix? Default off if yes.  Answer: don't port any of smarkworks scripts under the bin directory.
- [x] Trailing-slash variant (`/posts/foo.html` flat) — confirm directory-style only is acceptable.  Answer: I don't know what you mean.
- [x] Asset copy ordering on collision — warn vs. fail. Default warn.  Answer: OK. 
- [x] Should the export task auto-run `mix assets.deploy` when `MIX_ENV=prod`, or stay explicit and have the README document the two-step recipe? Default: explicit, matches smartworks.  Answer: documentation only
- [x] Render concurrency — confirm serial v1 is fine; revisit only if a real consumer reports slow exports.  Answer: serial is fine.
- [x] Surface `--strict` vs `--lenient` flags for non-200 handling, or always strict? Default: always strict.  Answer: strict is ok 
- [x] Robots.txt installer flag — include in v1 or punt? Spec says "optional"; lean punt unless trivial.  Answer: ok 
