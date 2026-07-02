--!nonstrict
--[[
	Flux unified test entry: one suite, two runtimes.

	* Headless: `luau test/spec.client.luau` (vanilla Luau 0.640+). rtest() tests are
	  skipped; the rest runs in ~20ms. The fast feedback loop.
	* Roblox: run as a Luau Execution API task by CI against the built place, or
	  via the Studio MCP. Runs everything: Instances, Motion datatypes, real
	  scheduler timing. The trailing `return` also lets it double as a ModuleScript.

	The tests themselves live one-file-per-`src`-module under `test/unit/`; this
	file just pulls in that aggregator (`test/unit/init.luau`), which owns the
	shared teardown and requires each suite, then runs the registered tests.

	Conventions (see test/unit/*.spec.luau):
	* test() registers a universal test; rtest() a Roblox-only one (Instances,
	  Roblox datatypes, real task scheduling).
	* Effects and bindings are DEFERRED: call flush() after a write to observe it.
	* EXPECTED NOISE: tests marked "(expected warn)" exercise error paths; their
	  warnings and tracebacks are deliberate. Only the final summary line and exit
	  code matter. (warn can't be intercepted; modules bind it at require time.)
]]

local IS_ROBLOX = game ~= nil

local sert
if IS_ROBLOX then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	sert = require(ReplicatedStorage:WaitForChild("sert")) :: any
	-- Requiring the aggregator registers every suite (and the shared hooks).
	require(ReplicatedStorage:WaitForChild("Flux.unit"))
else
	sert = require("./sert") :: any
	require("./unit")
end

-- Headless-only: `luau test/spec.client.luau -a <substring>` runs just matching tests
-- (plain substring), muting expected-warn noise. CLI passes post-`-a` args as varargs.
local filter = if IS_ROBLOX then nil else ... :: string?

-- sert.run prints a per-test report, raises on any failure (so the Luau CLI and
-- the Execution API both see a non-zero / failed task), and returns its Results.
return sert.run({ filter = filter })
