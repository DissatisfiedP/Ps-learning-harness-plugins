# Plugin packages (api 1)

This file describes what a plugin package contains and how the host loads and runs it: the folder layout, every `plugin.toml` key with the exact validation error for a wrong value, the input schemas, the entry module, `require`, the sandbox and its standard library, how values convert between JSON and Lua, what a tool may return, and the limits. It documents host API version 1 as implemented by the app build of 2026-11-15. Error texts in backticks are copied from `plugin validate` / `plugin test` output or from the app's source; the ones that only occur inside a running app (tool calls, artifacts, time and memory limits) are quoted from the source and its unit tests and are marked "from source". The host modules are in [host-api.md](host-api.md), artifacts and views in [artifacts-and-views.md](artifacts-and-views.md), the test commands in [testing.md](testing.md).

## Layout

```text
plugins/<id>/
  plugin.toml            manifest; required
  src/main.luau          entry module; required; returns a table of functions
  src/**/*.luau          the plugin's own modules, loaded with require
  schemas/*.json         one JSON Schema per tool (its input); required per tool
  prompts/<agent>.md     optional prompt fragment per agent, at most 250 words
  views/*.html|js|css    optional interactive view (one per plugin)
  tests/*.luau           test files; `plugin test` needs at least one
  tests/golden/*         golden files for `@harness/test`
  README.md              optional; not read by the app
```

- In this registry the folder name must equal the manifest `id`.
- Every path in the manifest is relative to the package root and must name an existing file inside it.
- The whole folder is packed and installed, tests included; names starting with `.` are never packed. Only plain files and folders are allowed (no links), each file at most 16 MiB, 64 MiB in total, 16 MiB packed (checked by `scripts/registry.sh`).
- Everything the plugin needs must be in the package. At runtime there is no network, file system, clock or process access.

## Manifest (`plugin.toml`)

Unknown keys are errors at every level; a missing required key is an error. Validation stops at the first problem. `plugin validate <dir>` prints the error on standard error and exits with 1.

```toml
id = "tally"
version = "0.1.0"
api = 1
title = "Tally bars"
description = "Draws labelled horizontal bars for a short list of counts."
license = "MIT"
platforms = ["desktop", "mobile"]
permissions = []
use_when = "The learner must compare a handful of counts at a glance."
avoid_when = "Two numbers would do, or exact values matter more than their sizes."
cost = "instant"

[[tool]]
name = "tally_show"
description = "Draw one horizontal bar per labelled count. Returns the total. Place the figure with ![short description](artifact:<id>)."
agents = ["tutor"]
input = "schemas/tally_show.json"
entry = "show"
artifact = true

[[renderer]]
entry = "render"

[prompts]
tutor = "prompts/tutor.md"
```

### Top-level keys

| Key | Type | Required | Constraint | Error when violated |
|---|---|---|---|---|
| `id` | string | yes | A lowercase letter, then `a-z`, `0-9`, `-` | ``id `Demo` must start with a lowercase letter and use only a-z, 0-9 and '-'`` |
| | | | `<id>_` (with `-` → `_`) must not begin any core tool name | ``id `question` collides with the core tool `question_ask`; pick another id`` (also e.g. `file`, `probe`) |
| `version` | string | yes | Semver, no `v` prefix | ``version `1.0` is not semver (e.g. 0.1.0)`` |
| `api` | integer | yes | `1` | `api 2 is not supported (this build implements api 1)` |
| `title` | string | yes | Not blank | `title and description are required` |
| `description` | string | yes | Not blank | `title and description are required` |
| `license` | string | yes | Not blank (an SPDX identifier is customary) | `license is required` |
| `platforms` | list of strings | yes | Non-empty subset of `desktop`, `mobile` | `platforms must be a non-empty subset of [desktop, mobile]` |
| `permissions` | list of strings | no (default `[]`) | Empty for a Luau plugin | `permissions must be empty for a Luau plugin (api 1); got [net]` |
| `use_when` | string | yes | Read by the planner. The app accepts `""`; this registry's check requires it non-empty | (registry) `` `use_when` must be a non-empty string `` |
| `avoid_when` | string | yes | As `use_when` | (registry) `` `avoid_when` must be a non-empty string `` |
| `cost` | string | yes | Free text for the planner (`"instant"`); may be empty | |
| `[[tool]]` | list of tables | no | At most 3 | `4 tools (at most 3 per plugin)` |
| `[[renderer]]` | list of tables | see below | At most one | `at most one [[renderer]] is allowed` |
| `[[view]]` | list of tables | no | At most one | `at most one [[view]] is allowed` |
| `[prompts]` | table | no | Agent name → file | below |

Parse errors come from the TOML reader and carry the position:

```text
plugin.toml: TOML parse error at line 12, column 1
   |
12 | colour = "red"
   | ^^^^^^
unknown field `colour`, expected one of `id`, `version`, `api`, `title`, `description`, `license`, `platforms`, `permissions`, `use_when`, `avoid_when`, `cost`, `tool`, `renderer`, `view`, `prompts`
```

A missing key reads ``missing field `cost` ``, a wrong type e.g. `invalid type: string "1", expected u32` (`api = "1"`) or `invalid type: string "desktop", expected a sequence`. The keys are spelled with underscores: `use-when` is an unknown field. A missing manifest is `can't read plugin.toml (No such file or directory (os error 2))`.

### `[[tool]]`

| Key | Type | Required | Constraint | Error when violated |
|---|---|---|---|---|
| `name` | string | yes | Starts with the id (with `-` → `_`) and `_` | ``tool `draw` must start with `demo_kit_` (the plugin id with '-' replaced by '_')`` |
| `description` | string | yes | Not blank. This is what the model reads when choosing the tool | ``tool `demo_kit_draw` needs a description`` |
| `agents` | list of strings | effectively | At least one of `tutor`, `practice` | ``tool `demo_kit_draw` needs at least one agent`` |
| | | | `coach`, `figure-maker`, `demo-builder`, `problem-checker` are reserved | ``tool `demo_kit_draw` names reserved agent `coach`; this build supports [tutor, practice]`` |
| | | | Nothing else | ``tool `demo_kit_draw` names unknown agent `wizard` (valid: [tutor, practice])`` |
| `input` | string | yes | Path of a JSON file in the package | ``tool `demo_kit_draw` input schema `schemas/in.json` does not exist``; `… is outside the package` |
| `entry` | string | yes | Not blank; the name of a function `src/main.luau` returns | ``tool `demo_kit_draw` needs an entry function`` |
| `artifact` | boolean | no (default `false`) | `true` requires a `[[renderer]]` | ``tool `demo_kit_draw` declares artifact = true but the plugin has no [[renderer]]`` |

Not checked by validation: that `name` has anything after the prefix, that two tools have different names, and that `entry` names a function the entry module actually exports. A wrong `entry` shows up only when the tool is called (``the plugin exports no function `<entry>` ``, from source), so assert the exports in a test ([testing.md](testing.md#writing-tests)).

`tutor` is the live teaching agent. `practice` is the practice coach; it receives the `practice`-scoped tools of the plugins that were active when the practised material was taught. A tool is offered to an agent only if the agent is in `agents`, the plugin is enabled, lists the device's platform, and is active in the current plan section (at most 3 plugins per section).

### `[[renderer]]`

| Key | Type | Required | Constraint |
|---|---|---|---|
| `entry` | string | yes | Name of an exported function that takes an artifact's stored `data` and returns an SVG string |

Required when any tool has `artifact = true`. See [artifacts-and-views.md](artifacts-and-views.md#the-renderer) for when it runs.

### `[[view]]`

| Key | Type | Required | Constraint | Error when violated |
|---|---|---|---|---|
| `name` | string | yes | Not blank | `view.name is required` |
| `html` | string | yes | Path of an existing file in the package | ``view html `views/demo.html` does not exist`` |
| `calls` | list of strings | no (default `[]`) | Exported functions the view may call. Not checked against the entry module | |
| `answer` | boolean | no (default `false`) | `true` allows the view as a `question_ask` answer surface; the entry module must then export `grade` | |

### `[prompts]`

Keys are agent names, values are paths to text files. Each file may have at most 250 whitespace-separated words (the target is about 200). The fragment is added to that agent's prompt while the plugin is active in a section; it is read from disk each time a prompt is composed, trimmed, and joined with other plugins' fragments by a blank line.

| Problem | Error |
|---|---|
| Key is not `tutor` or `practice` | ``prompts key `planner` is not an agent (valid: [tutor, practice])`` |
| File missing | ``prompts.tutor `prompts/tutor.md` does not exist`` |
| 251 words or more | `prompts.tutor has 251 words (about 200 at most)` |

### Other checks

| Problem | Error |
|---|---|
| No entry module | ``entry module `src/main.luau` does not exist`` |
| A manifest path that resolves outside the package (`..`, a symlink) | ``<what> `<path>` is outside the package`` |

What the planner sees of an enabled plugin is one catalog line built from the manifest (from source):

```text
- **Tally bars** (`tally`): tools [tally_show]; platforms [desktop, mobile]. Use when: … Avoid when: … Cost: instant
```

## Input schemas

Each tool's `input` file is a JSON Schema for the tool's argument object. It is sent to the model as the tool's parameter schema together with `name` and `description`.

What the host checks:

| Check | Error |
|---|---|
| The file exists inside the package | above |
| It parses as JSON | `schemas/in.json: EOF while parsing an object at line 2 column 0` (the JSON parser's message) |
| The top-level value is an object | `schemas/in.json must be a JSON object` |

What the host does not check:

- **That the file is a valid JSON Schema.** `{"type": 5, "nonsense": true}` passes `plugin validate`.
- **That the model's arguments match the schema.** The app passes the arguments of a tool call to the entry function as they arrive; there is no schema validation in the dispatch path. A model provider may enforce the schema; the plugin must not assume it. Missing required fields, wrong types and extra fields all reach the plugin.

Therefore the entry function validates its own input and raises a clear error for anything it cannot use. The error text is returned to the model, which can correct the call:

```lua
assert(type(args) == "table" and type(args.items) == "table", "items must be a list")
```

Keep schemas small and explicit (`type`, `properties`, `required`, `enum`, `minItems`/`maxItems`, `description`); the description fields are the model's documentation.

## The entry module

`src/main.luau` returns a table. The host looks functions up in that table by name:

| Looked up | When |
|---|---|
| each tool's `entry` | the model calls the tool |
| the renderer's `entry` | see [artifacts-and-views.md](artifacts-and-views.md#the-renderer) |
| each name in `[[view]].calls` | the view sends a `call` |
| `grade` | a learner submits an answer in the view (`answer = true`) |

```lua
local function show(args) … end
local function render(data) … end

return {
  show = show,       -- [[tool]].entry
  render = render,   -- [[renderer]].entry
  scale = scale,     -- listed in [[view]].calls
  grade = grade,     -- answer = true
}
```

Each function receives one argument, the JSON value converted to Lua ([below](#json-and-lua-values)); `grade` receives two, `(answer, target)`. A missing name is the error ``the plugin exports no function `<name>` `` (from source).

### The VM

- A plugin has one Luau VM. It is created on first use and shared by tool calls, view calls and `grade`; calls are serialized.
- `src/main.luau` is evaluated once per VM, when a function is first needed. The returned table is cached. Module-level state (in `main.luau` and in every required module) lives as long as the VM, and an edit on disk does not change a VM that is running.
- **Any error discards the VM**: a Lua error, a missing export, a result the host cannot convert, a time or memory limit. The next call builds a fresh VM and evaluates `src/main.luau` again, so module-level state is gone. Errors caught with `pcall` inside the plugin do not count.
- A folder plugin (development) whose files changed gets a new VM the next time it is used; a reinstall or update does too.
- The first call on a VM pays for loading `main.luau` and its requires inside the call's time limit.

Do not keep anything in module-level state that a later call needs for correctness. Everything a figure needs belongs in `artifact.data`.

### Errors and the model

A failing tool call is returned to the model as a tool error whose text is `plugin error: <message>` (from source). For an error raised with `error("…")` or `assert(…, "…")` the message is prefixed `runtime error: ` and the source position, and is followed by a stack traceback, as in this `plugin test` output:

```text
runtime error: tests/t.luau:3: math is broken
stack traceback:
	[C]: in ?
	[C]: in function 'assert'
	tests/t.luau:3: in function 'b'
```

Write error messages for the model: say what was wrong with the input and what is accepted.

## `require`

`require` follows Luau's require-by-string rules, the same ones `luau-analyze` and luau-lsp use.

| Form | Resolves to |
|---|---|
| `require("@harness/json")`, `svg`, `num`, `rand`, `log` | the host module |
| `require("@harness/test")` | the test module, under `plugin test` only |
| `require("./x")` | `x` next to the requiring file |
| `require("../x")` | `x` one folder up from the requiring file |
| `require("@self/x")` | from `dir/init.luau`: `dir/x`. From any other file `f.luau`: `f/x` |

Rules, with the observed error for each violation:

- A module path `p` names the file `p.luau` or `p/init.luau`. Do not write the extension.

  | Call | Error |
  |---|---|
  | `require("../src/util.luau")` | `error requiring module "../src/util.luau": could not resolve child component "util.luau"` |
  | `require("../src/missing")` | `error requiring module "../src/missing": could not resolve child component "missing"` |
  | `require("../src/group/init")` (the file exists) | `error requiring module "../src/group/init": could not resolve child component "init"` — require the folder: `require("../src/group")` |
  | `require("../src/dir")` where `dir/` has no `init.luau` | `no module present at resolved path` |
  | both `src/amb.luau` and `src/amb/` exist | `error requiring module "../src/amb": could not resolve child component "amb" (ambiguous)` |

- `./` from an `init.luau` is relative to the folder's parent: from `src/group/init.luau`, `./util` is `src/util` and `@self/inner` is `src/group/inner`.
- Only `.luau` files load. A `.lua` file, a `.txt` file or `plugin.toml` cannot be required (`could not resolve child component …`).
- No bare names and no absolute paths:

  ```text
  error requiring module "util": require path must start with a valid prefix: ./, ../, or @
  ```

- No alias other than `@harness` and `@self`. A package's own `.luaurc` is not read at runtime.

  | Call | Error |
  |---|---|
  | `require("@lune/fs")` | `@lune is not a require alias here: a plugin requires @harness/<module>, @self/…, ./… or ../…` |
  | `require("@harness/fs")` | `@harness/fs is not a harness module (json, svg, num, rand, log)` |
  | `require("@harness/JSON")` | `@harness/JSON is not a harness module (json, svg, num, rand, log)` |
  | `require("@harness/json/x")` | `@harness/json/x is not a harness module` |
  | `require("@harness")` | `no module present at resolved path` |
  | `require("@harness/test")` in a running plugin | ``@harness/test is only available under `plugin test` `` (from source) |

- A path cannot leave the package, and a module file must lie in `src/` (after following symlinks). Under `plugin test`, `tests/` is allowed too.

  | Call (from `tests/f.luau`) | Error |
  |---|---|
  | `require("../../x")` | `tests/f.luau: a require path can't leave the plugin package` |
  | `require("../outside")` (a file in the package root) | ``module `outside.luau` resolves outside the plugin's src/ and tests/`` (in a running plugin: `… the plugin's src/`) |

- The argument must be a string: `bad argument #1 to 'require' (string expected, got number)`. It may be computed at runtime, but the type checker then cannot follow it.
- A module is evaluated once per VM and the result is cached per file, whatever path reached it (`require("../src/util") == require("../src/dir/../util")`). A module that returns nothing, or `nil`, yields `true`. A module that returns several values yields the first. A module that raises an error is not cached and raises again on the next `require`.
- A syntax error in a required module is `syntax error: src/syntax.luau:2: Expected identifier when parsing expression, got <eof>`; a runtime error while loading is the module's own error (`src/throws.luau:1: boom at load`).

## The sandbox

The VM is Luau (reported `_VERSION`: `Luau 0.740`) with the safe standard libraries and Luau's sandbox mode on.

### Globals

Present:

```text
_G _VERSION assert bit32 buffer coroutine error gcinfo getfenv getmetatable integer
ipairs math newproxy next pairs pcall print rawequal rawget rawlen rawset require
select setfenv setmetatable string table tonumber tostring type typeof unpack utf8
vector xpcall
```

Absent (`nil`): `io`, `os`, `debug`, `package`, `dofile`, `loadfile`, `loadstring`, `load`, `collectgarbage`. So there is no clock (`os.time`, `os.clock`), no file access, and no way to compile code from a string:

```text
os.time()            attempt to index nil with 'time'
io.open("/x")        attempt to index nil with 'open'
loadstring("…")      attempt to call a nil value
```

Library contents:

| Library | Functions and constants |
|---|---|
| `string` | `byte char find format gmatch gsub len lower match pack packsize rep reverse split sub unpack upper` |
| `table` | `clear clone concat create find foreach foreachi freeze getn insert isfrozen maxn move pack remove sort unpack` |
| `math` | `abs acos asin atan atan2 ceil clamp cos cosh deg exp floor fmod frexp isfinite isinf isnan ldexp lerp log log10 map max min modf noise pow rad random randomseed round sign sin sinh sqrt tan tanh`; constants `e huge nan phi pi sqrt2 tau` |
| `bit32` | `arshift band bnot bor btest bxor byteswap countlz countrz extract lrotate lshift replace rrotate rshift` |
| `utf8` | `char charpattern codepoint codes len offset` |
| `buffer` | `copy create fill fromstring len readbits readf32 readf64 readi16 readi32 readi8 readstring readu16 readu32 readu8 tostring writebits writef32 writef64 writei16 writei32 writei8 writestring writeu16 writeu32 writeu8` |
| `coroutine` | `close create isyieldable resume running status wrap yield` |
| `vector` | `abs angle ceil clamp create cross dot floor lerp magnitude max min normalize one sign zero` |
| `integer` | 64-bit integer functions (`create add sub mul div …`). `json.encode` writes an `integer` value as a number; nothing else about it was tested with the host modules, and the type stubs do not describe it |

Luau syntax is available: type annotations, string interpolation (`` `x is {x}` ``), `continue`, compound assignment (`+=`), `if … then … else` expressions, floor division `//`.

### Behaviour to know

- **`print`** writes its arguments to the host process's standard output. Under `plugin test` that is the terminal (the lines appear after the test report). In the app nothing shows it. It is not a result channel.
- **`math.random`** is present and seeded differently in every VM; `math.randomseed` works within a VM. Output that depends on it is not reproducible across devices, restarts or discarded VMs. Use [`@harness/rand`](host-api.md#harnessrand).
- **Built-in libraries are read-only.** `string.foo = 1`, `table.insert = nil`, `_G.x = 1`, `rawset(string, …)` and changing the string metatable all fail with `attempt to modify a readonly table`. String methods work (`("abc"):upper()`).
- **Global variables** can be created by plain assignment (`counter = 1`). They are shared by every module of the plugin for the life of the VM, and under `plugin test` by every test file. Prefer `local`.
- **Errors**: `error("msg")` and `assert(false, "msg")` produce the string `<file>:<line>: msg`; `error("msg", 0)` produces `msg`; `assert(false)` produces `<file>:<line>: assertion failed!`; `error({ code = 1 })` raises the table itself. Errors from host functions are error objects, not strings ([host-api.md](host-api.md#errors-raised-by-host-functions)).
- **Recursion** deeper than about 20 000 Lua calls is the catchable error `stack overflow` (19 996 frames measured for a simple function).
- `getfenv`/`setfenv` exist; `luau-analyze` flags `getfenv` as deprecated.
- `tostring` of numbers: `3` → `3`, `0.1 + 0.2` → `0.30000000000000004`, `10 / 3` → `3.3333333333333335`, `1e21` → `1e+21`, `1 / 0` → `inf`, `0 / 0` → `nan`. `string.format("%d", 3.7)` → `3`.

## JSON and Lua values

Values cross the boundary in both directions. The rules are the same everywhere and are the ones `json.decode` and `json.encode` expose, so both directions can be tested with those two functions.

### JSON → Lua

Used for tool arguments, the `data` given to a renderer, view call arguments, and `grade`'s `answer` and `target`.

| JSON | Lua |
|---|---|
| object | table with string keys |
| array | table with keys `1..n` |
| string, boolean | string, boolean |
| number | number. Every Luau number is a double: integers are exact up to 2^53 |
| `null` | `nil` |

Consequences:

- An object field that is `null` and a field that is absent are the same thing: `args.x == nil`.
- `null` inside an array leaves a hole. `[1, null, 3]` arrives with `#t == 1` and `ipairs` stops at the hole. If nulls are meaningful, ask for another encoding in the schema.
- `[]` and `{}` both arrive as an empty table.
- Object keys are strings, including `"1"`.
- A tool called without arguments, or a view `call` without `args`, passes `nil` or an empty table; test for both (`args = args or {}`).

### Lua → JSON

Used for a non-artifact tool's table result, `artifact.data`, view call results, `grade` results and `log.debug`.

| Lua | JSON |
|---|---|
| `nil` | `null` |
| boolean, string | the same (a string that is not valid UTF-8 becomes `""`) |
| number | integral values within the 64-bit integer range print as integers (`3.0` → `3`); other finite numbers with the shortest round-trip digits (`0.30000000000000004`, `1e+21`); NaN and ±infinity → `null`; `-0` → `-0.0` |
| table with no string keys and integer keys exactly `1..n` (n ≥ 1) | array |
| any other table | object: integer keys as strings, then string keys, sorted by byte value; other keys dropped |
| function, buffer, vector, userdata, thread | `null` |

Consequences:

- **An empty table is `{}`**, never `[]`. A view that expects a list must accept an empty object: `Array.isArray(data.items) ? data.items : []`.
- **A list with a hole is an object**: `{ 1, nil, 3 }` → `{"1":1,"3":3}`. Use a placeholder value (`false`, `""`) instead of `nil` inside lists.
- **A table with both list items and named fields is an object**: `{ "a", x = 1 }` → `{"1":"a","x":1}`.
- A field set to `nil` is omitted.
- Two errors are possible: `the value contains a table that refers to itself; it can't become JSON` and `the value nests deeper than 64 tables; it can't become JSON`. In a tool result either one makes the call a tool error.

Complete examples with output are in [host-api.md](host-api.md#harnessjson).

## Tool results

The texts in this section are from the app's source (`crates/harness/src/plugins/luau.rs`, `artifacts.rs`, `agent.rs`) and its unit tests; `plugin test` cannot exercise a tool call through the host.

### A tool without `artifact = true`

| Return value | Result text the model reads |
|---|---|
| a string | the string |
| a table with a `text` field that is a string (or a number) | that text |
| any other table | the table as JSON ([rules above](#lua--json)), e.g. `{ 'a', 'b' }` → `["a","b"]` |
| `nil` (or no return) | empty text |
| a number or boolean | its JSON text (`7`, `true`) |

Text longer than 16 KiB (16 384 bytes) is cut at a character boundary and `\n[result truncated at 16 KiB]` is appended. That is not an error.

### A tool with `artifact = true`

Exactly one shape is accepted:

```lua
return {
  text = "2 bars; the total is 9.",   -- optional; what the model reads
  artifact = {
    kind = "svg",                     -- required; the only kind in api 1
    svg = figure,                     -- required; the static figure, a string
    data = { … },                     -- optional; stored, and given to the view
  },
}
```

| Problem | Tool error (after `plugin error: `) |
|---|---|
| The return value is not a table | `an artifact tool must return { text = "…", artifact = { kind = "svg", svg = "<svg…>", data = {…} } }` |
| No `artifact` field (e.g. a flat `{ text, svg, data }`) | ``the result has no `artifact`; an artifact tool must return { … }`` |
| `artifact` is not a table | `` `artifact` must be a table; an artifact tool must return { … }`` |
| `artifact.kind` missing | `artifact.kind is required ("svg")` |
| `artifact.kind` is something else | ``artifact.kind `png` is not supported (only "svg")`` |
| `artifact.svg` missing or not a string | `artifact.svg is required (the static SVG figure)` |
| `artifact.data` cannot become JSON | `artifact.data: <one of the two conversion errors>` |
| `artifact.data` as JSON is larger than 256 KiB | `artifact.data is <n> KiB, over the 256 KiB limit; ask for less data (a smaller figure)` |

`text` is truncated at 16 KiB like any result; a `text` that is not a string counts as empty. An artifact tool cannot return plain text instead of a figure: to refuse a request, raise an error.

After a valid return the figure is sanitized and stored; that step can fail too. The model then reads `<tool name> refused: <message>`, with the messages listed in [artifacts-and-views.md](artifacts-and-views.md#the-sanitizer).

### Errors

| Situation | What the model reads |
|---|---|
| Lua error in the tool | `plugin error: runtime error: <file>:<line>: <message>` and a traceback |
| `entry` is not exported | ``plugin error: runtime error: the plugin exports no function `<entry>` `` |
| `src/main.luau` fails to load or does not return a table | `plugin error: runtime error: src/main.luau: <error>` |
| A wrong result shape of an artifact tool | `plugin error: <message from the table above>` |
| Time limit | `plugin error: plugin time limit (2000 ms) exceeded` |
| Memory limit | `plugin error: plugin memory limit: <detail>` (`plugin test` shows `plugin memory limit: not enough memory`) |

In every case the VM is discarded. The app keeps running and the model may retry.

## Limits

| Limit | Value | What happens beyond it |
|---|---|---|
| Tools per plugin | 3 | `4 tools (at most 3 per plugin)` |
| Renderers, views per plugin | 1 each | validation error |
| Prompt fragment | 250 words per agent | `prompts.<agent> has <n> words (about 200 at most)` |
| Plugins active in one plan section | 3 | the plan or request is refused (app side) |
| Memory per VM | 64 MiB | `plugin memory limit: …`; VM discarded |
| Time per tool call, per `grade` call | 2 000 ms | `plugin time limit (2000 ms) exceeded`; VM discarded |
| Time per view call | 200 ms | `plugin time limit (200 ms) exceeded`; VM discarded |
| Time per test file under `plugin test` | 10 000 ms | `plugin time limit (10000 ms) exceeded` |
| Tool result text | 16 KiB | cut, marked `[result truncated at 16 KiB]` |
| `artifact.data` as JSON | 256 KiB | tool error |
| Fallback SVG | 256 KiB | `the fallback SVG is <n> KiB (limit 256 KiB); ask for a simpler figure` |
| Table nesting when converting to JSON | 64 | `the value nests deeper than 64 tables; it can't become JSON` |
| JSON nesting in `json.decode` | 127 | `invalid JSON: recursion limit exceeded …` |
| Matrix or vector side in `num.mul` / `num.linsolve` | 400 | `…: matrices and vectors are limited to 400 rows and columns` |
| Lua call depth | about 20 000 | `stack overflow` |
| View state summary | 500 characters, latest per artifact | cut |
| Package | 16 MiB per file, 64 MiB unpacked, 16 MiB packed | refused by the registry check and by install |

The time limits are wall-clock, measured from the start of the call, and enforced between Luau instructions. A host function (for example `num.linsolve`) cannot be interrupted while it runs, which is why sizes are capped instead. A loop is stopped within the limit; the 10 s test limit was measured at 10.02 s.
