--[=[
	`require("@harness/json")`, api 1. Reference: docs/host-api.md
	("@harness/json") and docs/package.md ("JSON and Lua values") in this
	repository. Types only: the harness supplies the real module at runtime.

	The Lua → JSON rules below are the ones the host uses everywhere a plugin
	value leaves the VM: tool results, `artifact.data`, view call results,
	`grade` results and `log.debug`.
]=]

local json = {}

--[=[
	Returns `value` as compact JSON text (no spaces, no newlines).

	Conversion:
	- `nil` → `null`; booleans and strings as themselves. A string that is
	  not valid UTF-8 becomes `""`.
	- Numbers: an integral value that fits a 64-bit integer prints without a
	  fraction (`3`, `1e15` → `1000000000000000`); other numbers print with
	  the shortest digits that round-trip (`0.1 + 0.2` →
	  `0.30000000000000004`, `1e21` → `1e+21`). NaN and ±infinity → `null`.
	- A table is an ARRAY only when it has no string keys and its integer
	  keys are exactly 1..n (n ≥ 1). Every other table is an OBJECT: integer
	  keys are written as strings, then string keys; keys come out in byte
	  order (`"10"` before `"9"`, upper case before lower case). So `{}` →
	  `{}`, `{ [1] = "a", [3] = "c" }` → `{"1":"a","3":"c"}` and
	  `{ "a", x = 1 }` → `{"1":"a","x":1}`.
	- A field set to `nil` does not exist, so it is not written; a `nil` in
	  the middle of a list makes it an object (`{ 1, nil, 3 }` →
	  `{"1":1,"3":3}`).
	- Keys that are neither strings nor whole numbers (booleans, fractions,
	  tables) are dropped with their values. Functions, buffers, vectors,
	  threads and userdata as VALUES become `null`. Metatables are ignored.

	Errors:
	- `the value contains a table that refers to itself; it can't become JSON`
	  (a table reachable from itself; a table used twice side by side is fine);
	- `the value nests deeper than 64 tables; it can't become JSON`.

	```lua
	json.encode({ ok = true, list = { 1, 2 }, none = {} })
	--> {"list":[1,2],"none":{},"ok":true}
	```
]=]
function json.encode(value: any): string
	return nil :: any
end

--[=[
	Parses JSON text and returns the Lua value: objects → tables with string
	keys, arrays → 1-based tables, strings, booleans, numbers, `null` → `nil`.

	- `null` inside an array leaves a hole (`[1,null,3]` gives a table whose
	  `#` is 1 and which encodes back as `{"1":1,"3":3}`); `null` as an
	  object value means the key is absent.
	- `[]` and `{}` both give an empty table, which encodes back as `{}`.
	- Object keys stay strings: `{"1":"a"}` is `t["1"]`, not `t[1]`.
	- Every number is a Luau number (a double): integers above 2^53 lose
	  precision (`9007199254740993` → `9007199254740992`).
	- A duplicate key keeps the last value.

	Errors: `invalid JSON: <reason> at line <l> column <c>`, for example
	`invalid JSON: EOF while parsing a value at line 1 column 0` (empty text),
	`invalid JSON: trailing comma at line 1 column 6`,
	`invalid JSON: recursion limit exceeded at line 1 column 128` (more than
	127 nested arrays/objects) and `invalid JSON: number out of range …`
	(`1e400`). A non-string argument other than a number is
	`bad argument #1: error converting Lua <type> to String …`.

	```lua
	local v = json.decode('{"a":1,"b":[true,null]}')
	-- v.a == 1, v.b[1] == true, v.b[2] == nil
	```
]=]
function json.decode(text: string): any
	return nil :: any
end

return json
