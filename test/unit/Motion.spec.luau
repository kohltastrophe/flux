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
local expectError = sert.fails
local flush = Flux.flush
local Motion = Flux.Motion
local MotionModule = if IS_ROBLOX
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux"):WaitForChild("Motion")) :: any
	else require("../../src/Motion") :: any
local Compat = if IS_ROBLOX then nil else require("../../src/Compat") :: any
local TweenInfo = if IS_ROBLOX then TweenInfo else Compat.TweenInfo
local Enum = if IS_ROBLOX then Enum else Compat.Enum
local UDim = if IS_ROBLOX then UDim else Compat.UDim
local UDim2 = if IS_ROBLOX then UDim2 else Compat.UDim2
local Vector2 = if IS_ROBLOX then Vector2 else Compat.Vector2
local Vector3 = if IS_ROBLOX then Vector3 else Compat.Vector3
local Color3 = if IS_ROBLOX then Color3 else Compat.Color3
local ColorSequence = if IS_ROBLOX then ColorSequence else Compat.ColorSequence
local ColorSequenceKeypoint = if IS_ROBLOX then ColorSequenceKeypoint else Compat.ColorSequenceKeypoint
local NumberSequence = if IS_ROBLOX then NumberSequence else Compat.NumberSequence
local NumberSequenceKeypoint = if IS_ROBLOX then NumberSequenceKeypoint else Compat.NumberSequenceKeypoint

local approx = sert.approx

-- Advance the Motion engine by `dt` seconds of SIMULATED time via Motion.step(dt).
local function advance(dt: number)
	Motion.step(dt)
end

-- Drive a Flux.tween node by `elapsed` seconds of simulated time instantly.
local function tweenAt(node: any, elapsed: number): any
	Motion.step(elapsed)
	return node:get()
end

local function tweenToGoal(start: any, goal: any)
	-- a 0-duration Linear tween clamps alpha to 1 on the first step, so one Motion.step()
	-- lands the value on the goal exactly; the pack/unpack round-trip these tests verify
	local tw = Flux.tween(start, TweenInfo.new(0, Enum.EasingStyle.Linear))
	tw:set(goal)
	flush()
	Motion.step(0)
	return tw:get()
end

test("motion · nil-goal fallback follows and survives retarget (expected warn)", function()
	-- the fallback is a value node + follower effect (not a bare computed): a retarget
	-- is a plain value write the next goal change overrides, never freezing the follower
	local goal = Flux.signal(nil)
	local spr = Flux.spring(goal) -- expected warn: Animating a nil value
	goal:set(5)
	flush()
	expect(spr:get() == 5, "fallback follows the goal")
	spr:set(99) -- retarget on the fallback: plain value write
	expect(spr:get() == 99, "retarget writes")
	goal:set(7)
	flush()
	expect(spr:get() == 7, "STILL follows after retarget")
end)

test("motion · non-animatable types error at the call site", function()
	expectError(function()
		return Flux.spring(true)
	end, "Cannot animate a boolean value")
	expectError(function()
		return Flux.tween("nope", nil)
	end, "Cannot animate a string value")
end)

test("motion · number spring converges (manual step)", function()
	local goal = Flux(0)
	local spr = Flux.spring(goal, 10, 1)
	goal:set(100)
	flush() -- the follower effect retargets the spring
	advance(0.1)
	local mid = spr:get()
	expect(mid > 0, `spring moved toward the goal, got {mid}`)
	advance(0.2) -- a freq-10 critically-damped spring is converged within ~0.2s of sim time
	expect(approx(spr:get(), 100, 0.5), `spring converged, got {spr:get()}`)
end)

test("motion · impulse kicks a resting number spring", function()
	local spr = Flux.spring(0, 10, 1)
	Motion.step()
	expect(approx(spr:get(), 0), "starts at rest at 0")

	spr:impulse(500)
	advance(0.05)
	local mid = spr:get()
	expect(mid > 0, `impulse moved the spring off rest, got {mid}`)

	advance(0.2)
	expect(approx(spr:get(), 0, 0.5), `spring returns to target after impulse, got {spr:get()}`)
end)

test("motion · impulse accumulates (two impulses > one)", function()
	local a = Flux.spring(0, 10, 1)
	local b = Flux.spring(0, 10, 1)
	Motion.step()

	a:impulse(100)
	b:impulse(100)
	b:impulse(100)

	advance(0.02)
	expect(b:get() > a:get(), `accumulated impulse travels further: a={a:get()} b={b:get()}`)
end)

test("motion · setVelocity replaces (not adds)", function()
	local spr = Flux.spring(0, 10, 1)
	Motion.step()
	spr:impulse(1000)
	spr:setVelocity(0)

	advance(0.05)
	expect(approx(spr:get(), 0, 1e-3), `setVelocity(0) cancelled the impulse, got {spr:get()}`)
end)

test("motion · impulse reactivates a converged spring", function()
	local goal = Flux(0)
	local spr = Flux.spring(goal, 10, 1)
	goal:set(50)
	flush()
	advance(0.2)
	expect(approx(spr:get(), 50, 0.5), "converged to 50")

	spr:impulse(-300)
	advance(0.03)
	expect(spr:get() < 50, `impulse re-woke the converged spring, got {spr:get()}`)
end)

test("motion · underdamped number spring overshoots then converges", function()
	local goal = Flux(0)
	local spr = Flux.spring(goal, 12, 0.3) -- damping 0.3 < 1 -> underdamped branch
	goal:set(100)
	flush() -- the follower effect retargets the spring

	local maxSeen = -math.huge
	-- 25 steps of 0.02s sim time (~0.5s, instant via advance): at frequency 12 the
	-- spring overshoots within a couple steps then settles well inside the window
	for _ = 1, 25 do
		advance(0.02)
		local v = spr:get()
		if v > maxSeen then
			maxSeen = v
		end
	end

	-- underdamped MUST overshoot (>100 at some sample); a critical/overdamped solver wouldn't
	expect(maxSeen > 101, `underdamped spring overshot the goal, peak={maxSeen}`)
	expect(approx(spr:get(), 100, 0.5), `underdamped spring converged, got {spr:get()}`)
end)

test("motion · overdamped number spring converges monotonically (no overshoot)", function()
	local goal = Flux(0)
	local spr = Flux.spring(goal, 12, 2) -- damping 2 > 1 -> overdamped branch
	goal:set(100)
	flush()

	local prev = spr:get()
	local maxSeen = prev
	local sawProgress = false
	-- 30 steps of 0.02s sim time (~0.6s, instant via advance); converges well within
	for _ = 1, 30 do
		advance(0.02)
		local v = spr:get()
		-- monotonic toward the goal (fp tolerance); an underdamped/sign-swapped solver would dip
		expect(v >= prev - 1e-3, `overdamped spring is monotonic, prev={prev} now={v}`)
		if v > prev + 1e-4 then
			sawProgress = true
		end
		if v > maxSeen then
			maxSeen = v
		end
		prev = v
	end

	expect(sawProgress, "overdamped spring actually advanced toward the goal")
	-- never overshoots above the goal (overdamped has no overshoot)
	expect(maxSeen <= 100 + 1e-3, `overdamped spring never overshoots, peak={maxSeen}`)
	expect(approx(spr:get(), 100, 0.5), `overdamped spring converged, got {spr:get()}`)
end)

test("motion · scope teardown unregisters a spring from the engine", function()
	-- A spring's node is a signal, so the scope does NOT own it (the GC reclaims it once
	-- unreferenced). Its engine registration IS a scope-bound side effect: teardown must drop it
	-- from the engine's active set via the owner cleanup, or the engine would keep stepping it.
	local ms
	local sc = Flux.scope(function()
		ms = Flux.spring(0, 10, 1)
		ms(100) -- retarget so the spring is active in the engine
	end)
	advance(0.01) -- spring is live and being stepped
	local before = ms:get()
	expect(before > 0, "spring advanced while scope was alive")
	sc:Destroy() -- teardown unregisters it from the engine via the owner cleanup
	advance(0.2)
	expect(ms:get() == before, "the engine no longer steps the scope-destroyed spring")
end)

test("motion · vector spring round-trips exactly and converges componentwise", function()
	-- the `vector` packers run wherever typeof() yields "vector" (the Luau CLI);
	-- under Roblox typeof(vector.create(...)) is "Vector3", exercising that packer instead
	local start = vector.create(1.5, -2.25, 3.125)
	local goal = Flux.signal(start)
	local spr = Flux.spring(goal, 10, 1)
	Motion.step()
	expect(spr:get() == start, `resting spring pack/unpack is lossless, got {tostring(spr:get())}`)

	goal:set(vector.create(30, -20, 10))
	flush()
	advance(0.2) -- a freq-10 critically-damped spring is converged within ~0.2s of sim time
	local v = spr:get()
	expect(
		approx(v.x, 30, 0.5) and approx(v.y, -20, 0.5) and approx(v.z, 10, 0.5),
		`vector spring converged componentwise, got {tostring(v)}`
	)
end)

test("motion · impulse/setVelocity/setCurrent/snap warn on a tween node (expected warn)", function()
	local tw = Flux.tween(0, TweenInfo.new(0.2)) :: any
	tw:impulse(100) -- expected warn: :impulse() is only valid on a spring
	tw:setVelocity(100) -- expected warn: :setVelocity() is only valid on a spring
	tw:setCurrent(50) -- expected warn: :setCurrent() is only valid on a spring
	tw:snap(50) -- expected warn: :snap() is only valid on a spring
	expect(approx(tw:get(), 0), "tween value unchanged by spring-only controls")
	tw:Destroy()
end)

test("motion · snap, setCurrent, initialVelocity, reactive frequency/damping, and type guards", function()
	local goal = Flux.signal(0)
	local freq = Flux.signal(10)
	local damp = Flux.signal(1)
	local spr = Flux.spring(goal, freq, damp, 500)
	flush()
	advance(0.02)
	expect(spr:get() > 0, "initialVelocity moved the spring off 0")

	-- snap jumps both current and target to value at zero velocity
	spr:snap(250)
	expect(spr() == 250, "snap sets current value immediately")
	advance(0.05)
	expect(spr() == 250, "snap zeroes velocity and target so spring stays at rest")

	-- setCurrent changes current value without changing target (250), waking the spring
	spr:setCurrent(100)
	expect(spr() == 100, "setCurrent updates animated value immediately")
	advance(0.05)
	expect(spr() > 100, "spring eases back toward target 250 after setCurrent")

	-- reactive frequency and damping update while converging toward goal
	goal:set(250)
	freq:set(20)
	damp:set(0.8)
	flush()
	advance(0.5)
	expect(approx(spr(), 250, 0.5), "converged with updated frequency and damping")

	-- type mismatch guards
	expectError(function()
		spr:set("bad" :: any)
	end, "Cannot retarget")
	expectError(function()
		spr:impulse("bad" :: any)
	end, "Cannot impulse")
	expectError(function()
		spr:setVelocity("bad" :: any)
	end, "Cannot set velocity")
	expectError(function()
		spr:setCurrent("bad" :: any)
	end, "Cannot set a number spring's current value")
	expectError(function()
		spr:snap("bad" :: any)
	end, "Cannot snap")

	spr:Destroy()
end)

test("motion · tween reactive TweenInfo, DelayTime, and easing styles", function()
	local goal = Flux.signal(0)
	local info = Flux.signal(TweenInfo.new(0.4, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0.2))
	local tw = Flux.tween(goal, info)
	goal:set(100)
	flush()

	-- When setupTween is armed with DelayTime > 0, stepTween waits while elapsed < 0
	local rawTween = MotionModule.NodeToMotion[tw] :: any
	MotionModule.Engine.setupTween(rawTween, info:peek())
	advance(0.1)
	expect(approx(tw(), 0), "tween waits during DelayTime")
	advance(0.3) -- 0.2s past delay -> halfway through 0.4s duration
	expect(approx(tw(), 50, 1), "halfway through tween after DelayTime")

	-- Retarget with a new reactive TweenInfo (retargets immediately without DelayTime)
	info:set(TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
	goal:set(200)
	flush()
	advance(0.2)
	expect(approx(tw(), 200, 1e-3), "completed with updated reactive TweenInfo")
	tw:Destroy()

	-- Exercise every easing style and direction via both curve() and get()
	local styles = {
		Enum.EasingStyle.Linear,
		Enum.EasingStyle.Sine,
		Enum.EasingStyle.Back,
		Enum.EasingStyle.Quad,
		Enum.EasingStyle.Quart,
		Enum.EasingStyle.Quint,
		Enum.EasingStyle.Bounce,
		Enum.EasingStyle.Elastic,
		Enum.EasingStyle.Exponential,
		Enum.EasingStyle.Circular,
		Enum.EasingStyle.Cubic,
	}
	local directions = {
		Enum.EasingDirection.In,
		Enum.EasingDirection.Out,
		Enum.EasingDirection.InOut,
	}
	for _, style in styles do
		for _, dir in directions do
			local curve = MotionModule.Easing.curve(style, dir)
			local v0 = curve(0)
			local vMid = MotionModule.Easing.get(0.5, style, dir)
			local v1 = curve(1)
			expect(approx(v0, 0, 2e-3) and approx(v1, 1, 2e-3) and vMid == vMid, `curve {style.Name}/{dir.Name}`)
		end
	end
end)

test("motion · Vector3 spring impulse moves componentwise", function()
	local spr = Flux.spring(Vector3.zero, 10, 1)
	advance(0.05)
	spr:impulse(Vector3.new(0, 200, 0))
	advance(0.05)
	local v = spr:get()
	expect(v.Y > 0 and math.abs(v.X) < 1e-2, `impulse hit Y only, got {tostring(v)}`)
end)

test("motion · Vector3 spring follows a reactive goal", function()
	local goal = Flux.signal(Vector3.zero)
	local spr = Flux.spring(goal, 10, 1)
	goal:set(Vector3.new(0, 50, 0))
	flush()
	advance(0.05)
	local v = spr:get()
	expect(v.Y > 1, `spring moved toward the goal, got {tostring(v)}`)
end)

test("motion · UDim2 tween reaches its goal", function()
	local goal = Flux.signal(UDim2.fromScale(0, 0))
	local tw = Flux.tween(goal, TweenInfo.new(0))
	goal:set(UDim2.fromScale(1, 0))
	flush()
	Motion.step(0) -- 0-duration: alpha clamps to 1 on the first step, value = goal exactly
	local v = tw:get()
	expect(approx(v.X.Scale, 1) and approx(v.X.Offset, 0), `X axis reached the goal exactly, got {tostring(v)}`)
	expect(approx(v.Y.Scale, 0) and approx(v.Y.Offset, 0), `Y axis reached the goal exactly, got {tostring(v)}`)
end)

test("motion · tween linear easing is ~quarter-value at quarter-flight", function()
	-- a linear tween reads ~25 at quarter-flight; Cubic-InOut (the default) reads ~6.25,
	-- and sampling OFF-CENTER avoids the midpoint where both curves read 50
	local goal = Flux.signal(0)
	local tw = Flux.tween(goal, TweenInfo.new(1, Enum.EasingStyle.Linear))
	goal:set(100)
	flush()
	local v = tweenAt(tw, 0.25)
	expect(v > 18 and v < 40, `linear tween ~25 at quarter-flight, got {v}`)
end)

test("motion · tween Reverses heads back toward the start", function()
	local goal = Flux.signal(0)
	-- short forward leg so we land on the reversing leg quickly
	local tw = Flux.tween(goal, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, true))
	goal:set(100)
	flush()
	-- 0.55s in: 0.25s into the reverse leg, off the midpoint (where both read 50), so
	-- dropping `alpha = 1 - alpha` would leave it climbing (~83.3) not falling (~16.7)
	local v = tweenAt(tw, 0.55)
	expect(v < 30, `Reverses=true sent the tween back toward start, got {v}`)
end)

test("motion · tween RepeatCount loops back toward the start", function()
	local goal = Flux.signal(0)
	local tw = Flux.tween(goal, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 2))
	goal:set(100)
	flush()
	-- 0.6s in: 0.1s into the 2nd leg, so the value dropped back near the start (~20)
	local v = tweenAt(tw, 0.6)
	expect(v < 50, `RepeatCount restarted the leg near the start, got {v}`)
end)

test("motion · number tween lands EXACTLY on the goal", function()
	local goal = Flux.signal(0)
	local tw = Flux.tween(goal, TweenInfo.new(0, Enum.EasingStyle.Linear))
	goal:set(42)
	flush()
	Motion.step(0) -- 0-duration: alpha clamps to 1 on the first step, value = goal exactly
	expect(approx(tw:get(), 42, 1e-4), `number tween equals the goal exactly, got {tw:get()}`)
end)

test("motion · UDim2 tween lands EXACTLY on the goal on both axes", function()
	local goal = Flux.signal(UDim2.new(0, 0, 0, 0))
	local tw = Flux.tween(goal, TweenInfo.new(0, Enum.EasingStyle.Linear))
	local target = UDim2.new(0.5, 10, 0.25, 20)
	goal:set(target)
	flush()
	Motion.step(0) -- 0-duration: alpha clamps to 1 on the first step, value = goal exactly
	local v = tw:get()
	expect(approx(v.X.Scale, 0.5, 1e-4), `X.Scale exact, got {v.X.Scale}`)
	expect(approx(v.X.Offset, 10, 1e-4), `X.Offset exact, got {v.X.Offset}`)
	expect(approx(v.Y.Scale, 0.25, 1e-4), `Y.Scale exact, got {v.Y.Scale}`)
	expect(approx(v.Y.Offset, 20, 1e-4), `Y.Offset exact, got {v.Y.Offset}`)
end)

test("motion · Vector2 reaches its goal", function()
	local got = tweenToGoal(Vector2.new(-3, 7), Vector2.new(12.5, -4.25))
	expect(got == Vector2.new(12.5, -4.25), `Vector2 round-trip, got {tostring(got)}`)
end)

test("motion · Vector3 reaches its goal exactly", function()
	local got = tweenToGoal(Vector3.new(-3, 7, 1), Vector3.new(12.5, -4.25, 9))
	expect(got == Vector3.new(12.5, -4.25, 9), `Vector3 round-trip, got {tostring(got)}`)
end)

test("motion · UDim reaches its goal", function()
	-- offset is integer-rounded on unpack; scale is exact
	local got = tweenToGoal(UDim.new(0, 0), UDim.new(0.5, 40))
	expect(got.Scale == 0.5 and got.Offset == 40, `UDim round-trip, got {tostring(got)}`)
end)

test("motion · UDim2 reaches its goal exactly", function()
	-- guards scale/offset arg order: UDim2.new(xScale, xOffset, yScale, yOffset)
	local got = tweenToGoal(UDim2.new(0, 0, 0, 0), UDim2.new(0.25, 30, 0.75, -10))
	expect(
		got.X.Scale == 0.25 and got.X.Offset == 30 and got.Y.Scale == 0.75 and got.Y.Offset == -10,
		`UDim2 round-trip, got {tostring(got)}`
	)
end)

rtest("motion · Rect reaches its goal", function()
	-- packs Min.X, Min.Y, Max.X, Max.Y; unpack Rect.new(arr1..arr4)
	local got = tweenToGoal(Rect.new(0, 0, 1, 1), Rect.new(4, 8, 16, 32))
	expect(got.Min == Vector2.new(4, 8) and got.Max == Vector2.new(16, 32), `Rect round-trip, got {tostring(got)}`)
end)

rtest("motion · NumberRange reaches its goal", function()
	local got = tweenToGoal(NumberRange.new(0, 1), NumberRange.new(3.5, 9.25))
	expect(
		approx(got.Min, 3.5) and approx(got.Max, 9.25),
		`NumberRange round-trip, got {tostring(got.Min)}..{tostring(got.Max)}`
	)
end)

test("motion · NumberSequenceKeypoint reaches its goal", function()
	-- guards arg order: NumberSequenceKeypoint.new(time, value, envelope)
	-- where pack stores [time, value, envelope] and unpack passes (arr1, arr2, arr3)
	local goal = NumberSequenceKeypoint.new(0.4, 0.8, 0.1) -- (time, value, envelope)
	local got = tweenToGoal(NumberSequenceKeypoint.new(0, 0, 0), goal)
	expect(
		approx(got.Time, 0.4) and approx(got.Value, 0.8) and approx(got.Envelope, 0.1),
		`NSK round-trip time={got.Time} value={got.Value} env={got.Envelope}`
	)
end)

test("motion · NumberSequence reaches its goal", function()
	-- guards the keypoint loop stride (3 numbers per keypoint: time, value, envelope)
	-- and the NumberSequenceKeypoint.new(time, value, envelope) rebuild order.
	-- keypoint COUNTS must match: the motion's packed length is fixed at creation.
	local start = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0, 0),
		NumberSequenceKeypoint.new(0.5, 0.5, 0),
		NumberSequenceKeypoint.new(1, 1, 0),
	})
	local goal = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25, 0.05),
		NumberSequenceKeypoint.new(0.4, 0.9, 0.1),
		NumberSequenceKeypoint.new(1, 0.1, 0.2),
	})
	local got = tweenToGoal(start, goal)
	expect(#got.Keypoints == 3, `keypoint count preserved, got {#got.Keypoints}`)
	for i, k in goal.Keypoints do
		local g = got.Keypoints[i]
		expect(
			approx(g.Time, k.Time) and approx(g.Value, k.Value) and approx(g.Envelope, k.Envelope),
			`NS keypoint {i} round-trip, got time={g.Time} value={g.Value} env={g.Envelope}`
		)
	end
end)

test("motion · ColorSequenceKeypoint reaches its goal", function()
	-- Time is exact; the Value color round-trips through Oklab (lossy) so use eps
	local goal = ColorSequenceKeypoint.new(0.6, Color3.new(0.2, 0.4, 0.8))
	local got = tweenToGoal(ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)), goal)
	local c = got.Value
	expect(approx(got.Time, 0.6), `CSK time round-trip, got {got.Time}`)
	expect(
		approx(c.R, 0.2, 3e-3) and approx(c.G, 0.4, 3e-3) and approx(c.B, 0.8, 3e-3),
		`CSK color round-trip, got {tostring(c)}`
	)
end)

test("motion · ColorSequence reaches its goal", function()
	-- guards the keypoint loop stride (4 numbers per keypoint: time + Oklab xyz).
	-- keypoint COUNTS must match: the motion's packed length is fixed at creation.
	-- times round-trip exactly; the colors go through Oklab (lossy) so use eps.
	local start = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 0, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.new(0, 1, 0)),
		ColorSequenceKeypoint.new(1, Color3.new(0, 0, 1)),
	})
	local goal = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(0.2, 0.4, 0.8)),
		ColorSequenceKeypoint.new(0.25, Color3.new(0.9, 0.1, 0.5)),
		ColorSequenceKeypoint.new(1, Color3.new(0.05, 0.95, 0.35)),
	})
	local got = tweenToGoal(start, goal)
	expect(#got.Keypoints == 3, `keypoint count preserved, got {#got.Keypoints}`)
	for i, k in goal.Keypoints do
		local g = got.Keypoints[i]
		local c, e = g.Value, k.Value
		expect(approx(g.Time, k.Time, 1e-4), `CS keypoint {i} time round-trip, got {g.Time}`)
		expect(
			approx(c.R, e.R, 3e-3) and approx(c.G, e.G, 3e-3) and approx(c.B, e.B, 3e-3),
			`CS keypoint {i} color round-trip, got {tostring(c)}`
		)
	end
end)

test("motion · Color3 reaches its goal", function()
	-- Oklab round-trip is lossy, so use eps
	local goal = Color3.new(0.9, 0.1, 0.5)
	local got = tweenToGoal(Color3.new(0, 0, 0), goal)
	expect(
		approx(got.R, 0.9, 3e-3) and approx(got.G, 0.1, 3e-3) and approx(got.B, 0.5, 3e-3),
		`Color3 round-trip, got {tostring(got)}`
	)
end)

rtest("motion · CFrame reaches its goal", function()
	-- position round-trips exactly; rotation goes through ToAxisAngle ->
	-- fromAxisAngle(axis.Unit, angle), so compare via component equality with eps
	local goal = CFrame.new(5, -2, 8) * CFrame.Angles(0, math.rad(90), 0)
	local got = tweenToGoal(CFrame.new(0, 0, 0), goal)
	local pos = got.Position
	expect(
		approx(pos.X, 5, 1e-3) and approx(pos.Y, -2, 1e-3) and approx(pos.Z, 8, 1e-3),
		`CFrame position round-trip, got {tostring(pos)}`
	)
	-- rotation fidelity: every rotation-matrix component must match the goal
	local ga = { goal:GetComponents() }
	local na = { got:GetComponents() }
	local ok = true
	for i = 4, 12 do -- indices 4..12 are the 3x3 rotation submatrix
		if not approx(na[i], ga[i], 1e-3) then
			ok = false
		end
	end
	expect(ok, `CFrame rotation round-trip mismatch, got {tostring(got)}`)
end)

rtest("motion · NumberRange degenerate (Min==Max) reaches its goal", function()
	-- separate guard: a zero-width range must not collapse arg order
	local got = tweenToGoal(NumberRange.new(2, 2), NumberRange.new(5, 5))
	expect(
		approx(got.Min, 5) and approx(got.Max, 5),
		`degenerate NumberRange, got {tostring(got.Min)}..{tostring(got.Max)}`
	)
end)

test("motion · :set() and call-write on a destroyed motion warn and return early (expected warn)", function()
	local spr = Flux.spring(0)
	spr:Destroy()
	-- Calling :set() or spr(val) on a destroyed motion should warn and not mutate or crash
	spr:set(100)
	spr(200)
	expect(spr:get() == nil, "destroyed motion node remains stripped after :set() and call-write")
end)

test("motion · waking a sleeping motion inside step callback does not corrupt iteration", function()
	local b = Flux.tween(0, TweenInfo.new(0, Enum.EasingStyle.Linear))
	local a = Flux.tween(0, TweenInfo.new(0, Enum.EasingStyle.Linear))
	local motionA = MotionModule.NodeToMotion[a]
	local origUnpack = motionA.unpack
	motionA.unpack = function(arr)
		b:set(50)
		return origUnpack(arr)
	end
	a:set(10)
	Motion.step(0)
	expect(approx(a:get(), 10), "first tween completed")
	Motion.step(0)
	expect(approx(b:get(), 50), "woken second tween completed on subsequent step")
	a:Destroy()
	b:Destroy()
end)

return {}
