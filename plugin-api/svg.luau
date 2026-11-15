--[=[
	`require("@harness/svg")`, api 1. Reference: docs/host-api.md
	("@harness/svg") and docs/artifacts-and-views.md ("The sanitizer") in
	this repository. Types only: the harness supplies the real module at
	runtime.

	Every function returns a string of SVG markup. Rules shared by all:

	- Attributes from an `attrs` table come first, sorted by name in byte
	  order (upper case, then `_`, then lower case); the function's own
	  positional attributes (`x`, `y`, `d`, …) follow in a fixed order. The
	  output is therefore deterministic.
	- Attribute values are escaped (`&` `<` `>` `"` `'` → `&amp;` `&lt;`
	  `&gt;` `&quot;` `&#39;`). Text given to `svg.text`/`svg.escape` has
	  `&`, `<`, `>` escaped. `content` arguments are markup and are inserted
	  as they are.
	- Numbers print with Rust's shortest round-trip digits and no exponent:
	  `3` → `3`, `10 / 3` → `3.3333333333333335`, `0.1 + 0.2` →
	  `0.30000000000000004`, `1e21` → `1000000000000000000000`, NaN → `NaN`,
	  infinity → `inf`. Round coordinates yourself.
	- An element with empty content is self-closing (`<g/>`, `<text …/>`).
	- There is no builder for `polygon`, `polyline`, `ellipse`, `defs`,
	  `marker`, `tspan`, `use`, …: write those as strings and pass text
	  through `svg.escape`.

	Errors every function can raise:
	- a wrong argument type: `bad argument #<n>: error converting Lua <type>
	  to f64 (expected number or string coercible to number)` for a
	  coordinate, `… to String (expected string or number)` for text/content,
	  `… to table` for `attrs` (numeric strings and numbers are coerced);
	- ``SVG attribute `<name>` is not allowed`` for an attribute whose name
	  starts with `on` in any letter case (`onclick`, but also `only`);
	- `external SVG references are not allowed` for `href`/`xlink:href`
	  whose value does not start with `#` or `data:image/`.
]=]

--[=[
	Attribute name → value. Strings, numbers and booleans (`true`/`false`)
	are written; a value of any other type is skipped without an error.
	Use string keys only: an integer key is written as the attribute name
	`1`, which is not XML. Do not repeat an attribute the function sets
	itself (`x` for `svg.rect`, `d` for `svg.path`, …): both are emitted, and
	when the figure is stored the sanitizer keeps the first one, the value
	from `attrs`.
]=]
export type Attributes = { [string]: string | number | boolean }

local svg = {}

--[=[
	A complete document:
	`<svg xmlns="http://www.w3.org/2000/svg" width="W" height="H"
	viewBox="0 0 W H" fill="none" stroke="currentColor">content</svg>`.
	Takes no attributes. Because of the root `fill="none"` and
	`stroke="currentColor"`, shapes are outlines in the UI's text colour
	unless they set their own, and text is outlined, not filled: give
	`svg.text` `{ fill = "currentColor", stroke = "none" }`.

	```lua
	svg.document(100, 50, svg.line(0, 0, 10, 0))
	--> <svg xmlns="http://www.w3.org/2000/svg" width="100" height="50" viewBox="0 0 100 50" fill="none" stroke="currentColor"><line x1="0" y1="0" x2="10" y2="0"/></svg>
	```
]=]
function svg.document(width: number, height: number, content: string): string
	return nil :: any
end

--[=[
	`<g attrs>content</g>`; `<g attrs/>` when `content` is empty. `attrs`
	comes first and may be `nil`, but must be passed: `svg.group(content)`
	is `bad argument #1: error converting Lua string to table`.

	```lua
	svg.group({ transform = "translate(10,10)" }, svg.circle(0, 0, 4))
	--> <g transform="translate(10,10)"><circle cx="0" cy="0" r="4"/></g>
	```
]=]
function svg.group(attrs: Attributes?, content: string): string
	return nil :: any
end

--[=[
	`<path attrs d="…"/>`. `d` is escaped like an attribute value and not
	checked as path data.

	```lua
	svg.path("M0 0L10 10", { ["stroke-width"] = 2 })
	--> <path stroke-width="2" d="M0 0L10 10"/>
	```
]=]
function svg.path(d: string, attrs: Attributes?): string
	return nil :: any
end

--[=[
	`<line attrs x1="…" y1="…" x2="…" y2="…"/>`.

	```lua
	svg.line(0, 0, 10, 0)   --> <line x1="0" y1="0" x2="10" y2="0"/>
	```
]=]
function svg.line(x1: number, y1: number, x2: number, y2: number, attrs: Attributes?): string
	return nil :: any
end

--[=[
	`<rect attrs x="…" y="…" width="…" height="…"/>`.

	```lua
	svg.rect(0, 0, 40, 12, { rx = 2 })
	--> <rect rx="2" x="0" y="0" width="40" height="12"/>
	```
]=]
function svg.rect(x: number, y: number, w: number, h: number, attrs: Attributes?): string
	return nil :: any
end

--[=[
	`<circle attrs cx="…" cy="…" r="…"/>`.

	```lua
	svg.circle(5, 6, 7)   --> <circle cx="5" cy="6" r="7"/>
	```
]=]
function svg.circle(cx: number, cy: number, r: number, attrs: Attributes?): string
	return nil :: any
end

--[=[
	`<text attrs x="…" y="…">escaped text</text>`; `&`, `<`, `>` in `text`
	are escaped, quotes are left. A number is accepted as text; `nil` is an
	error. Empty text gives `<text …/>`. Useful attributes: `text-anchor`,
	`font-size`, `font-weight`, `fill`, `stroke`, `class`.

	```lua
	svg.text(10, 20, "a < b", { fill = "currentColor", stroke = "none" })
	--> <text fill="currentColor" stroke="none" x="10" y="20">a &lt; b</text>
	```
]=]
function svg.text(x: number, y: number, text: string, attrs: Attributes?): string
	return nil :: any
end

--[=[
	Escapes `&`, `<`, `>` for use as element text in markup you write
	yourself. It does not escape quotes, so it is not enough for an
	attribute value, and it escapes again what is already escaped
	(`&amp;` → `&amp;amp;`).

	```lua
	svg.escape("a < b & c")   --> a &lt; b &amp; c
	```
]=]
function svg.escape(text: string): string
	return nil :: any
end

return svg
