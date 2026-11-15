--[=[
	`require("@harness/test")`, api 1. Reference: docs/testing.md and
	docs/host-api.md ("@harness/test") in this repository. Types only: the
	harness supplies the real module.

	Only inside `plugin test` (tests/*.luau and what they require). In a
	running plugin, requiring it is the error
	"@harness/test is only available under `plugin test`".
]=]

local test = {}

--[=[
	Compares `text` with the file `tests/golden/<name>` byte for byte and
	returns nothing when they are equal.

	With the environment variable `PLUGIN_UPDATE_GOLDEN=1` (exactly `1`) it
	writes `text` to that file instead, creating folders as needed, and
	never fails on content.

	Errors:
	- ``golden: `<name>` must be a relative path inside tests/golden`` when
	  `name` is empty, contains `..` anywhere (so `a..txt` too), starts with
	  `/` or contains a backslash;
	- `golden file tests/golden/<name> missing (run with PLUGIN_UPDATE_GOLDEN=1 to write it)`;
	- on a mismatch, the first differing line (1-based):
	  `golden tests/golden/<name> differs at line <n>:`, then `  got:  <line>`
	  and `  want: <line>`. `<end of text>` / `<end of file>` stand for a
	  side that ran out; texts that differ only in line endings or in a final
	  newline report both at the line after the last one.

	```lua
	local golden = require("@harness/test").golden
	golden("card.svg", main.render(data))
	```
]=]
function test.golden(name: string, text: string): () end

return test
