# Contributing to Flux

This guide covers developing Flux itself, including the reactive runtime, test suites, documentation site, and release process. If you are using Flux in a game, read the [Getting Started guide](.luaudocs/guide/introduction/getting-started.md) instead.

Bug reports and pull requests are welcome. Open an issue first for anything larger than a bug fix. For smaller changes, open a pull request with the checks below passing.

## Setup

- [Rokit](https://github.com/rojo-rbx/rokit): Run `rokit install` to install the tools pinned in `rokit.toml` (Rojo, StyLua, luau-lsp, and Wally).
- Python 3.11 or newer: Run `python3 tools/sert.py fetch` to populate `.sert/` with the pinned [sert](https://github.com/kohltastrophe/sert) test toolkit, engine definitions, and standalone `luau` binary. `.luaurc` aliases `@sert` to `.sert/sert/src`, so run this before running the headless test suite or language server.
- Node 22 or newer for the [LuauDocs](https://github.com/kohltastrophe/luaudocs) documentation site and `llms.txt` generation.

## Layout

```text
src/                     the Flux package (Rojo root, --!strict Luau)
  init.luau              public Flux table, callable constructor, and Instance creation (new, edit)
  Graph.luau             reactive graph (signal, computed, effect, scope, context, batching, and flush)
  Store.luau             deep reactive proxy tables and array helpers
  Conditional.luau       reactive control flow (show, switch, presence) and list mapping (forValue, forIndex)
  Bind.luau              two-way Instance property bindings (bind, model) and action helpers
  Edit.luau              declarative property, attribute, tag, event, ref, and child application
  Motion.luau            physics springs, parametric tweens, and perceptual Oklab/Oklch color helpers
  Async.luau             cancellable reactive tasks (async) and error boundaries (safe)
  Sync.luau              server-to-client and per-player state replication
  Layout.luau            terse UI layout and constraint builders
  Interact.luau          pointer, hover, press, and focus interaction tracking
  Responsive.luau        viewport size tracking and media query helpers
  Clock.luau             frame scheduler and deterministic manual clock for tests
  Compat.luau            Roblox datatype, Instance, and task fallbacks for standalone Luau
  Type/
    init.luau            public and internal Luau type definitions
    Instances.luau       generated Creatable and Editable class maps (updated daily by update-instances.yml)
test/
  spec.client.luau       shared test entry point for standalone Luau and Open Cloud execution
  default.project.json   Rojo project for Studio and Open Cloud test places
  unit/
    init.luau            suite aggregator and afterEach leak/reset hooks
    *.spec.luau          per-module unit, property, and model-based test suites
  lib/
    env.luau             test harness bridging Flux.Clock, Compat, and sert.env
    GraphModel.luau      stateful reference model for Graph property tests
    Model.luau           shared model-testing helpers
  runner/                sert Studio runner configuration and client/server bootstrap scripts
  types/                 compile-time type probes (positive cases and negative cases in fail/)
.luaudocs/               documentation site guides, landing page, and static assets
tools/
  sert.py                bootstrap wrapper for the pinned sert version in sert.toml
```

`src/Type/Instances.luau` is generated from the Roblox API dump by `.github/scripts/generate_instances.py` and updated automatically by `.github/workflows/update-instances.yml`. Do not edit it by hand; run `python3 .github/scripts/generate_instances.py` to refresh it locally.

## Tests

CI runs static checks, unit tests, line coverage, and mutation testing in fastest-first order:

```sh
npx --yes luaudocs@latest llms --check               # verify root llms.txt matches src/ and .luaudocs/
python3 tools/sert.py lint                           # luau-lsp (new solver), test/types probes, and stylua --check
python3 tools/sert.py run                            # headless test suite on standalone luau
python3 tools/sert.py run -a "Graph"                 # filter tests by name or tag (e.g. -a "@file=Graph")
python3 tools/sert.py run --coverage                 # run suite and write coverage.out
python3 tools/sert.py coverage --min 90              # enforce >= 90% line coverage across src/
python3 tools/sert.py mutate --no-coverage-run --min 85  # enforce >= 85% mutation score across src/
```

`sert lint` verifies that every `test/unit/**/*.spec.luau` file is required in `test/unit/init.luau`, checks `src` and `test` under the new Luau type solver, verifies that every file in `test/types/` passes and every file in `test/types/fail/` fails typechecking, and checks formatting with `stylua --check`. Run `stylua src test` to format code locally.

When adding a new module or spec file:

1. Require the spec in `test/unit/init.luau`.
2. Tag the spec with `@file=<Name>` and map the source module under `[mutate.specs]` in `sert.toml` so targeted mutation runs stay fast.

Nightly CI (and manual workflow dispatch) also runs `python3 tools/sert.py run --exhaustive` for larger property and model test budgets.

### Test harness and leak checks

`test/lib/env.luau` lets the same spec files run in both standalone Luau and Roblox:

- **Headless (`luau`):** `env.luau` constructs a `sert.env` mock engine wired to `Flux.Clock` (manual clock) and `src/Compat.luau`, then bridges the mock engine's `RunService` step to `Flux.Clock`'s `Heartbeat` connection before requiring `src/init.luau`. `sert.test` specs run against this deterministic clock, while `sert.rtest` specs (which require real Roblox `Instance` layout or engine services) skip in standalone `luau`.
- **Roblox (Studio and Open Cloud):** `env.luau` requires the mounted `ReplicatedStorage.Flux` and `ReplicatedStorage.sert` modules directly and steps frames with `RunService.Heartbeat:Wait()`. Both `sert.test` and `sert.rtest` specs run.

Effects and UI bindings are frame-batched, so tests advance time with `Flux.flush()`, `env.frame(dt)`, or `env.settle()`. Tests that expect warning output capture it with `env.warnings(fn)`.

After every test, the `afterEach` hook in `test/unit/init.luau` resets `Flux.Defaults`, restores the default `1920x1080` viewport, resets `Flux.Clock`, and calls `env.idle(Flux)` to verify that no reactive owner, active tracking context, suspended `untrack` state, or provided `Flux.context` value leaked at the top level.

## Roblox Lane

Run the full suite (including `rtest` specs) in Roblox Studio or via the Open Cloud Luau Execution API:

```sh
python3 tools/sert.py studio    # run test/default.project.json in a fresh headless Studio session
python3 tools/sert.py cloud     # build the test place and run test/spec.client.luau on Open Cloud
```

`cloud` builds `test/default.project.json` with Rojo and executes `test/spec.client.luau` against the place configured by `ROBLOX_API_KEY`, `ROBLOX_UNIVERSE_ID`, and `ROBLOX_PLACE_ID` (or `ROBLOX_TEST_UNIVERSE_ID` and `ROBLOX_TEST_PLACE_ID` in CI). Pass `--dry-run` to validate the place build without making network requests, or `studio --check` to validate the Studio suite configuration without launching Studio.

## Docs

The documentation site in `.luaudocs/` is built with [LuauDocs](https://github.com/kohltastrophe/luaudocs) from the doc comments in `src/` and the Markdown guides in `.luaudocs/guide/`:

```sh
npx --yes luaudocs@latest dev     # start local VitePress dev server with live reload
npx --yes luaudocs@latest build   # build static site into .luaudocs/.vitepress/dist
npx --yes luaudocs@latest llms    # regenerate the root llms.txt file
```

Any change to public API doc comments in `src/` or guide pages in `.luaudocs/guide/` can change the generated `llms.txt` at the repository root. Run `npx --yes luaudocs@latest llms` and commit the updated `llms.txt` in the same pull request so the `luaudocs llms --check` CI step passes.

## Releasing

[`.github/workflows/release.yml`](.github/workflows/release.yml) uses [`kohltastrophe/release`](https://github.com/kohltastrophe/release) to maintain an automated release pull request on `main` that bumps `wally.toml` and `.luaudocs/guide/introduction/getting-started.md` from Conventional Commits. Merging the release pull request tags `v<version>`, waits for CI on that commit, builds `Flux.rbxm` and `Flux-Model.rbxm`, creates the GitHub release, updates the `dist` branch, and publishes to Wally and the Roblox Creator Store.

1. **Dry run.** Trigger the **Release** workflow manually from the Actions tab on `main` with `dry_run` enabled. This validates version sync across manifests, builds `Flux.rbxm`, `Flux-Model.rbxm`, and the Wally package zip, enforces the 2 MiB Wally registry limit, and uploads the `release` artifact with `SHA256SUMS` without publishing.
2. **Release.** Merge the automated `chore: release <version>` pull request (or push a release commit to `main`). Versions with a hyphen suffix (like `-rc.1`) publish as GitHub prereleases.
3. **Dist branch and registries.** The `dist` job runs `python3 tools/sert.py dist --from "$GITHUB_SHA"` to commit the released tree (`default.project.json` and `src/`) onto the `dist` branch for consumers that vendor Flux via Git subtree or submodule. The `wally` and `creator-store` jobs publish using the `release` environment secrets:
   - `WALLY_AUTH_TOKEN`: token for the `kohltastrophe` Wally scope.
   - `MODEL_TOKEN`: Roblox Open Cloud API key with write access to asset `18506925834`.

### Version pins

Update pinned tools intentionally:

- `rokit.toml`: Rojo, StyLua, luau-lsp, and Wally.
- `sert.toml`: `[sert]` `version` and `[tools]` `luau`.
- GitHub workflows: `CompeyDev/setup-rokit` and third-party actions in `.github/workflows/`.
