--!nonstrict
-- Flux.Clock on a manual clock (always, headless; switched on per test in Studio), and the Compat shims built on it.
local env = if game ~= nil
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Flux, Compat, sert, IS_ROBLOX = env.Flux, env.Compat, env.sert, env.IS_ROBLOX

local test = sert.test
local rtest = sert.rtest
local expect = sert
local eq = sert.eq
local near = sert.near
local fails = sert.fails

local Clock = Flux.Clock

-- Runs `fn` on a clean manual clock, then drops what it left pending (and, in Studio, turns manual back off).
local function manual(fn: () -> ())
	local wasManual = Clock.isManual()
	Clock.manual(true)
	Clock.reset()
	local ok, err = pcall(fn)
	Clock.reset()
	Compat.setWarnHook(nil)
	if not wasManual then
		Clock.manual(false)
	end
	if not ok then
		error(err, 0)
	end
end

test("clock · delays fire in deadline order, ties in the order they were scheduled", function()
	manual(function()
		local order = {}
		Clock.delay(0.2, function(name)
			table.insert(order, name)
		end, "late")
		Clock.delay(0.1, function(name)
			table.insert(order, name)
		end, "first")
		Clock.delay(0.1, function(name)
			table.insert(order, name)
		end, "second")
		Clock.step(0.05)
		eq(order, {}, "nothing is due yet")
		Clock.step(0.25)
		eq(order, { "first", "second", "late" }, "earliest deadline first, then scheduling order")
	end)
end)

test("clock · a zero delay scheduled by a firing timer waits for the next frame", function()
	manual(function()
		local order = {}
		Clock.delay(0, function()
			table.insert(order, "outer")
			Clock.delay(0, function()
				table.insert(order, "inner")
			end)
		end)
		Clock.step(0)
		eq(order, { "outer" }, "the inner timer is not run in the same frame")
		Clock.step(0)
		eq(order, { "outer", "inner" }, "it runs on the next frame")
	end)
end)

test("clock · step splits into frames of at most `frame` seconds and lands exactly", function()
	manual(function()
		local start = Clock.now()
		local dts = {}
		Clock.connect("Heartbeat", function(dt)
			table.insert(dts, dt)
		end)
		Clock.step(0.05, 0.02)
		eq(#dts, 3, "two full frames and a partial one")
		near(dts[1], 0.02, 1e-12)
		near(dts[2], 0.02, 1e-12)
		near(dts[3], 0.01, 1e-12)
		eq(Clock.now(), start + 0.05, "now lands on start + seconds")
		table.clear(dts)
		Clock.step(1)
		eq(#dts, 60, "the default frame is 1/60 s")
		eq(Clock.now(), start + 1.05)

		local fired = false
		Clock.delay(0.3, function()
			fired = true
		end)
		Clock.step(0.1)
		Clock.step(0.2)
		expect(fired, "0.1 + 0.2 reaches a 0.3 s deadline despite float rounding")
	end)
end)

test("clock · wait yields until a step passes the deadline and returns the time waited", function()
	manual(function()
		local waited
		local thread = coroutine.create(function()
			waited = Clock.wait(0.5)
		end)
		coroutine.resume(thread)
		Clock.step(0.4)
		eq(waited, nil, "still waiting at 0.4 s")
		Clock.step(0.1)
		near(waited, 0.5, 1e-9, "resumed with the time waited")

		local frames = 0
		coroutine.resume(coroutine.create(function()
			Clock.wait()
			frames += 1
		end))
		Clock.step(1 / 60)
		eq(frames, 1, "a bare wait resumes on the next frame")
	end)
end)

if not IS_ROBLOX then
	test("clock · wait outside a coroutine errors headless", function()
		-- sert runs every test on a coroutine of its own, so the wait goes through a C call boundary (a gsub
		-- callback), where the running thread cannot yield.
		fails(function()
			string.gsub("x", "x", function()
				Clock.wait(1)
			end)
		end, "yieldable coroutine")
	end)
end

test("clock · cancel stops a delay, a deferred call and a wait", function()
	manual(function()
		local ran = {}
		local delayed = Clock.delay(0.1, function()
			table.insert(ran, "delay")
		end)
		local deferred = Clock.defer(function()
			table.insert(ran, "defer")
		end)
		local waiting = coroutine.create(function()
			Clock.wait(0.1)
			table.insert(ran, "wait")
		end)
		coroutine.resume(waiting)
		Clock.cancel(delayed)
		Clock.cancel(deferred)
		Clock.cancel(waiting)
		Clock.step(0.2)
		eq(ran, {}, "nothing cancelled runs")
	end)
end)

test("clock · defer queues until drain, in order, including work deferred while draining", function()
	manual(function()
		local order = {}
		Clock.defer(function(name)
			table.insert(order, name)
			Clock.defer(function()
				table.insert(order, "nested")
			end)
		end, "a")
		Clock.defer(function()
			table.insert(order, "b")
		end)
		eq(order, {}, "deferred work waits")
		Clock.drain()
		eq(order, { "a", "b", "nested" }, "FIFO, then what was deferred meanwhile")

		local function forever()
			Clock.defer(forever)
		end
		Clock.defer(forever)
		fails(Clock.drain, "did not settle")
		Clock.drain() -- the runaway queue was dropped
	end)
end)

test("clock · a frame runs render subscribers, then Flux's step and flush, then heartbeat", function()
	manual(function()
		local order = {}
		local value = Flux.signal(0)
		local scope = Flux.scope(function()
			Flux.effect(function()
				if value() > 0 then
					table.insert(order, "flush")
				end
			end)
		end)
		Flux.flush()
		Clock.connect("Heartbeat", function()
			table.insert(order, "heartbeat")
		end)
		Clock.connect("PreRender", function()
			table.insert(order, "prerender")
			value:set(value:get() + 1)
		end)
		local disconnect = Clock.connect("RenderStepped", function()
			table.insert(order, "renderstepped")
		end)
		Clock.step(1 / 60)
		eq(order, { "prerender", "renderstepped", "flush", "heartbeat" })
		disconnect()
		table.clear(order)
		Clock.step(1 / 60)
		eq(order, { "prerender", "flush", "heartbeat" }, "a disconnected subscriber stops")
		fails(function()
			Clock.connect("Stepped" :: any, function() end)
		end, "unknown phase")
		scope:Destroy()
	end)
end)

test("clock · reset drops pending work and subscribers but never moves time back", function()
	manual(function()
		local ran = false
		Clock.delay(0.1, function()
			ran = true
		end)
		Clock.defer(function()
			ran = true
		end)
		Clock.connect("Heartbeat", function()
			ran = true
		end)
		Clock.step(0.05)
		ran = false
		local before = Clock.now()
		Clock.reset()
		eq(Clock.now(), before, "now is untouched")
		Clock.step(1)
		Clock.drain()
		expect(not ran, "nothing pending survives a reset")
	end)
end)

test("clock · wall time starts at 2026-01-01T00:00:00Z and moves with now", function()
	manual(function()
		eq(Clock.wall() - Clock.now(), 1767225600)
		local wall = Clock.wall()
		Clock.step(2)
		near(Clock.wall() - wall, 2, 1e-6)
	end)
end)

test("compat · UDim offsets truncate toward zero like the engine's int32", function()
	local sum = Compat.UDim.new(0, 1.7) + Compat.UDim.new(0.5, -2.9)
	eq(sum.Scale, 0.5)
	eq(sum.Offset, -1, "1 + -2: each offset truncates when built, and the sum stays whole")
	eq((Compat.UDim.new(0, 3) - Compat.UDim.new(0, 1)).Offset, 2)
	eq(Compat.UDim2.new(0, -4.5, 0, 4.5).X.Offset, -4)
end)

test("compat · headless stubs and arithmetic metamethods behave consistently", function()
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

test("compat · typeof reports engine names for the datatypes", function()
	local typeof = Compat.typeof
	eq(typeof(Compat.Color3.new(1, 0, 0)), "Color3")
	eq(typeof(Compat.UDim.new(1, 0)), "UDim")
	eq(typeof(Compat.UDim2.fromScale(1, 1)), "UDim2")
	eq(typeof(Compat.Vector2.new(1, 2)), "Vector2")
	eq(typeof(Compat.Vector3.new(1, 2, 3)), "Vector3")
	eq(typeof(Compat.TweenInfo.new()), "TweenInfo")
	eq(typeof(Compat.Font.fromEnum(Compat.Enum.Font.Gotham)), "Font")
	eq(typeof(Compat.Enum.EasingStyle.Quad), "EnumItem")
	eq(typeof(Compat.Enum.EasingStyle), "Enum")
	eq(typeof(Compat.Enum), "Enums")
	eq(typeof(Compat.ColorSequence.new(Compat.Color3.new(1, 0, 0))), "ColorSequence")
	eq(typeof(Compat.ColorSequenceKeypoint.new(0, Compat.Color3.new(1, 0, 0))), "ColorSequenceKeypoint")
	eq(typeof(Compat.NumberSequence.new(0, 1)), "NumberSequence")
	eq(typeof(Compat.NumberSequenceKeypoint.new(0, 1)), "NumberSequenceKeypoint")
	eq(typeof(1), "number")
	eq(typeof({}), "table")
end)

test("compat · an enum item's EnumType is its enum", function()
	local quad = Compat.Enum.EasingStyle.Quad
	expect(quad.EnumType == Compat.Enum.EasingStyle, "EnumType is the enum itself")
	expect(quad.EnumType ~= Compat.Enum.EasingDirection, "and no other")
	eq(tostring(quad), "Enum.EasingStyle.Quad")
	eq(tostring(quad.EnumType), "EasingStyle")
end)

test("compat · TweenInfo defaults and Vector3:Lerp match the engine", function()
	local info = Compat.TweenInfo.new()
	eq(info.Time, 1)
	expect(info.EasingStyle == Compat.Enum.EasingStyle.Quad, "Quad")
	expect(info.EasingDirection == Compat.Enum.EasingDirection.Out, "Out")
	eq(info.RepeatCount, 0)
	eq(info.Reverses, false)
	eq(info.DelayTime, 0)
	eq(Compat.Enum.EasingStyle.Cubic.Value, 10)
	expect(Compat.TweenInfo.new(1) == info, "value equality")
	local mid = Compat.Vector3.new(0, 0, 0):Lerp(Compat.Vector3.new(2, 4, 6), 0.5)
	expect(mid == Compat.Vector3.new(1, 2, 3), "Lerp halfway")
end)

test("clock · a tween built from Compat.TweenInfo moves only with step", function()
	manual(function()
		local goal = Flux.signal(0)
		local info = Compat.TweenInfo.new(1, Compat.Enum.EasingStyle.Linear, Compat.Enum.EasingDirection.In)
		local tween = Flux.tween(goal, info)
		Flux.flush()
		goal:set(10)
		Flux.flush()
		Flux.Motion.step() -- a real frame: no manual time has passed
		near(tween:get(), 0, 1e-9, "a frame without a step adds nothing")
		Clock.step(0.5)
		near(tween:get(), 5, 1e-6, "halfway after half the time")
		Clock.step(0.5)
		near(tween:get(), 10, 1e-6, "done after the full time")
	end)
end)

test("compat · setWarnHook captures warnings until cleared", function()
	local seen = {}
	Compat.setWarnHook(function(message)
		table.insert(seen, message)
	end)
	local ok, err = pcall(Compat.warn, "[Flux] captured", 1, true)
	Compat.setWarnHook(nil)
	assert(ok, err)
	eq(seen, { "[Flux] captured 1 true" }, "the hook gets the joined message, and the warning is not printed")
end)

if not IS_ROBLOX then
	test("compat · headless task: spawn resumes now, defer and delay wait for the clock", function()
		manual(function()
			local order = {}
			Compat.task.defer(function()
				table.insert(order, "defer")
			end)
			Compat.task.delay(0.1, function()
				table.insert(order, "delay")
			end)
			Compat.task.spawn(function()
				table.insert(order, "spawn")
			end)
			eq(order, { "spawn" })
			Clock.drain()
			eq(order, { "spawn", "defer" })
			Clock.step(0.1)
			eq(order, { "spawn", "defer", "delay" })
		end)
	end)

	test("compat · an error in a resumed thread is warned, not raised", function()
		manual(function()
			local seen = {}
			Compat.setWarnHook(function(message)
				table.insert(seen, message)
			end)
			Clock.defer(function()
				error("deferred failure")
			end)
			Clock.drain()
			eq(#seen, 1)
			expect(string.find(seen[1], "deferred failure", 1, true) ~= nil, "the warning carries the error")
		end)
	end)
end

-- Studio spike: the manual clock drives frame subscribers, springs and flushes deterministically, and `Clock.defer`
-- work drains inside `step`; the engine's own `task.defer` does not (it waits for a resumption point).
rtest("clock · a manual clock steps subscribers, motion and flush; engine defers wait for the engine", function()
	manual(function()
		local beats = 0
		Clock.connect("Heartbeat", function()
			beats += 1
		end)
		local goal = Flux.signal(0)
		local spring = Flux.spring(goal, 10, 1)
		Flux.flush()
		goal:set(100)
		Flux.flush()
		local observed = {}
		Clock.defer(function()
			table.insert(observed, "clock defer")
			Clock.defer(function()
				table.insert(observed, "clock chained defer")
			end)
			task.defer(function()
				table.insert(observed, "engine defer")
			end)
		end)
		Clock.step(1)
		local atReturn = table.clone(observed)
		eq(beats, 60, "60 heartbeat frames in a 1 s step")
		near(spring:get(), 100, 0.1, "the spring converged within the step")
		eq(atReturn, { "clock defer", "clock chained defer" }, "Clock.defer chains drain inside step")
		task.wait()
		eq(observed[3], "engine defer", "task.defer from inside step runs at the engine's next resumption point")
		spring:Destroy()
	end)
end)

return {}
