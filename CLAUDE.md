# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

`phoenix_ssg` is an early-stage Elixir library (currently v0.0.1, mostly default Mix scaffold). The implementation is being migrated from an existing working SSG setup at `$HOME/src/Web/smartworks` — read that project when porting features. The full design and rationale lives in `_spec/designs/260425_Intro.md`; consult it before adding architecture.

## Intended architecture (target, not yet implemented)

The library will let a Phoenix app export itself to static HTML so dev keeps Phoenix's tooling (Tidewave, Claude Code, click-to-edit) while production deploys as static files.

Three planned components, in order of priority:

1. **`Mix.Tasks.PhoenixSsg.Export`** — render every exportable route via `Phoenix.ConnTest` against the user's `Endpoint`, write `index.html` per path, copy `priv/static`, emit `sitemap.xml`. This is the main event.
2. **`Mix.Tasks.PhoenixSsg.Install`** — Igniter installer that adds config stubs, a `SitemapController` + route, and optionally `robots.txt`. Use `Igniter.Libs.Phoenix.add_scope/4`.
3. **`Mix.Tasks.PhoenixSsg.Lint`** — exportability checker. Per the design doc, prefer **render-time anomaly detection** (non-200 responses, `<form method="post">`, CSRF tokens, session-setting responses) over static AST scanning.

Route enumeration uses `Phoenix.Router.routes/1`, filtered to `:get` and non-dynamic paths, combined with a user-supplied `extra_paths: {Module, :fun, args}` MFA in config for dynamic routes (e.g. `/posts/:id`).

Important runtime constraint: `Phoenix.ConnTest` must not be `only: :test` in the consuming app — the export task uses it at runtime.

## Common commands

```bash
mix deps.get              # fetch dependencies
mix compile               # compile
mix test                  # run all tests
mix test test/path.exs    # run single test file
mix test test/path.exs:N  # run single test at line N
mix format                # format code per .formatter.exs
bin/release               # tag + push a release (runs git_ops.release + git push --follow-tags)
```

## Release & commit conventions

- This repo uses **`git_ops`** for releases (configured in `config/dev.exs`). Versions are managed automatically in `mix.exs` and `README.md`; do not hand-edit version numbers.
- Commits **must follow Conventional Commits** (`feat:`, `fix:`, `chore:`, etc.) — `git_ops` parses these to compute the next version and update `CHANGELOG.md`.
- A `commit_hook` dependency is wired in via local path (`/home/aleak/src/Tool/commit_hook`); expect commit-message validation locally.
- `bin/release` runs `mix git_ops.release --yes && git push --follow-tags` — only invoke when the user explicitly asks to cut a release.

## Dependencies of note

- `git_ops` (dev only) — release tooling, see above.
- `igniter` (optional) — used to author the installer task; treat as optional at runtime so non-Igniter consumers can still use the export task.
- `commit_hook` (local path) — pre-commit validation; if Mix complains about a missing path, the user's `commit_hook` checkout is the cause.
