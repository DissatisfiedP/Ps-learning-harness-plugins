# Host API reference (api 1)

This file is the reference for the six modules a plugin can `require` from the host: `@harness/json`, `@harness/svg`, `@harness/num`, `@harness/rand`, `@harness/log`, and, under `plugin test` only, `@harness/test`. For each function it gives the signature, what it returns, every error it raises, and an example. Every output shown after `-->` was produced by the app's runtime through `plugin test` (app build of 2026-11-15, Luau 0.740), not written by hand. The type stubs for editors are in [`../plugin-api/`](../plugin-api/); how values cross between Lua and JSON in tool calls is in [package.md](package.md#json-and-lua-values).

The modules are pure: no I/O, no clock, no ambient randomness. There are no host globals; a module exists only after `require`:

```lua
local json = require("@harness/json")
local svg = require("@harness/svg")
local num = require("@harness/num")
local rand = require("@harness/rand")
local log = require("@harness/log")
```

Each `require` of the same module returns the same table for the life of the VM. The tables are not frozen, but do not add to them: the change is visible to every module of the plugin.

## Errors raised by host functions

Two things hold for every function below.

1. **A host error is not a string.** `pcall` gives back an error object (`type(e) == "userdata"`, `typeof(e) == "error"`). `tostring(e)` is the message followed by a stack traceback. `string.find(e, …)` and `"x" .. e` fail (`invalid argument #1 to 'find' (string expected, got error)`, `attempt to concatenate string with error`). Always convert first:

   ```lua
   local ok, e = pcall(json.decode, "{")
   local message = tostring(e)
   string.find(message, "invalid JSON", 1, true)   --> 16
   ```

   The message starts `runtime error: ` for errors the host raises on purpose, so `invalid JSON` begins at character 16. Errors raised by Luau itself (`error("x")`, `assert`, a failed `require` resolution) are ordinary strings.

2. **A wrong argument type is reported by position**, before the function runs:

   | Expected | Message |
   |---|---|
   | number | `bad argument #<n>: error converting Lua <type> to f64 (expected number or string coercible to number)` |
   | string | `bad argument #<n>: error converting Lua <type> to String (expected string or number)` |
   | table | `bad argument #<n>: error converting Lua <type> to table` |

   Numbers and numeric strings convert into each other silently where a number or a string is expected: `svg.rect("1", "2.5", "3", "4")` and `svg.text(1, 2, 42)` both work. Do not rely on it; the type stubs reject it.

In a running plugin an uncaught error ends the call as a tool error and discards the VM ([package.md](package.md#the-vm)).

## `@harness/json`

| Function | Returns |
|---|---|
| `json.encode(value: any): string` | Compact JSON text |
| `json.decode(text: string): any` | The Lua value |

### `json.encode(value)`

Returns compact JSON: no spaces, no newlines. The conversion is the one the host applies to every plugin value that leaves the VM (tool results, `artifact.data`, view call results, `grade` results, `log.debug`).

| Lua value | JSON |
|---|---|
| `nil` | `null` |
| boolean | `true` / `false` |
| string | string; `"`, `\`, control characters escaped (`\n`, `\t`, `\u0001`), non-ASCII and `/` left as they are. A string that is not valid UTF-8 becomes `""` |
| number, integral and within the 64-bit integer range | integer digits: `3`, `3.0` → `3`, `1e15` → `1000000000000000`, `2^53` → `9007199254740992` |
| other finite number | shortest digits that round-trip: `3.5`, `0.1 + 0.2` → `0.30000000000000004`, `1e21` → `1e+21`, `2^63` → `9.223372036854776e+18`, `1e-7` → `1e-7` |
| `-0` | `-0.0` |
| NaN, `math.huge`, `-math.huge` | `null` |
| table with no string keys whose integer keys are exactly `1..n`, n ≥ 1 | array |
| any other table, including `{}` | object |
| function, buffer, vector, thread, userdata | `null` |

Objects:

- Integer keys are written as strings, then string keys. Keys come out sorted by byte value, so `"10"` sorts before `"9"` and upper case before `_` before lower case.
- A whole-number key and the string with the same digits collide; the string key wins (`{ [1] = "int", ["1"] = "str" }` → `{"1":"str"}`).
- Keys that are neither strings nor whole numbers (booleans, fractions, tables) are dropped with their values; so are string keys that are not valid UTF-8.
- A field assigned `nil` does not exist in Lua, so it is not written.
- Metatables are ignored: only the table's own fields are written. Frozen tables encode normally.

```lua
json.encode({})                                      --> {}
json.encode({ 1, 2, 3 })                             --> [1,2,3]
json.encode({ [1] = 1, [3] = 3 })                    --> {"1":1,"3":3}
json.encode({ [2] = 2, [3] = 3 })                    --> {"2":2,"3":3}
json.encode({ [0] = 0, [1] = 1 })                    --> {"0":0,"1":1}
json.encode({ "a", x = 1 })                          --> {"1":"a","x":1}
json.encode({ 1, nil, 3 })                           --> {"1":1,"3":3}
json.encode({ a = nil, b = 1 })                      --> {"b":1}
json.encode({ t = true, f = false })                 --> {"f":false,"t":true}
json.encode({ f = function() end, n = 1 })           --> {"f":null,"n":1}
json.encode({ list = { 1, { 2, 3 } }, obj = { k = { "v" } }, empty = {} })
                                                     --> {"empty":{},"list":[1,[2,3]],"obj":{"k":["v"]}}
json.encode({ b = 1, a = 2, B = 3, ["10"] = 4, ["9"] = 5, _z = 6 })
                                                     --> {"10":4,"9":5,"B":3,"_z":6,"a":2,"b":1}
json.encode({ [true] = "x" })                        --> {}
json.encode(0 / 0)                                   --> null
json.encode(nil)                                     --> null
```

Errors:

| Message | When |
|---|---|
| `the value contains a table that refers to itself; it can't become JSON` | A table is reachable from itself. The same table used twice side by side is fine: `local s = {1}; json.encode({ a = s, b = s })` → `{"a":[1],"b":[1]}` |
| `the value nests deeper than 64 tables; it can't become JSON` | 64 tables inside each other encode; the 65th level is the error |

### `json.decode(text)`

Parses one JSON value.

| JSON | Lua |
|---|---|
| object | table with string keys |
| array | table with keys `1..n` |
| string, `true`, `false` | string, boolean |
| number | number (a double) |
| `null` | `nil` |

- `null` inside an array leaves a hole: `json.decode('[1,null,3]')` has `t[1] == 1`, `t[2] == nil`, `t[3] == 3` and `#t == 1`, and it encodes back as `{"1":1,"3":3}`. A trailing `null` vanishes (`[1,2,null]` → `#t == 2`), and `[null,null]` is an empty table.
- `null` as an object value means the key is absent (`{"a":null,"b":1}` → `{ b = 1 }`).
- `[]` and `{}` both become an empty table, which encodes back as `{}`. An empty array does not survive a round trip.
- Object keys stay strings: `json.decode('{"1":"a"}')["1"] == "a"`, and index `[1]` is `nil`. It encodes back as an object.
- Integers beyond 2^53 lose precision: `9007199254740993` decodes as `9007199254740992`; `12345678901234567890` encodes back as `1.2345678901234567e+19`.
- A duplicated key keeps the last value. `\u` escapes, including surrogate pairs, become UTF-8.
- A number argument is converted to its text first (`json.decode(12)` → `12`).

```lua
local v = json.decode('{"a":1,"b":[true,null]}')
-- v.a == 1, v.b[1] == true, v.b[2] == nil
```

Errors, all of the form `invalid JSON: <reason> at line <l> column <c>` (the reason text comes from the parser):

| Input | Message |
|---|---|
| `""` (empty) | `invalid JSON: EOF while parsing a value at line 1 column 0` |
| `{"a":` | `invalid JSON: EOF while parsing a value at line 1 column 5` |
| `{a:1}`, `{'a':1}` | `invalid JSON: key must be a string at line 1 column 2` |
| `[1,2,]` | `invalid JSON: trailing comma at line 1 column 6` |
| `1 2` | `invalid JSON: trailing characters at line 1 column 3` |
| `NaN`, `// x` | `invalid JSON: expected value at line 1 column 1` |
| `1e400` | `invalid JSON: number out of range at line 1 column 5` |
| 128 or more nested arrays/objects | `invalid JSON: recursion limit exceeded at line 1 column 128` |
| a table or `nil` argument | `bad argument #1: error converting Lua table to String (expected string or number)` |

### Gotchas

- Array or object is decided by the keys alone. To send a list that may be empty or sparse, the receiver must accept `{}`; there is no way to produce `[]`.
- Text decoded with up to 127 levels can be deeper than the 64 levels `encode` accepts.
- `encode` output is deterministic (sorted keys), so it is safe in golden files.

## `@harness/svg`

Each function returns a string of markup. Build a figure by concatenating strings and wrapping them with `svg.document`.

| Function | Output |
|---|---|
| `svg.document(width, height, content)` | `<svg xmlns=… width height viewBox fill="none" stroke="currentColor">content</svg>` |
| `svg.group(attrs?, content)` | `<g …>content</g>` |
| `svg.path(d, attrs?)` | `<path … d="…"/>` |
| `svg.line(x1, y1, x2, y2, attrs?)` | `<line … x1 y1 x2 y2/>` |
| `svg.rect(x, y, w, h, attrs?)` | `<rect … x y width height/>` |
| `svg.circle(cx, cy, r, attrs?)` | `<circle … cx cy r/>` |
| `svg.text(x, y, text, attrs?)` | `<text … x y>escaped text</text>` |
| `svg.escape(text)` | `text` with `&`, `<`, `>` escaped |

### Rules shared by the builders

**Attribute order.** Attributes from the `attrs` table come first, sorted by name in byte order; the function's positional attributes follow in the fixed order shown above.

```lua
svg.rect(1, 2, 30, 40, { rx = 4, fill = "currentColor", ["fill-opacity"] = 0.2 })
--> <rect fill="currentColor" fill-opacity="0.2" rx="4" x="1" y="2" width="30" height="40"/>
svg.rect(0, 0, 1, 1, { b = 1, a = 2, B = 3, ["a-b"] = 4, _c = 5 })
--> <rect B="3" _c="5" a="2" a-b="4" b="1" x="0" y="0" width="1" height="1"/>
```

**Attribute values.** `attrs` is `{ [string]: string | number | boolean }`. Booleans are written as `true`/`false`. A value of any other type (table, function, `nil`) is skipped without an error. Values are escaped: `&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`, `"` → `&quot;`, `'` → `&#39;`.

```lua
svg.rect(0, 0, 1, 1, { ["data-x"] = "a<b>&\"q\"'s'" })
--> <rect data-x="a&lt;b&gt;&amp;&quot;q&quot;&#39;s&#39;" x="0" y="0" width="1" height="1"/>
svg.rect(0, 0, 1, 1, { hidden = true, a = {}, c = "kept" })
--> <rect c="kept" hidden="true" x="0" y="0" width="1" height="1"/>
```

**Numbers.** Coordinates and numeric attribute values print with the shortest digits that round-trip and never with an exponent. Whole numbers have no fraction.

| Lua | Printed |
|---|---|
| `3`, `3.0` | `3` |
| `2.50` | `2.5` |
| `10 / 3` | `3.3333333333333335` |
| `0.1 + 0.2` | `0.30000000000000004` |
| `1e21` | `1000000000000000000000` |
| `1e-7` | `0.0000001` |
| `-0` | `-0` |
| `0 / 0`, `1 / 0`, `-1 / 0` | `NaN`, `inf`, `-inf` |

Round before drawing; `NaN` and `inf` are not valid SVG lengths and nothing rejects them.

```lua
svg.line(0.1 + 0.2, 10 / 3, 0, 0)
--> <line x1="0.30000000000000004" y1="3.3333333333333335" x2="0" y2="0"/>
svg.line(math.round(3.3333 * 100) / 100, 0, 0, 0)
--> <line x1="3.33" y1="0" x2="0" y2="0"/>
```

**Empty content.** An element whose content is the empty string is self-closing: `svg.group({ id = "e" }, "")` → `<g id="e"/>`, `svg.text(1, 2, "")` → `<text x="1" y="2"/>`.

**Refused attributes.**

| Message | When |
|---|---|
| ``SVG attribute `<name>` is not allowed`` | The name starts with `on` in any letter case: `onclick`, `ONLOAD`, and also `only`. `opacity` is fine. Not raised when the value is of a skipped type |
| `external SVG references are not allowed` | `href` or `xlink:href` (any letter case) whose value does not start with `#` or `data:image/`. A number as the value is refused too |

The builder lets `href = "data:image/svg+xml;…"` and `style = "…"` through; the sanitizer removes both when the figure is stored ([artifacts-and-views.md](artifacts-and-views.md#the-sanitizer)).

### `svg.document(width: number, height: number, content: string): string`

Wraps `content` (markup, inserted as it is) in the root element. It takes no attributes.

```lua
svg.document(120, 40, "")
--> <svg xmlns="http://www.w3.org/2000/svg" width="120" height="40" viewBox="0 0 120 40" fill="none" stroke="currentColor"></svg>
svg.document(100, 50, svg.line(0, 0, 10, 0))
--> <svg xmlns="http://www.w3.org/2000/svg" width="100" height="50" viewBox="0 0 100 50" fill="none" stroke="currentColor"><line x1="0" y1="0" x2="10" y2="0"/></svg>
```

The root sets `fill="none"` and `stroke="currentColor"`, and children inherit both: shapes are outlines in the UI's text colour, and **text is outlined too** unless it sets `fill` and `stroke` itself.

### `svg.group(attrs: Attributes?, content: string): string`

`attrs` is the first parameter and may be `nil`, but it must be passed.

```lua
svg.group(nil, "<a/>")                                  --> <g><a/></g>
svg.group({ transform = "translate(10,10)" }, svg.circle(0, 0, 4))
--> <g transform="translate(10,10)"><circle cx="0" cy="0" r="4"/></g>
svg.group("<a/>")   -- error: bad argument #1: error converting Lua string to table
```

`content` is not escaped: `svg.group(nil, "a<b&c")` → `<g>a<b&c</g>`, which is not well-formed and makes the artifact a tool error.

### `svg.path(d: string, attrs: Attributes?): string`

`d` is escaped as an attribute value and not checked as path data.

```lua
svg.path("M0 0L10 10Z")                              --> <path d="M0 0L10 10Z"/>
svg.path("M0 0", { stroke = "red", ["stroke-width"] = 2, fill = "none" })
--> <path fill="none" stroke="red" stroke-width="2" d="M0 0"/>
```

### `svg.line(x1, y1, x2, y2, attrs?)`, `svg.rect(x, y, w, h, attrs?)`, `svg.circle(cx, cy, r, attrs?)`

```lua
svg.line(0, 1.5, 2, 3, { ["stroke-dasharray"] = "4 2" })
--> <line stroke-dasharray="4 2" x1="0" y1="1.5" x2="2" y2="3"/>
svg.rect(1, 2, 30, 40)       --> <rect x="1" y="2" width="30" height="40"/>
svg.circle(5, 6, 7, { fill = "currentColor", stroke = "none" })
--> <circle fill="currentColor" stroke="none" cx="5" cy="6" r="7"/>
```

A missing coordinate is `bad argument #<n>: error converting Lua nil to f64 (expected number or string coercible to number)`; a string where `attrs` belongs is `bad argument #5: error converting Lua string to table`.

### `svg.text(x: number, y: number, text: string, attrs: Attributes?): string`

`text` has `&`, `<` and `>` escaped; quotes are left alone. `nil` text is `bad argument #3: error converting Lua nil to String (expected string or number)`.

```lua
svg.text(1, 2, "a < b & \"c\" > 'd'")
--> <text x="1" y="2">a &lt; b &amp; "c" &gt; 'd'</text>
svg.text(10, 20, "R₁ = 1 kΩ", { fill = "currentColor", stroke = "none", ["text-anchor"] = "middle", ["font-size"] = 12 })
--> <text fill="currentColor" font-size="12" stroke="none" text-anchor="middle" x="10" y="20">R₁ = 1 kΩ</text>
```

### `svg.escape(text: string): string`

Escapes `&`, `<`, `>`. It is for element text in markup written by hand. It does not escape quotes, so it is not sufficient for an attribute value, and it does not detect text that is already escaped.

```lua
svg.escape("a < b & \"c\" > 'd'")   --> a &lt; b &amp; "c" &gt; 'd'
svg.escape("&amp;")                 --> &amp;amp;
```

### Elements without a builder

There is no builder for `polygon`, `polyline`, `ellipse`, `defs`, `marker`, `linearGradient`, `tspan`, `use`, `image` or `clipPath`, and `svg.document` cannot be given extra root attributes. Write the markup as a string. Format numbers yourself, and pass any text that comes from tool input through `svg.escape`. The sanitizer keeps all of these elements.

```lua
local points = {}
for _, p in ipairs({ { 0, 0 }, { 10, 0 }, { 5, 8.66 } }) do
  points[#points + 1] = string.format("%g,%g", p[1], p[2])
end
local triangle = '<polygon points="' .. table.concat(points, " ") .. '" fill="currentColor"/>'
--> <polygon points="0,0 10,0 5,8.66" fill="currentColor"/>

local label = '<text x="0" y="12" stroke="none" fill="currentColor">'
  .. svg.escape("V")
  .. '<tspan baseline-shift="sub" font-size="8">' .. svg.escape("out & in") .. "</tspan></text>"
--> <text x="0" y="12" stroke="none" fill="currentColor">V<tspan baseline-shift="sub" font-size="8">out &amp; in</tspan></text>
```

For an attribute value built by hand from untrusted text, escape `&`, `<`, `>`, `"` yourself (`string.gsub`), or wrap the element in `svg.group` and put the value in its `attrs`.

### Gotchas

- **Positional attributes cannot be overridden cleanly.** Passing `x` to `svg.rect`, or `d` to `svg.path`, emits the attribute twice:

  ```lua
  svg.rect(1, 2, 30, 40, { x = 9 })   --> <rect x="9" x="1" y="2" width="30" height="40"/>
  ```

  That is not well-formed XML. The core sanitizer does not refuse it: it keeps the first occurrence, so the stored figure has `x="9"`, the value from `attrs`. Golden files and anything that parses the raw string see both. Do not rely on it.
- **Integer keys in `attrs` become attribute names.** `svg.rect(0, 0, 1, 1, { "a", k = "v" })` → `<rect 1="a" k="v" …/>`. Use string keys only.
- **Text needs its own paint.** Under `svg.document`, `svg.text(…)` without `fill` is drawn as hollow outlines. Use `{ fill = "currentColor", stroke = "none" }`.
- **Use `currentColor`**, not fixed colours, so the figure follows the light and dark themes; `style` attributes and `<style>` elements are removed when the figure is stored.
- **Do not call with `:`.** `svg:rect(0, 0, 1, 1)` passes the module as `x`: `bad argument #1: error converting Lua table to f64 …`.
- **Size limit.** A stored figure may be at most 256 KiB; full-precision coordinates in long paths add up.

## `@harness/num`

Real and complex arithmetic, matrix products and a dense linear solve.

```lua
export type Complex = { re: number, im: number }
export type Number = number | Complex
export type Matrix = { { Number } }   -- non-empty list of rows
export type Vector = { Number }       -- flat list
```

**What counts as a number.** A plain Lua number, or a table with a numeric `re` field (`im` defaults to 0; a non-numeric `im` reads as 0; other fields are ignored). Everything else is not a number and raises the function's error: `{}`, `{ im = 1 }`, a list such as `{ 1, 2 }`, a string, `nil`.

**What comes back.** A function returning `Number` returns a plain number when the absolute imaginary part is below `1e-12`, and otherwise a new table `{ re = …, im = … }`. The same holds for every element of a returned vector or matrix.

```lua
num.c(3, 4)        --> { re = 3, im = 4 }      (type "table")
num.c(3)           --> 3                       (type "number")
num.c(3, 1e-13)    --> 3
num.c(3, 1e-12)    --> { re = 3, im = 1e-12 }
```

| Function | Returns | Error |
|---|---|---|
| `num.c(re: number, im: number?): Number` | `re + im·i` | `bad argument #1: error converting Lua nil to f64 (expected number or string coercible to number)` |
| `num.add(a, b): Number` | `a + b` | `add expects numbers` |
| `num.sub(a, b): Number` | `a - b` | `sub expects numbers` |
| `num.mul(a, b)` | product, three forms (below) | `mul: …` |
| `num.div(a, b): Number` | `a / b` | `div expects numbers` |
| `num.abs(a): number` | magnitude | `abs expects a number` |
| `num.phaseDeg(a): number` | argument in degrees, from -180 to 180; 0 for 0 | `phaseDeg expects a number` |
| `num.conj(a): Number` | conjugate | `conj expects a number` |
| `num.real(a): number` | real part | `real expects a number` |
| `num.imag(a): number` | imaginary part, not rounded | `imag expects a number` |
| `num.linsolve(a: Matrix, b: Vector): Vector` | `x` with `a·x = b` | below |

```lua
num.add(1, 2)                              --> 3
num.add(num.c(1, 2), num.c(3, -1))         --> { re = 4, im = 1 }
num.add(num.c(1, 2), num.c(3, -2))         --> 4
num.add(0.1, 0.2)                          --> 0.30000000000000004
num.sub(5, num.c(2, 1))                    --> { re = 3, im = -1 }
num.div(1, 4)                              --> 0.25
num.div(1, num.c(0, 1))                    --> { re = 0, im = -1 }
num.abs(num.c(3, 4))                       --> 5
num.abs(-2)                                --> 2
num.phaseDeg(num.c(0, 1))                  --> 90
num.phaseDeg(-1)                           --> 180
num.phaseDeg(num.c(0, -1))                 --> -90
num.conj(num.c(1, 2))                      --> { re = 1, im = -2 }
num.real(num.c(1, 2)), num.imag(num.c(1, 2))   --> 1, 2
num.real(7), num.imag(7)                   --> 7, 0
num.add({}, 2)        -- error: add expects numbers
num.add({ im = 1 }, 2) -- error: add expects numbers
num.add("1", 2)       -- error: add expects numbers
```

### `num.mul(a, b)`

```lua
num.mul: ((a: Matrix, b: Vector) -> Vector)
       & ((a: Matrix, b: Matrix) -> Matrix)
       & ((a: Number, b: Number) -> Number)
```

The first argument decides the form. If it is a matrix, the second must be a vector (result: one element per matrix row) or a matrix (rows of `a` times columns of `b`). Otherwise both must be numbers.

```lua
num.mul(3, 4)                                               --> 12
num.mul(num.c(0, 1), num.c(0, 1))                           --> -1
num.mul(num.c(1, 2), num.c(3, 4))                           --> { re = -5, im = 10 }
num.mul({ { 1, 2 }, { 3, 4 } }, { 5, 6 })                   --> { 17, 39 }
num.mul({ { 1, 2 }, { 3, 4 } }, { { 0, 1 }, { 1, 0 } })     --> { { 2, 1 }, { 4, 3 } }
num.mul({ { 1, 2, 3 }, { 4, 5, 6 } }, { { 1 }, { 2 }, { 3 } })  --> { { 14 }, { 32 } }
num.mul({ { num.c(0, 1), 1 } }, { num.c(0, 1), num.c(2, 3) })   --> { { re = 1, im = 3 } }
```

| Message | When |
|---|---|
| `mul: expects two numbers, a matrix and a vector, or two matrices` | The first argument is not a matrix and the two are not both numbers: `num.mul(2, { { 1 } })`, `num.mul({ 1, 2 }, { 3, 4 })`, `num.mul({ 1, 2 }, 3)`, `num.mul("a", 2)`, `num.mul({}, {})` |
| `mul: the matrix's rows have different lengths` | The first argument is ragged |
| `mul: a matrix with <k> columns needs a vector of <k> numbers, got <n>` | Matrix × vector of the wrong length, also an empty list (`got 0`) |
| `mul: a matrix multiplies a vector or a matrix` | Matrix × number, matrix × string |
| `mul: matrix shapes don't match` | Matrix × matrix where `b` does not have as many rows as `a` has columns, or `b` is ragged |
| `mul: matrices and vectors are limited to 400 rows and columns` | Either argument has more than 400 rows or a row with more than 400 elements; 400 is accepted |

There is no scalar × matrix, vector × vector or vector × scalar; loop over the elements.

### `num.div` and division by zero

No function raises an error for division by zero, overflow or NaN input. `num.div(x, 0)` returns a complex table whose parts are both NaN, for every `x` including real ones (it is not `inf`):

```lua
local z = num.div(1, 0)
type(z)                                   --> table
num.real(z), num.imag(z), num.abs(z)      --> nan, nan, nan
json.encode(z)                            --> {"im":null,"re":null}
```

Check the divisor before dividing.

### `num.linsolve(a: Matrix, b: Vector): Vector`

Solves `a·x = b` by Gaussian elimination with partial pivoting. `a` must be square (n×n) and `b` must have n elements; both may contain complex numbers. Returns a new list of n `Number`s and leaves its arguments unchanged.

```lua
num.linsolve({ { 2, 1 }, { 1, 3 } }, { 3, 5 })     --> { 0.8, 1.4 }
num.linsolve({ { 2 } }, { 6 })                     --> { 3 }
num.linsolve({ { 0, 1 }, { 1, 0 } }, { 2, 3 })     --> { 3, 2 }
num.linsolve({ { num.c(1, 1), 0 }, { 0, num.c(0, 2) } }, { 2, 4 })
                                                   --> { { re = 1, im = -1 }, { re = 0, im = -2 } }
num.linsolve({ { 3 } }, { 1 })                     --> { 0.3333333333333333 }
```

| Message | When |
|---|---|
| `linsolve expects a matrix` | `a` is not a non-empty list of lists of numbers: a number, `{}`, a flat list, rows holding strings (`{ { "2" } }`) |
| `linsolve expects a vector` | `b` is not a flat list of numbers: a number, a list of lists, a list of strings |
| `linsolve shapes don't match` | `#b` differs from the number of rows |
| `the matrix is singular (no unique solution)` | A pivot with magnitude below `1e-14` (so `{ { 1e-15 } }` counts as singular), and also a non-square or ragged `a` |
| `linsolve: matrices and vectors are limited to 400 rows and columns` | More than 400 rows, columns or vector elements |

The solve runs in host code that the time limit cannot interrupt, which is why the size is capped.

### Worked example

```lua
local jw = num.mul(num.c(0, 1), 2 * math.pi * 50)   -- jω at 50 Hz
local zc = num.div(1, num.mul(jw, 1e-6))            -- 1/(jωC), C = 1 µF
local z = num.add(1000, zc)                         -- R + 1/(jωC)
--> z = { re = 1000, im = -3183.098861837907 }
num.abs(z)        --> 3336.4829333047364
num.phaseDeg(z)   --> -72.55940550948813
```

### Gotchas

- **Treat every result as `number | Complex`.** `num.mul(num.c(0, 1), num.c(0, 1))` is the number `-1`, so `result.re` is an error (`attempt to index number with 're'`). Read results with `num.real`, `num.imag`, `num.abs`, `num.phaseDeg`, which accept both.
- **Tiny imaginary parts vanish** (below `1e-12` in absolute terms, regardless of the size of the real part). `num.imag` on a table you built yourself does not round: `num.imag({ re = 1, im = 1e-13 })` → `1e-13`.
- **Results are full-precision doubles.** Format them for people (`string.format("%.4g", x)`) and round before drawing.
- **Complex numbers encode as objects**: `json.encode(num.c(1, 2))` → `{"im":2,"re":1}`. Views receive that shape in `artifact.data`.
- Numeric strings are not numbers here (`num.add("1", 2)` fails), unlike in `svg` and `num.c`, which coerce them.

## `@harness/rand`

| Function | Returns |
|---|---|
| `rand.seeded(seed: number): Rng` | A new generator |
| `rng.next(): number` | Uniform in [0, 1) |
| `rng.range(lo: number, hi: number): number` | `lo + (hi - lo) * next()` |
| `rng.int(lo: number, hi: number): number` | Whole number in [lo, hi], both included |

The generator is xorshift64. The same seed gives the same sequence on every device and in every replay. Two generators are independent, even with the same seed. Each call to any of the three functions advances the state by one step.

```lua
local rng = rand.seeded(42)
rng.next(), rng.next(), rng.next()
--> 2.4641099161115676e-09, 0.6251627798119515, 0.543262100969348

local dice = rand.seeded(42)
-- ten calls of dice.int(1, 6):
--> 4, 1, 4, 1, 5, 6, 1, 1, 6, 6

local r = rand.seeded(42)
r.range(10, 20), r.range(10, 20), r.range(10, 20)
--> 10.0000000246411, 16.251627798119515, 15.43262100969348
```

### `rand.seeded(seed)`

`seed` must be a whole number, 0 or more and below 2^64. `0` is replaced by `1`:

```lua
rand.seeded(1).next()   --> 5.866995778092132e-11
rand.seeded(0).next()   --> 5.866995778092132e-11
rand.seeded(2).next()   --> 1.1733991556184264e-10
```

| Seed | Result |
|---|---|
| `1.0`, `"42"` | accepted (same as `1`, `42`) |
| `-1` | `bad argument #1: error converting Lua integer to u64 (out of range)` |
| `1.5`, `2^64`, `1e30`, NaN, infinity | `bad argument #1: error converting Lua number to u64 (out of range)` |
| `"x"`, `nil` | `bad argument #1: error converting Lua <type> to u64 (expected number or string coercible to number)` |

Seeds above 2^53 are not exact as Lua numbers; neighbouring values may be the same seed.

### `rng.next()`, `rng.range(lo, hi)`, `rng.int(lo, hi)`

- `range` with `lo > hi` returns a value in (hi, lo] (`rand.seeded(42).range(20, 10)` → `19.9999999753589`); with `lo == hi` it returns `lo`.
- `int` reduces by modulo, so very large spans are slightly biased. With `hi < lo` it always returns `lo` (`rand.seeded(42).int(6, 1)` → `6`). `int(3, 3)` → `3`. Negative bounds work (`int(-3, 3)`).
- `int` needs whole numbers: `int(1.5, 6)` is `bad argument #1: error converting Lua number to i64 (out of range)`. `1.0` and `"1"` are accepted.
- Any two whole numbers in the 64-bit integer range work, however far apart. App builds from before 2026-11-15 failed when `hi - lo` reached 2^63 (`int(-2^62, 2^62)` raised `attempt to subtract with overflow`); a plugin that must run on those keeps its spans below that.

A shuffle (Fisher–Yates):

```lua
local rng = rand.seeded(2026)
local t = { "a", "b", "c", "d", "e" }
for i = #t, 2, -1 do
  local j = rng.int(1, i)
  t[i], t[j] = t[j], t[i]
end
table.concat(t)   --> ecdba
```

### Gotchas

- **Call with `.`, not `:`.** The functions are closures, not methods. `rng:next()` happens to work (extra arguments are ignored); `rng:int(1, 6)` is `bad argument #1: error converting Lua table to i64 (expected number or string coercible to number)` and `rng:range(1, 6)` the same with `f64`.
- **Small seeds start small.** The first `next()` of seed `n` is about `n × 5.87e-11`, and `range` inherits it (`10.0000000246411` above). The second value on is well mixed. If the first value matters, call `rng.next()` once and discard it.
- **The seed must come from the tool input** (or a constant). A plugin has no clock. `math.random` exists in the sandbox but is seeded differently in every VM (two runs gave `0.3735062380500071` and `0.7287047716145907` as the first value); a figure that uses it cannot be reproduced. Use `@harness/rand`.
- **Order matters.** Inserting one more `rng.*` call shifts everything after it; give independent parts their own generator (`rand.seeded(seed)`, `rand.seeded(seed + 1)`).

## `@harness/log`

`log.debug(value: any): ()`

Converts `value` to JSON with the `json.encode` rules and emits it as one debug-level `tracing` event with target `plugin`. Returns nothing. It raises the two `json.encode` errors (a self-referential table, more than 64 levels).

```lua
log.debug({ step = "solve", n = 3 })
```

The event is never shown to the model or the learner, and it is not a result channel. Who else sees it depends on the program running the plugin, which decides where the app core's `tracing` events go:

| Program | `log.debug` lines |
|---|---|
| `plugin test` | on standard error as they happen, one line each: `2026-11-15T09:50:22.397575Z DEBUG plugin: {"n":3,"step":"solve"}`. The test report goes to standard output, so `2>/dev/null` hides them |
| the app | on its standard error only when it is started with `PS_LEARN_LOG=debug` (it shows `info` and above otherwise) |

`PS_LEARN_LOG` (`error`, `warn`, `info`, `debug`, `trace`) sets the level for either; `PS_LEARN_LOG=warn plugin test <dir>` silences the lines. App builds from before 2026-11-15 installed no `tracing` subscriber, so there `log.debug` printed nothing anywhere.

`print` also works for development output: it writes to the host process's standard output, visible in the terminal under `plugin test` (after the test report, because of buffering) and invisible in the app.

## `@harness/test`

Exists only in the VM `plugin test` creates, for `tests/*.luau` and anything they require (a module in `src/` required from a test can require it too). In a running plugin, `require("@harness/test")` is the error ``@harness/test is only available under `plugin test` ``.

`test.golden(name: string, text: string): ()`

Compares `text` with the file `tests/golden/<name>`, byte for byte. Returns nothing when they are equal.

With the environment variable `PLUGIN_UPDATE_GOLDEN` set to exactly `1`, it writes `text` to the file instead (creating sub-folders as needed) and does not compare. Every `golden` call in the run writes; the last call for a name wins.

```lua
local golden = require("@harness/test").golden
golden("two-bars.svg", main.show(args).artifact.svg)
```

| Message | When |
|---|---|
| `golden file tests/golden/<name> missing (run with PLUGIN_UPDATE_GOLDEN=1 to write it)` | The file cannot be read (also when `<name>` is a folder) |
| `golden tests/golden/<name> differs at line <n>:` followed by `  got:  <line>` and `  want: <line>` | First differing line, counted from 1. `got` is `text`, `want` is the file |
| ``golden: `<name>` must be a relative path inside tests/golden`` | `name` is empty, starts with `/`, contains a backslash, or contains `..` anywhere (`../x`, `sub/../x`, and also `a..txt`) |
| `bad argument #2: error converting Lua <type> to String (expected string or number)` | `text` is `nil` or a table |

Observed mismatch reports, with the file holding `line1\nline2\nline3\n`:

```text
golden tests/golden/a.txt differs at line 2:
  got:  LINE2
  want: line2

golden tests/golden/a.txt differs at line 3:
  got:  <end of text>
  want: line3

golden tests/golden/a.txt differs at line 4:
  got:  line4
  want: <end of file>
```

### Gotchas

- **Trailing newlines and line endings count** for equality but are invisible in the report: a text that differs from the file only by a final newline, or by `\r\n` line endings, reports `differs at line <last + 1>` with `got:  <end of text>` and `want: <end of file>`. This repository's `.gitattributes` checks every text file out with LF endings, `*.svg` included.
- Sub-folders are allowed (`golden("cards/a.svg", …)`).
- Review the diff of a golden after updating it; update mode accepts anything.
- Only deterministic text belongs in a golden: no `math.random`, and when output is built by iterating a table with string keys, sort the keys first.
