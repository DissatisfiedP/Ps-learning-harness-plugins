# Testing a plugin

This file covers how a plugin is checked before it is published: the app's `plugin validate` and `plugin test` commands (what each step does, the output, the exit codes), type checking in the editor, how to write tests that are worth having, how to try a plugin in the app, and this registry's own check with its version rule. It applies to host API version 1 and the app build of 2026-11-15. All command output shown was produced by running the commands; the checker was Luau 0.738's `luau-analyze`.

## The `plugin` command

The checker is a binary of the app repository (`crates/harness/src/bin/plugin.rs`). From a checkout of the app repo:

```sh
cargo run -p harness --bin plugin -- validate <path to this repo>/plugins/<id>
cargo run -p harness --bin plugin -- test <path to this repo>/plugins/<id>
```

After one build the binary is `target/debug/plugin` in the app repo and can be run directly. Below, `plugin` stands for either form.

| Command line | Exit code | Output |
|---|---|---|
| `plugin validate <dir>`, valid | 0 | `ok: <id> <version>` on standard output |
| `plugin test <dir>`, all passing | 0 | the report below on standard output |
| either, on a failure | 1 | the first error on standard error; nothing else |
| anything else (no directory, unknown command) | 2 | `usage: plugin test <dir> \| plugin validate <dir>` |

### `plugin validate <dir>`

1. Reads and parses `<dir>/plugin.toml` and applies every manifest rule ([package.md](package.md#manifest-plugintoml)): keys, id, version, api, platforms, permissions, tool names and agents, that each referenced file exists inside the package, the prompt word limit, that `src/main.luau` exists.
2. Reads each tool's `input` file and checks that it is JSON and that its top-level value is an object.

It stops at the first problem. It does not load any Luau, so it does not notice a syntax error, a missing export, or an `entry` that names nothing.

```console
$ plugin validate plugins/tally
ok: tally 0.1.0
```

### `plugin test <dir>`

Three steps, each stopping the run on failure:

1. **Validate**, as above.
2. **Type check**, if a `luau-analyze` binary is on `PATH`.
3. **Run the tests** in `tests/`.

```console
$ plugin test plugins/tally
manifest ok: tally 0.1.0 (1 tools)
luau-analyze: ok
4 test(s) passed:
  plugins/tally/tests/tally.luau::bad_input_is_an_error
  plugins/tally/tests/tally.luau::figure
  plugins/tally/tests/tally.luau::renderer_redraws_the_stored_data
  plugins/tally/tests/tally.luau::totals
```

Test names start with the directory as it was given on the command line.

#### The type check

- Every `.luau` file under `src/` and `tests/`, sub-folders included, is copied to a temporary folder next to the type stubs **bundled in the `plugin` binary** and a generated `.luaurc` that maps `@harness` to them. `luau-analyze` runs there with no options. Paths in its report are rewritten to the package's.
- The mode is luau-analyze's default, **nonstrict**, with the new type solver. A file opts into strict checking with `--!strict` on its first line.
- A non-zero exit of `luau-analyze` fails the run:

  ```console
  $ plugin test pkg
  luau-analyze failed:
  pkg/tests/a.luau(2,19): TypeError: Expected this to be 'number', but got 'string'
  ```

- Lint warnings (`LocalUnused`, `SameLineStatement`, `DeprecatedApi`, …) do not fail the run on their own and are not shown when the check passes. They are printed along with the errors when it fails.
- A syntax error in any file under `src/` or `tests/` fails this step, including files nothing requires.
- Without `luau-analyze` the step is skipped and the report says so; the tests still run:

  ```text
  luau-analyze: not installed (install the Luau CLI to type-check; tests still run)
  ```

  This repository's `nix develop` shell provides `luau-analyze` and `luau-lsp`.

**Use `--!strict`.** In nonstrict mode the checker accepted all of the following, and each failed only when the test ran:

| Code (no `--!strict`) | Type check | At runtime |
|---|---|---|
| `local x: number = "s"` | ok | (no error) |
| `svg.rect(1, 2, 3)` | ok | `bad argument #4: error converting Lua nil to f64 (expected number or string coercible to number)` |
| `svg.nope(1)` | ok | `attempt to call a nil value` |

With `--!strict` on the first line the first of these is reported as `TypeError: Expected this to be 'number', but got 'string'`. The reference plugin `plugins/argument-map` uses `--!strict` in every source file.

#### The test run

- Test files are the `*.luau` files **directly in `tests/`**, in order of their path (byte order: `B.luau` before `a.luau`). Sub-folders are not scanned, so helpers and fixtures belong in a sub-folder such as `tests/lib/`. A helper module placed directly in `tests/` is run as a test file: if it returns a table of functions, each one is called with no arguments.
- No `tests/` folder: `the package has no tests/ folder`. No `.luau` file in it: `tests/ has no *.luau files`. Both fail the run.
- All test files run in **one VM**, built like a plugin's VM ([package.md](package.md#the-sandbox)) with two additions: `require("@harness/test")` works, and `require` may load files from `tests/` as well as `src/`. Consequences: a module required by two test files is loaded once and keeps its state; a global assigned in one file is visible in the next. Tests must not depend on either.
- The entry module is not loaded automatically. A test reaches it with `require("../src/main")`.
- Each file is evaluated and its return value decides what runs:

  | The file returns | What runs | Reported as |
  |---|---|---|
  | a function | the function, once | `<path>` |
  | a table whose values are all functions | each function, in order of its key as a string (`"10"` before `"9"`, upper case before lower case) | `<path>::<key>` |
  | nothing (statements only) | only the file's top-level code | not listed; a run of such files alone prints `0 test(s) passed:` |
  | an empty table | | error `the test file returned an empty table` |
  | a table with a value that is not a function | | error `error converting Lua integer to function` (the type varies) |
  | any other value | | error `a test file must return a function or a table of functions` |

  A file that consists of a single expression, such as one `assert(…)` call, is evaluated as that expression, and its value counts as the return value (so `assert(1 == 1)` alone is the last error above). Always end a test file with `return`.
- A test passes when it returns without an error. Its return value is ignored. There are no assertion helpers beyond `assert`, `error` and `golden`.
- **The first failure stops the run.** Later tests and files do not run, the names of the tests that passed are not printed, and the exit code is 1:

  ```console
  $ plugin test pkg
  runtime error: tests/t.luau:3: math is broken
  stack traceback:
  	[C]: in ?
  	[C]: in function 'assert'
  	tests/t.luau:3: in function 'b'
  ```

- Each test file has 10 seconds in total (evaluation and all its functions): `plugin time limit (10000 ms) exceeded`. The 64 MiB memory limit applies: `plugin memory limit: not enough memory`.
- `print` works and goes to standard output; the lines appear after the report.

### Golden files

`require("@harness/test").golden(name, text)` compares `text` with `tests/golden/<name>` and fails with the first differing line ([host-api.md](host-api.md#harnesstest)).

```console
$ plugin test plugins/tally
runtime error: golden file tests/golden/two-bars.svg missing (run with PLUGIN_UPDATE_GOLDEN=1 to write it)
stack traceback:
	[C]: in ?
	tests/tally.luau:14: in function 'figure'

$ PLUGIN_UPDATE_GOLDEN=1 plugin test plugins/tally     # writes tests/golden/two-bars.svg
$ plugin test plugins/tally                            # compares
```

- The variable must be exactly `1`. With it, every `golden` call writes its file and none compares, so the run proves nothing about figures; run again without it.
- Commit the golden files. They are part of the package and are packed with it.
- After an update, read the diff. For an SVG, open the file in a browser.

## Type checking in the editor

The repository root has a `.luaurc`:

```json
{ "aliases": { "harness": "./plugin-api" } }
```

`luau-lsp` and `luau-analyze` resolve `require("@harness/svg")` through it to [`../plugin-api/svg.luau`](../plugin-api/svg.luau), and relative requires by the same rules as the runtime. The files in `plugin-api/` are type-only stubs with the documentation of each function; the real modules exist only in the app.

To check a plugin by hand, from the repository root:

```sh
luau-analyze plugins/<id>/src/*.luau plugins/<id>/tests/*.luau
```

`plugin-api/` mirrors the app repo's `crates/harness/plugin-api/` with identical signatures. `plugin test` does not read this repository's copy: it checks against the copy compiled into the binary. If the two ever differ in a signature, `plugin test` is the authority.

What the stubs cannot express, and the checker therefore does not catch: calling a generator with `:`, passing `x` in `attrs` to `svg.rect`, reading `.re` of a `num` result that turned out to be a plain number (the type is `number | Complex`, so strict mode does flag an unguarded `.re`), a seed out of range.

## Writing tests

A test file is ordinary Luau:

```lua
local main = require("../src/main")
local golden = require("@harness/test").golden

local args = { items = { { label = "Cats", count = 3 }, { label = "Dogs", count = 6 } } }

return {
  totals = function()
    local out = main.show(args)
    assert(out.text == "2 bars; the total is 9.", out.text)
    assert(out.artifact.kind == "svg")
    assert(out.artifact.data.total == 9)
  end,
  figure = function()
    golden("two-bars.svg", main.show(args).artifact.svg)
  end,
  renderer_redraws_the_stored_data = function()
    local out = main.show(args)
    assert(main.render(out.artifact.data) == out.artifact.svg)
  end,
  bad_input_is_an_error = function()
    local ok, err = pcall(main.show, { items = { { label = "Cats" } } })
    assert(not ok and string.find(tostring(err), "items[1].count must be a number", 1, true), tostring(err))
  end,
}
```

What to test:

- **Every name the manifest refers to.** Neither command checks that `entry`, the renderer, the `calls` and `grade` exist in the entry module. One assertion per name does: `assert(type(main.show) == "function")`.
- **The result shape of each tool**: `text` is a string; for an artifact tool `artifact.kind == "svg"`, `artifact.svg` is a string starting `<svg`, and `artifact.data` holds what the view and renderer need.
- **The figure, as a golden file.** The builders are deterministic, so the SVG text is stable. Keep fixtures small so the golden stays readable.
- **Bad input.** The model's arguments are not validated against the schema ([package.md](package.md#input-schemas)). Call each tool with missing fields, wrong types and empty lists, and assert on the error text the model would read. Pass the second argument of `assert` so a failure shows the actual value.
- **JSON round trip of `data`.** The view and the renderer receive `data` after it has been stored as JSON. `json.decode(json.encode(data))` in a test reproduces that, including the cases that change shape (empty tables, holes, mixed keys):

  ```lua
  local json = require("@harness/json")
  local stored = json.decode(json.encode(out.artifact.data))
  assert(main.render(stored) == out.artifact.svg)
  ```

- **`grade`**: a correct answer, a wrong one, the tolerance boundary, and malformed submissions (`nil`, a string, an empty table), which must not raise ([artifacts-and-views.md](artifacts-and-views.md#the-grade-contract)).
- **Hidden answers**: if a tool hides something from the learner, assert that the hidden text occurs neither in `artifact.svg` nor in `json.encode(artifact.data)`.
- **Limits**: a figure for the largest input the schema allows should stay well under 256 KiB (`#out.artifact.svg`) and inside 2 seconds.

Determinism:

- No `math.random`; use `@harness/rand` with a seed from the input or a constant.
- Round coordinates before drawing. Unrounded doubles (`3.3333333333333335`) make goldens long and fragile.
- When output is built by iterating a table with string keys, sort the keys first.
- Catch host errors with `pcall` and compare `tostring(err)` with `string.find(…, 1, true)`; the error is an object whose text includes a traceback, not a plain string ([host-api.md](host-api.md#errors-raised-by-host-functions)).

What tests cannot cover: the tool call through the host (result decoding, truncation, the 2 s and 200 ms limits, storing and sanitizing the artifact) and the view. Those need the app.

## Trying a plugin in the app

Two ways, both from the app's Settings. The steps below are from the app's source and this repository's README; they were not exercised for this document.

**As a folder plugin (fast loop).** Settings → Plugins → "Add folder plugin…", then pick `plugins/<id>`. The package is validated and loaded at once. The app re-reads it whenever its files (outside `tests/`) change, at the moment the plugin is next used; an edit that does not validate keeps the last good version in use and shows the error in the plugin list. A folder plugin takes precedence over an installed copy with the same id.

**Through a local registry index (tests the packed package).**

```sh
scripts/registry.sh check --local
```

Then add the absolute path of `out/site/index.json` as a registry in Settings → Registries (a registry must be `https://`, `file://` or an absolute path) and install the plugin from it. With `--local`, versions that are not yet published point at the `file://` package in `out/packages/`.

In both cases the plugin's tools reach the tutor only in a session whose plan section lists the plugin.

## The registry check

```sh
nix develop                # or direnv; provides the pinned tar, gzip, jq, yq, luau
scripts/registry.sh check
```

`check` does the following for every folder under `plugins/` and writes nothing outside `out/`:

1. Fetches the published `index.json` (`index_url` in `registry.toml`) as the base to compare against. `REGISTRY_BASE=<url or path>` overrides it; `REGISTRY_BASE=none` compares against an empty registry.
2. Checks the fields of `plugin.toml` that the index carries: `id` (pattern, and equal to the folder name), `version` (semver), `api` (a whole number ≥ 1), non-empty `title`, `description`, `use_when`, `avoid_when`, `platforms` (non-empty subset of `desktop`, `mobile`, no duplicates), empty `permissions`.
3. Checks the files: plain files and folders only, each at most 16 MiB, 64 MiB in total.
4. Packs the folder reproducibly into `out/packages/<id>-<version>.tar.gz` (dotfiles excluded) and checks the package is at most 16 MiB.
5. Compares with the base: a version that is already published must pack to the same sha256; a new version must be higher than every published one.
6. Writes the index the next publish would deploy to `out/site/index.json`.

```console
$ scripts/registry.sh check
  tally                    0.1.0        new        ee0e25959ef0041e124dc44a9094b149f985ff741f1db53ecc067e383af40d45

Wrote out/site/index.json: 1 plugin(s), 1 new version(s).
```

The third column is `new` or `published`. Problems are listed together and the exit code is 1:

```console
$ scripts/registry.sh check

1 problem(s):
  - plugins/tally: 0.1.0 is already published, and the folder no longer packs to it (published sha256 ee0e…0d45, now 4585…9aae). Bump `version` in plugin.toml.
```

**The registry check does not run `plugin validate` or `plugin test`.** It does not look at tools, schemas, views or Luau source: a package that fails `plugin test` passes `scripts/registry.sh check`. Run both.

### Versions are immutable

From this repository's README:

- Every change to a published plugin needs a higher `version` in its `plugin.toml`. That includes changes to tests, golden files, prompts and the README inside the plugin folder, because the whole folder is packed.
- A published version is never changed or withdrawn. CI rebuilds every package on every run and fails if a published version no longer packs to the sha256 the index lists.
- Versions only go up: `version <v> is not above the published <higher>; versions only go up`.
- The package bytes depend on the `tar` and `gzip` builds, which `flake.lock` pins. Run the check inside `nix develop`.

## Before opening a pull request

```sh
plugin test plugins/<id>          # manifest, types, tests
scripts/registry.sh check         # packing, sizes, version rule
```

Then check by hand: the figure in light and dark theme in the app, the tool descriptions as the model will read them, and that `version` was raised if the plugin was already published.
