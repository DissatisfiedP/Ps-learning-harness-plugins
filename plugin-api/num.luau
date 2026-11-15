--[=[
	`require("@harness/num")`, api 1. Reference: docs/host-api.md
	("@harness/num") in this repository. Types only: the harness supplies the
	real module at runtime.

	Numbers: every `Number` below accepts a plain number (real part, imaginary
	part 0) or a `Complex` (a table with a numeric `re`; `im` defaults to 0,
	other fields are ignored). Any other value is not a number and makes the
	call an error: a table without a numeric `re` (`{}`, `{ im = 1 }`, a
	vector, a matrix), a string, `nil`.

	Results: functions that return a `Number` return a plain number when
	|imaginary part| < 1e-12 (so `num.c(3, 0)` is just 3, and i·i is -1),
	and a new `Complex` table otherwise. A result is therefore
	`number | Complex`: read it with `num.real`/`num.imag`/`num.abs`, never
	with `.re` directly. The same rule applies to every element of a
	returned vector or matrix.

	There is no error for division by zero or overflow: the IEEE result
	comes back. `num.div(x, 0)` is a `Complex` whose `re` and `im` are both
	NaN, for every x.
]=]

export type Complex = { re: number, im: number }
export type Number = number | Complex

--[=[
	A matrix is a non-empty list of rows; each row is a list of `Number`.
	A vector is a flat list of `Number`. At most 400 rows and 400 columns
	(400 elements for a vector) in `mul` and `linsolve`.
]=]
export type Matrix = { { Number } }
export type Vector = { Number }

local num = {}

--[=[
	The number `re + im·i`; `im` defaults to 0. Returns a plain number when
	|im| < 1e-12, else `{ re = re, im = im }`.

	Errors: `bad argument #1: error converting Lua <type> to f64 (expected
	number or string coercible to number)` when `re` is missing or not a
	number.

	```lua
	num.c(3, 4)   --> { re = 3, im = 4 }
	num.c(3)      --> 3
	```
]=]
function num.c(re: number, im: number?): Number
	return nil :: any
end

--[=[
	`a + b`. Error: `add expects numbers`.

	```lua
	num.add(num.c(1, 2), 3)   --> { re = 4, im = 2 }
	```
]=]
function num.add(a: Number, b: Number): Number
	return nil :: any
end

--[=[
	`a - b`. Error: `sub expects numbers`.

	```lua
	num.sub(5, num.c(2, 1))   --> { re = 3, im = -1 }
	```
]=]
function num.sub(a: Number, b: Number): Number
	return nil :: any
end

--[=[
	Three forms, chosen by the first argument:
	- number × number → `Number` (real or complex);
	- matrix × vector → vector (one element per matrix row);
	- matrix × matrix → matrix (rows of `a` × columns of `b`).

	There is no number × matrix, matrix × number, vector × vector or
	vector × number: scale and dot yourself.

	Errors (each prefixed `mul: `):
	- `expects two numbers, a matrix and a vector, or two matrices` (first
	  argument is not a matrix and the two are not both numbers);
	- `the matrix's rows have different lengths` (first argument ragged);
	- `a matrix with <k> columns needs a vector of <k> numbers, got <n>`;
	- `a matrix multiplies a vector or a matrix` (second argument is
	  neither);
	- `matrix shapes don't match` (rows of `b` ≠ columns of `a`, or `b`
	  ragged);
	- `matrices and vectors are limited to 400 rows and columns`.

	```lua
	num.mul(num.c(0, 1), num.c(0, 1))             --> -1
	num.mul({ { 1, 2 }, { 3, 4 } }, { 5, 6 })     --> { 17, 39 }
	```
]=]
num.mul = (nil :: any) :: ((a: Matrix, b: Vector) -> Vector)
	& ((a: Matrix, b: Matrix) -> Matrix)
	& ((a: Number, b: Number) -> Number)

--[=[
	`a / b`. Division by zero is not an error: the result is a `Complex`
	with NaN parts. Error: `div expects numbers`.

	```lua
	num.div(1, num.c(0, 1))   --> { re = 0, im = -1 }
	```
]=]
function num.div(a: Number, b: Number): Number
	return nil :: any
end

--[=[
	Magnitude, always a plain number. Error: `abs expects a number`.

	```lua
	num.abs(num.c(3, 4))   --> 5
	```
]=]
function num.abs(a: Number): number
	return nil :: any
end

--[=[
	Argument in degrees, from -180 to 180; 0 for 0. Error: `phaseDeg expects
	a number`.

	```lua
	num.phaseDeg(num.c(0, 1))   --> 90
	```
]=]
function num.phaseDeg(a: Number): number
	return nil :: any
end

--[=[
	Complex conjugate; a real number comes back unchanged. Error: `conj
	expects a number`.

	```lua
	num.conj(num.c(1, 2))   --> { re = 1, im = -2 }
	```
]=]
function num.conj(a: Number): Number
	return nil :: any
end

--[=[
	Real part, always a plain number. Error: `real expects a number`.
]=]
function num.real(a: Number): number
	return nil :: any
end

--[=[
	Imaginary part, always a plain number (0 for a real; not rounded, so a
	`Complex` with `im = 1e-13` gives 1e-13). Error: `imag expects a number`.
]=]
function num.imag(a: Number): number
	return nil :: any
end

--[=[
	Solves `a · x = b` for `x` by Gaussian elimination with partial
	pivoting. `a` is an n×n matrix, `b` a vector of n numbers; both may hold
	complex numbers. Returns a new vector of n `Number`s; the arguments are
	not changed.

	Errors:
	- `linsolve expects a matrix` (`a` is not a non-empty list of rows of
	  numbers);
	- `linsolve expects a vector` (`b` is not a flat list of numbers);
	- `linsolve shapes don't match` (`#b` ≠ number of rows);
	- `the matrix is singular (no unique solution)`: a pivot below 1e-14 in
	  magnitude, and also a non-square or ragged `a`;
	- `linsolve: matrices and vectors are limited to 400 rows and columns`.

	```lua
	num.linsolve({ { 2, 1 }, { 1, 3 } }, { 3, 5 })   --> { 0.8, 1.4 }
	```
]=]
function num.linsolve(a: Matrix, b: Vector): Vector
	return nil :: any
end

return num
