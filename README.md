# P's Learning Harness plugin registry

The plugins the app can install, as source. GitHub Actions pack each new
version into a `.tar.gz`, attach it to a GitHub Release, and publish one
`index.json` (registry format 1, the app repo's `docs/plugins.md` §8.1) to
GitHub Pages. The app downloads only that index and the packages a learner
installs, never this repository.

```
registry.toml               name, GitHub repository, published index URL
plugins/<id>/               one plugin: plugin.toml at the root, then src/, views/, prompts/, …
plugin-api/                 type-only stubs of the @harness/* host modules, a copy of the
                            app repo's crates/harness/plugin-api/
docs/                       plugin API documentation
scripts/registry.sh         pack, check, index, release (run by both workflows)
.github/workflows/
  check.yml                 pull requests: pack + check, upload the result
  publish.yml               master: release new versions, deploy the index
flake.nix                   the pinned tools (tar, gzip, jq, yq, gh, curl)
.luaurc                     editor/luau-analyze alias: @harness → ./plugin-api
```

## Using it in the app

Settings → Registries → add `https://dissatisfiedp.github.io/ps-learn-registry/index.json`
(`index_url` in `registry.toml`). The repository must be public: the app
downloads release assets without credentials.

## Adding or updating a plugin

1. Add or edit `plugins/<id>/`. The folder name is the plugin `id`.
2. Every change to a published plugin needs a higher `version` in its
   `plugin.toml`. A published version is immutable: CI rebuilds it on every
   run, and fails if the folder no longer packs to the sha256 the index lists.
3. Check locally:
   ```sh
   nix develop                       # or direnv
   scripts/registry.sh check
   ```
4. Open a pull request; `check.yml` runs the same check and uploads the
   packages and the index the merge would publish. Merge to publish.

To try a plugin in the app before publishing, run
`scripts/registry.sh check --local` and add `out/site/index.json` (its
absolute path) as a registry in Settings: new versions then point at their
local `file://` package.

## Editor setup and the host API

Plugins are Luau with no host globals. The host API is modules required by
name, and package files require each other by path relative to the requiring
file (Luau require-by-string; the app repo's `docs/plugins.md` §3 and §4):

```lua
local svg = require("@harness/svg")   -- also json, num, rand, log
local util = require("./util")        -- src/util.luau, next to this file
```

A test in `tests/` reaches the package with `require("../src/main")` and the
golden-file helper with `require("@harness/test")`.

The types of the `@harness/*` modules are in `plugin-api/<name>.luau` here:
type-only stubs mirrored from the app repo's `crates/harness/plugin-api/`,
with identical signatures. The `.luaurc` at this repo's root aliases
`harness` to `./plugin-api`, so luau-lsp and `luau-analyze` resolve them in
this checkout alone. The app's `plugin test` does not read this copy: it
type-checks with the copy bundled in the app, which is the one that counts.
The plugin API is documented in [`docs/README.md`](docs/README.md).

## What is checked

From `plugin.toml`, the fields the index carries:
- `id`: a lowercase letter followed by a-z, 0-9 or `-`, equal to the folder name;
- `version`: semver, never lower than a published version;
- `api`: a whole number, 1 or more;
- `title`, `description`, `use_when`, `avoid_when`: non-empty;
- `platforms`: a non-empty subset of `desktop`, `mobile`;
- `permissions`: empty. Registry packages are Luau plugins, which the app
  runs sandboxed and refuses if they declare permissions.

The files, against the app's install limits: plain files and folders only (no
links), each at most 16 MiB, 64 MiB in total, 16 MiB packed. Dotfiles are
never packed.

The rest of the manifest (tools, schemas, views, the Luau source) is validated
by the app's own checker. Run it from the app repo before opening a pull
request:

```sh
cargo run -p harness --bin plugin -- test ../ps-learn-registry/plugins/<id>
```

## How publishing works

`publish.yml` runs `scripts/registry.sh publish` on every push to master, one
run at a time:

1. Fetch the live `index.json`, the record of every published version.
2. Pack every plugin reproducibly (sorted members, owner 0, mode 644/755, time
   0, `gzip -n`), with one top-level folder `<id>-<version>/`. Check it as above.
3. Refuse to continue if any existing release is missing from the next index,
   which would mean the live index was stale or lost.
4. For each new version, create the release `<id>-v<version>` with
   `<id>-<version>.tar.gz` attached. A re-run reuses a release only if it
   holds the same bytes.
5. Deploy the new index to Pages. It lists every published version, with
   metadata from each plugin's current `plugin.toml`. A plugin whose folder is
   deleted stays listed as published, because learners may have it installed.

The package bytes, and so each sha256, depend on the tar and gzip builds.
`flake.lock` pins them, and both workflows run the script inside
`nix develop`. Updating `flake.lock` can change how existing versions pack,
which `check` then reports as an immutability failure. Re-pin only together
with version bumps.

## First-time setup on GitHub

1. Create the public repository `DissatisfiedP/ps-learn-registry` (or change
   `repository` and `index_url` in `registry.toml`) and push `master`.
2. Settings → Pages → Source: **GitHub Actions**.
3. The first push to master releases every plugin and deploys the index.

## Not built yet

Plugins whose source lives elsewhere: a `plugins/<id>/` that points at an
external package instead of holding the source.
