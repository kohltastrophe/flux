--!nonstrict
--[[
	The Flux test entry, for both runtimes. Headless: `python3 tools/sert.py run [-a filter --flags]` runs every `test`
	and skips `rtest` (Instances, datatypes, real scheduling). Roblox: CI runs it as a Luau Execution task (it doubles
	as a ModuleScript). Effects are deferred, so a test flushes after a write; a test that expects warnings captures
	them with `env.warnings`.
]]

local IS_ROBLOX = game ~= nil

local sert
local options
if IS_ROBLOX then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	sert = require(ReplicatedStorage:WaitForChild("sert")) :: any
	require(ReplicatedStorage:WaitForChild("Flux.unit"))
	options = {}
else
	sert = require("@sert") :: any
	options = sert.parseCliArgs(...)
	require("./unit")
end

-- sert.run prints a per-test report, raises on any failure (so the Luau CLI and
-- the Execution API both see a non-zero / failed task), and returns its Results.
assert(type(sert.run) == "function", "sert.run must be a function")
return sert.run(options)
