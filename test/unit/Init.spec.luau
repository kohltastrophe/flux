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
local new = Flux

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

test("new · rejects a non-string className", function()
	sert.fails(function()
		Flux.new(123 :: any)
	end, "String expected")
end)

test("clock · manual delay heap ordering, FIFO ties, and step", function()
	local Clock = Flux.Clock
	Clock.manual(true)
	local t0 = Clock.now()
	local w0 = Clock.wall()
	expect(Clock.isManual() == true, "manual clock active")

	local order = {}
	Clock.delay(0.3, function(tag)
		table.insert(order, tag)
	end, "c")
	Clock.delay(0.1, function(tag)
		table.insert(order, tag)
	end, "a1")
	Clock.delay(0.1, function(tag)
		table.insert(order, tag)
	end, "a2")
	Clock.delay(0.2, function(tag)
		table.insert(order, tag)
	end, "b")

	Clock.step(0.15, 0.05)
	expect(table.concat(order, ",") == "a1,a2", "0.1s timers ran in FIFO tie-break order")

	Clock.step(0.2, 0.05)
	expect(table.concat(order, ",") == "a1,a2,b,c", "remaining timers ran in deadline order")
	expect(sert.approx(Clock.now() - t0, 0.35), "Clock.now advanced by 0.35s")
	expect(sert.approx(Clock.wall() - w0, 0.35), "Clock.wall advanced in lockstep")
	Clock.manual(false)
end)

test("clock · wait inside a coroutine, defer, drain, and cancel", function()
	local Clock = Flux.Clock
	Clock.manual(true)

	local waited: number? = nil
	local co = coroutine.create(function()
		waited = Clock.wait(0.25)
	end)
	assert(coroutine.resume(co))
	expect(waited == nil, "coroutine parked on Clock.wait")

	Clock.step(0.25, 0.25)
	expect(waited ~= nil and sert.approx(waited :: number, 0.25), "Clock.wait resumed with elapsed time")

	-- Cancel a delayed timer, a deferred function, and a waiting coroutine
	local ranDelay, ranDefer, ranWait = false, false, false
	local tDelay = Clock.delay(0.1, function()
		ranDelay = true
	end)
	local tDefer = Clock.defer(function()
		ranDefer = true
	end)
	local tWait = coroutine.create(function()
		Clock.wait(0.1)
		ranWait = true
	end)
	assert(coroutine.resume(tWait))

	Clock.cancel(tDelay)
	Clock.cancel(tDefer)
	Clock.cancel(tWait)
	Clock.step(0.2, 0.1)
	expect(not ranDelay and not ranDefer and not ranWait, "cancelled delay, defer, and wait never ran")

	-- Nested defer drains completely
	local log = {}
	Clock.defer(function(first)
		table.insert(log, first)
		Clock.defer(function(second)
			table.insert(log, second)
		end, "inner")
	end, "outer")
	Clock.drain()
	expect(table.concat(log, ",") == "outer,inner", "Clock.drain runs transitive deferred calls")
	Clock.manual(false)
end)

test("clock · connect phases, disconnect, frame step integration, and reset", function()
	local Clock = Flux.Clock
	Clock.manual(true)

	sert.fails(function()
		Clock.connect("InvalidPhase" :: any, function() end)
	end, "unknown phase")

	local phases = {}
	local sig = Flux.signal(0)
	local effSeen = -1
	local eff = Flux.effect(function()
		effSeen = sig()
	end)
	local spr = Flux.spring(0, 10, 1)
	spr:set(100)

	local offRender = Clock.connect("PreRender", function(_dt)
		table.insert(phases, "render")
	end)
	local offHeart = Clock.connect("Heartbeat", function(_dt)
		table.insert(phases, `hb:{effSeen}`)
	end)

	sig:set(7)
	Clock.step(0.1, 0.1)
	expect(phases[1] == "render" and phases[2] == "hb:7", "PreRender -> Flux flush -> Heartbeat order")
	expect(spr:get() > 0, "Clock.step advanced active springs via frameHook")

	offRender()
	offHeart()
	table.clear(phases)
	Clock.step(0.1, 0.1)
	expect(#phases == 0, "disconnected phase listeners no longer fire")

	-- reset clears pending work without rewinding now()
	local never = false
	Clock.delay(0.1, function()
		never = true
	end)
	local beforeReset = Clock.now()
	Clock.reset()
	Clock.step(0.2, 0.1)
	expect(not never and Clock.now() >= beforeReset, "reset dropped pending timers and kept monotonic time")

	eff:Destroy()
	spr:Destroy()
	Clock.manual(false)
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

test("on · defer=true skips initial run and passes initial input as prevInput on first change", function()
	local src = new(10)
	local calls = 0
	local seenCur, seenPrev
	local c = new(Flux.on(src, function(cur, prev)
		calls += 1
		seenCur = cur
		seenPrev = prev
		return cur
	end, true))
	expect(c:get() == nil and calls == 0, "defer=true returns nil on initial evaluation without running fn")
	src:set(25)
	expect(c:get() == 25 and calls == 1, "first change runs fn")
	expect(seenCur == 25 and seenPrev == 10, "first change receives initial value 10 as prevInput")
	c:Destroy()
end)

test("compat · headless stubs and arithmetic metamethods behave consistently", function()
	local Compat = if IS_ROBLOX
		then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux"):WaitForChild("Compat")) :: any
		else require("../../src/Compat") :: any
	local U = Compat.UDim
	local U2 = Compat.UDim2
	local V2 = Compat.Vector2
	local V3 = Compat.Vector3
	local C3 = Compat.Color3

	local uSum = U.new(0.25, 10) + U.new(0.5, 5)
	local uDiff = U.new(0.75, 20) - U.new(0.25, 8)
	expect(uSum == U.new(0.75, 15), "UDim __add and __eq")
	expect(uDiff == U.new(0.5, 12), "UDim __sub")

	local u2 = U2.fromScale(0.5, 0.25)
	expect(u2 == U2.new(0.5, 0, 0.25, 0) and U2.fromOffset(10, 20) == U2.new(0, 10, 0, 20), "UDim2 constructors")

	local v2 = (V2.new(3, 4) + V2.new(1, 2) - V2.new(1, 2)) * 2 / 2
	expect(v2 == V2.new(3, 4) and -v2 == V2.new(-3, -4), "Vector2 arithmetic")
	expect(V2.zero:Lerp(V2.new(1, 1), 0.5) == V2.new(0.5, 0.5), "Vector2 Lerp")

	local v3 = (V3.new(1, 2, 2) + V3.new(1, 1, 1) - V3.new(1, 1, 1)) * 2 / 2
	expect(v3 == V3.new(1, 2, 2) and -v3 == V3.new(-1, -2, -2), "Vector3 arithmetic")
	expect(V3.zero:Lerp(V3.new(2, 4, 6), 0.5) == V3.new(1, 2, 3), "Vector3 Lerp")

	expect(C3.fromHex("#ff8000") == C3.fromRGB(255, 128, 0), "Color3.fromHex 6-digit")
	expect(C3.fromHex("f0f") == C3.fromRGB(255, 0, 255), "Color3.fromHex 3-digit")
	expect(C3.fromRGB(255, 128, 0):ToHex() == "ff8000", "Color3:ToHex")
	expect(C3.new(0, 0, 0):Lerp(C3.new(1, 0.5, 0.25), 0.5) == C3.new(0.5, 0.25, 0.125), "Color3:Lerp")
end)

return {}
