--!nonstrict
local IS_ROBLOX = game ~= nil

local Flux
local sert
if IS_ROBLOX then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	Flux = require(ReplicatedStorage:WaitForChild("Flux")) :: any
	sert = require(ReplicatedStorage:WaitForChild("sert")) :: any
else
	Flux = require("../../src") :: any
	sert = require("../sert") :: any
end

local test = sert.test
local rtest = sert.rtest
local expect = sert
local new = Flux.Graph.new

test("on · getter-function dep is called and tracked", function()
	local a = new(5)
	local calls = 0
	local c = new(Flux.on(function()
		return a:get() * 2
	end, function(v: number)
		calls += 1
		return v
	end))
	expect(c:get() == 10, "getter dep is invoked, not passed as a function")
	a:set(6)
	expect(c:get() == 12 and calls == 2, "getter's inner read is tracked; re-triggers")
end)

test("on · plain non-node array passed as single dep is array-shaped", function()
	local got: any
	local c = new(Flux.on({ 1, 2, 3 }, function(v: { number })
		got = v
		return #v
	end))
	expect(c:get() == 3, "treated as array of three static deps")
	expect(got[1] == 1 and got[2] == 2 and got[3] == 3, "each element read via readDep")
end)

test("on · single Node dep threads prevInput across runs", function()
	local a = new(1)
	local seen = {}
	local c = new(Flux.on(a, function(v, prevV)
		seen[#seen + 1] = { v, prevV }
		return v * 10
	end))
	expect(c:get() == 10, "first run uses current dep")
	expect(seen[1][1] == 1 and seen[1][2] == nil, "first prevInput is nil")
	a:set(2)
	expect(c:get() == 20, "re-runs on dep change")
	expect(seen[2][1] == 2 and seen[2][2] == 1, "prevInput is the prior dep value")
end)

test("on · defer skips the first run", function()
	local a = new(1)
	local runs = 0
	local c = new(Flux.on(a, function(v)
		runs += 1
		return v * 100
	end, true))
	expect(c:get() == nil and runs == 0, "deferred: first eval does not call fn")
	a:set(3)
	expect(c:get() == 300 and runs == 1, "fires on the first dependency change")
end)

test("on · array dep only re-runs when a listed dep changes", function()
	local a = new(1)
	local b = new(2)
	local untracked = new(99)
	local runs = 0
	local c = new(Flux.on({ a, b }, function(inp)
		runs += 1
		return inp[1] + inp[2]
	end))
	expect(c:get() == 3 and runs == 1, "sum of listed deps")
	untracked:set(100)
	expect(c:get() == 3 and runs == 1, "unlisted state does not re-trigger")
	b:set(5)
	expect(c:get() == 6 and runs == 2, "listed dep change re-triggers")
end)

rtest("heartbeat · effects auto-flush via the RunService hookup", function()
	local a = Flux(1)
	local seen = {}
	local e = Flux.effect(function()
		table.insert(seen, a:get())
	end)
	task.wait(0.1)
	expect(#seen >= 1 and seen[1] == 1, "creation run flushed by Heartbeat")
	a:set(2)
	task.wait(0.1)
	expect(seen[#seen] == 2, "set flushed by Heartbeat")
	e:Destroy()
end)

return {}
