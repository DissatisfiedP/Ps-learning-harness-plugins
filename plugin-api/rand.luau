--[=[
	`require("@harness/rand")`, api 1. Reference: docs/host-api.md
	("@harness/rand") in this repository. Types only: the harness supplies
	the real module at runtime.

	A seeded xorshift64 generator. The same seed gives the same sequence on
	every device and in every replay; nothing here reads a clock.
]=]

--[=[
	One generator. Its three functions are closures over the same state, so
	call them with `.`, not `:` (`rng.int(1, 6)`). A method call passes the
	table as the first argument: `rng:int(1, 6)` and `rng:range(1, 6)` fail
	with `bad argument #1: error converting Lua table to i64 …` / `… f64 …`.
	Every call advances the state by one step, whichever function it is.

	- `next()`: a number in [0, 1) with 53 random bits.
	- `range(lo, hi)`: `lo + (hi - lo) * next()`, so [lo, hi) for lo < hi;
	  with lo > hi the result lies in (hi, lo]; lo == hi returns lo.
	- `int(lo, hi)`: a whole number in [lo, hi], both ends included, by
	  modulo reduction (a very small bias for huge spans). When hi < lo it
	  returns `lo`. Both arguments must be whole numbers: a fraction is
	  `bad argument #1: error converting Lua number to i64 (out of range)`.
	  Any two whole numbers in the 64-bit integer range work (app builds from
	  before 2026-11-15 failed when `hi - lo` reached 2^63).
]=]
export type Rng = {
	-- [0, 1)
	next: () -> number,
	range: (lo: number, hi: number) -> number,
	-- inclusive
	int: (lo: number, hi: number) -> number,
}

local rand = {}

--[=[
	Returns a new generator, independent of every other one.

	`seed` must be a whole number, 0 or more and below 2^64; `0` is replaced
	by `1`, so seeds 0 and 1 give the same sequence. Anything else is an
	error: `bad argument #1: error converting Lua integer to u64 (out of
	range)` (negative), `… Lua number to u64 (out of range)` (fraction, NaN,
	infinity, 2^64 or more), `… Lua nil to u64 (expected number or string
	coercible to number)`.

	The first `next()`/`range()` value of a small seed is tiny and related
	between neighbouring seeds (seed 1 starts 5.87e-11, seed 2 starts
	1.17e-10). Discard a few values first when that matters.

	```lua
	local rng = rand.seeded(42)
	rng.int(1, 6)   --> 4, then 1, 4, 1, 5, 6, …
	```
]=]
function rand.seeded(seed: number): Rng
	return nil :: any
end

return rand
