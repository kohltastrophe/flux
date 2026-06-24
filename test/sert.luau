--!strict
--[[
	sert · assert that a condition is true
	======================================

	A single-file assertion library and test runner for Luau. Runs anywhere:
	the vanilla Luau CLI, Roblox Studio, or the Luau Execution API.

	local sert = require(path.to.sert)

	sert.test("math works", function()
		sert(1 + 1 == 2, "addition")
		sert.eq({ a = 1 }, { a = 1 }, "deep equality")
		sert.near(0.1 + 0.2, 0.3)
		sert.fails(function()
			error("boom")
		end, "boom")
	end)

	return sert.run()

	Tests run sequentially, in registration order. There is no async, no
	instance walking, and no environment injection. Specs are plain Luau
	files that require their target directly.
]]

local IS_ROBLOX = game ~= nil

-- vanilla Luau has no warn
local WARN: (...any) -> () = if warn == nil then print else warn

type TestFn = () -> ()
type Mode = "test" | "rtest" | "skip" | "focus"
type Test = { name: string, fn: TestFn, mode: Mode }

export type RunOptions = {
	filter: string?, -- only run tests whose name contains this substring (plain match)
	silent: boolean?, -- suppress output; failures still error
}

export type Results = {
	passed: number,
	failed: number,
	skipped: number,
	total: number,
	clock: number, -- seconds spent running
	failures: { string }, -- "name: error" per failed test
}

local tests: { Test } = {}
local beforeHooks: { TestFn } = {}
local afterHooks: { TestFn } = {}
local focusing = false

-- compact value formatting for failure messages: strings quoted, tables
-- shallow-printed (8 entries, 3 levels), everything else tostring'd
local function repr(value: any, depth: number): string
	local valueType = type(value)
	if valueType == "string" then
		return string.format("%q", value)
	elseif valueType ~= "table" then
		return tostring(value)
	elseif depth > 3 then
		return "{…}"
	end

	local parts = {}
	local count = 0
	for key, item in value :: { [any]: any } do
		count += 1
		if count > 8 then
			table.insert(parts, "…")
			break
		end
		local prefix = if key == count
			then "" -- array part: hide ordinal keys
			elseif type(key) == "string" then `{key} = `
			else `[{repr(key, depth + 1)}] = `
		table.insert(parts, prefix .. repr(item, depth + 1))
	end
	return if count == 0 then "{}" else "{ " .. table.concat(parts, ", ") .. " }"
end

local function deepEquals(a: any, b: any, seen: { [any]: any }): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	if seen[a] == b then
		return true -- this pair is already being compared (cycle)
	end
	seen[a] = b
	for key, value in a :: { [any]: any } do
		if not deepEquals(value, b[key], seen) then
			return false
		end
	end
	for key in b :: { [any]: any } do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local sert = {}

sert.roblox = IS_ROBLOX

-- Assertions ----------------------------------------------------------------

-- sert(condition, why?): the module itself is callable; see the bottom

--- Assert deep equality (tables compared by structure, cycle-safe; everything
--- else by ==). Returns value on success.
function sert.eq(value: any, expected: any, why: string?): any
	if not deepEquals(value, expected, {}) then
		error(`{why or "values differ"}: expected {repr(expected, 1)}, got {repr(value, 1)}`, 2)
	end
	return value
end

--- Assert two numbers are within tolerance (default 1e-6) of each other.
--- Returns value on success.
function sert.near(value: number, expected: number, tolerance: number?, why: string?): number
	local eps = tolerance or 1e-6
	if math.abs(value - expected) > eps then
		error(`{why or "values differ"}: expected {expected} ± {eps}, got {value}`, 2)
	end
	return value
end

--- Boolean tolerance check (default 1e-6) for composing into expect() messages;
--- sert.near is the erroring counterpart.
function sert.approx(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

--- Assert fn raises. fragment, when given, must appear in the error message
--- (plain substring, not a pattern). Returns the error message so callers can
--- make further checks.
function sert.fails(fn: () -> any, fragment: string?, why: string?): string
	local ok, err = pcall(fn)
	if ok then
		error(why or "expected the call to error, but it succeeded", 2)
	end
	local message = tostring(err)
	if fragment ~= nil and string.find(message, fragment, 1, true) == nil then
		error(`{why or "wrong error"}: expected error containing "{fragment}", got: {message}`, 2)
	end
	return message
end

-- Registration ---------------------------------------------------------------

local function register(name: string, fn: TestFn, mode: Mode)
	table.insert(tests, { name = name, fn = fn, mode = mode })
end

--- Register a test. Tests run sequentially, in registration order.
function sert.test(name: string, fn: TestFn)
	register(name, fn, "test")
end

--- Register a Roblox-only test (Instances, Roblox datatypes, the real task
--- scheduler). Counted as skipped when running under the vanilla Luau CLI.
function sert.rtest(name: string, fn: TestFn)
	register(name, fn, "rtest")
end

--- Register a test that is reported 🟡 and never run.
function sert.skip(name: string, fn: TestFn)
	register(name, fn, "skip")
end

--- Register a focused test. When any test is focused, ONLY focused tests run;
--- the header shouts FOCUS so this can't sneak into CI unnoticed.
function sert.focus(name: string, fn: TestFn)
	focusing = true
	register(name, fn, "focus")
end

--- Run fn before each test. Hooks run only for tests that actually execute.
function sert.beforeEach(fn: TestFn)
	table.insert(beforeHooks, fn)
end

--- Run fn after each test, even one that failed. This is the place for state
--- resets, so a failing test can't leak configuration into the tests after it.
function sert.afterEach(fn: TestFn)
	table.insert(afterHooks, fn)
end

-- Runner ----------------------------------------------------------------------

local function runTest(test: Test): string?
	local failure: string? = nil
	for _, hook in beforeHooks do
		local ok, err = pcall(hook :: () -> any)
		if not ok then
			failure = `beforeEach: {tostring(err)}`
			break
		end
	end
	if failure == nil then
		local ok, err = pcall(test.fn :: () -> any)
		if not ok then
			failure = tostring(err)
		end
	end
	for _, hook in afterHooks do
		local ok, err = pcall(hook :: () -> any)
		if not ok and failure == nil then
			failure = `afterEach: {tostring(err)}`
		end
	end
	return failure
end

--- Run every registered test and print a report. Errors (after the report)
--- if any test failed, so CI and the Luau Execution API see a failed run.
--- Returns Results on success.
function sert.run(options: RunOptions?): Results
	local opts: RunOptions = options or {}
	local out: (...any) -> () = if opts.silent then function() end else print
	local shout: (...any) -> () = if opts.silent then function() end else WARN

	if #tests == 0 then
		error("sert.run: no tests registered", 0)
	end

	local results: Results = { passed = 0, failed = 0, skipped = 0, total = #tests, clock = 0, failures = {} }

	local runtime = if IS_ROBLOX then "Roblox" else "Luau CLI"
	local focus = if focusing then " · FOCUS" else ""
	local filter = if opts.filter ~= nil then ` · filter "{opts.filter}"` else ""
	out(`sert · {#tests} tests · {runtime}{focus}{filter}`)

	local startClock = os.clock()
	for _, test in tests do
		local mode: string = test.mode
		local unfocused = focusing and mode ~= "focus"
		local headless = mode == "rtest" and not IS_ROBLOX
		local filtered = opts.filter ~= nil and string.find(test.name, opts.filter, 1, true) == nil
		if unfocused or headless or filtered then
			results.skipped += 1
			continue
		end
		if mode == "skip" then
			results.skipped += 1
			out(`🟡 {test.name}`)
			continue
		end

		local testClock = os.clock()
		local failure = runTest(test)
		local ms = math.round((os.clock() - testClock) * 1000)
		if failure == nil then
			results.passed += 1
			out(`✅ {test.name} · {ms} ms`)
		else
			results.failed += 1
			table.insert(results.failures, `{test.name}: {failure}`)
			shout(`❌ {test.name} · {ms} ms\n   ⚠️ {failure}`)
		end
	end
	results.clock = os.clock() - startClock

	out(
		`\n{results.passed} passed · {results.failed} failed · {results.skipped} skipped`
			.. ` · {math.round(results.clock * 1000)} ms`
	)

	if results.failed > 0 then
		error(`{results.failed} of {results.total} tests failed`, 0)
	end

	return results
end

--- sert(condition, why?) errors with why (default "expected condition to be
--- true") unless condition is truthy. Returns condition, so it can wrap
--- expressions inline.
return setmetatable(sert, {
	__call = function(_, condition: any, why: string?): any
		if not condition then
			error(why or "expected condition to be true", 2)
		end
		return condition
	end,
})
