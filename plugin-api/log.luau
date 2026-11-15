--[=[
	`require("@harness/log")`, api 1. Reference: docs/host-api.md
	("@harness/log") in this repository. Types only: the harness supplies the
	real module at runtime.
]=]

local log = {}

--[=[
	Converts `value` to JSON (the rules of `json.encode`) and emits it as one
	debug-level event on the host's `tracing` log, target `plugin`. Returns
	nothing. The line is never shown to the model or the learner and is not a
	result channel. `plugin test` prints it on standard error
	(`<time> DEBUG plugin: <json>`); the app prints it only when started with
	`PS_LEARN_LOG=debug` (see docs/host-api.md).

	Errors: the two `json.encode` errors (a table that refers to itself,
	nesting deeper than 64 tables).

	```lua
	log.debug({ step = "solve", n = 3 })
	```
]=]
function log.debug(value: any): () end

return log
