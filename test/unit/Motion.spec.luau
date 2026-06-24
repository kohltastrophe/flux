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
local Graph = Flux.Graph
local Motion = Flux.Motion
local MotionEngine = Motion.Engine

local approx = sert.approx

-- Advance the Motion engine by `dt` seconds of SIMULATED time, no real wait: a
-- spring steps off os.clock() - Engine.now, so rewinding Engine.now fakes the
-- elapsed time and the analytic solver lands exactly where a real sleep would.
local function advance(dt: number)
	MotionEngine.now = os.clock() - dt
	Motion.step()
end

-- Drive a Flux.tween node to `elapsed` seconds of simulated time instantly: a tween
-- steps off now - startTime, so rewind startTime onto the os.clock timeline and step
-- once. `elapsed` may exceed the duration (clamps to goal) or be negative (DelayTime).
local function tweenAt(node: any, elapsed: number): any
	Motion.NodeToMotion[node].startTime = os.clock() - elapsed
	Motion.step()
	return node:get()
end

local function tweenToGoal(start: any, goal: any)
	-- a 0-duration Linear tween clamps alpha to 1 on the first step, so one Motion.step()
	-- lands the value on the goal exactly; the pack/unpack round-trip these tests verify
	local tw = Flux.tween(start, TweenInfo.new(0, Enum.EasingStyle.Linear))
	tw:set(goal)
	flush()
	Motion.step()
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
		ms = Flux.spring(0, 1, 1)
		ms(100) -- retarget so the spring is active in the engine
	end)
	advance(0.01) -- spring is live and being stepped
	sc:Destroy() -- teardown unregisters it from the engine via the owner cleanup
	expect(Motion.NodeToMotion[ms] == nil, "the spring is unregistered from the engine on scope teardown")
	local ok = pcall(function()
		advance(0.01)
	end)
	expect(ok, "the engine no longer steps the scope-destroyed spring")
end)

rtest("motion · impulse/setVelocity warn on a tween node (expected warn)", function()
	-- a tween carries the Motion metatable, so the methods EXIST and the guard's
	-- reject path is genuinely exercised (TweenInfo is Roblox-only -> rtest)
	local tw = Flux.tween(0, TweenInfo.new(0.2))
	tw:impulse(100) -- expected warn: :impulse() is only valid on a spring
	tw:setVelocity(100) -- expected warn: :setVelocity() is only valid on a spring
	expect(approx(tw:get(), 0), "tween value unchanged by velocity controls")
end)

rtest("motion · Vector3 spring impulse moves componentwise", function()
	local spr = Flux.spring(Vector3.zero, 10, 1)
	advance(0.05)
	spr:impulse(Vector3.new(0, 200, 0))
	advance(0.05)
	local v = spr:get()
	expect(v.Y > 0 and math.abs(v.X) < 1e-2, `impulse hit Y only, got {tostring(v)}`)
end)

rtest("motion · Vector3 spring follows a reactive goal", function()
	local goal = Flux.signal(Vector3.zero)
	local spr = Flux.spring(goal, 10, 1)
	goal:set(Vector3.new(0, 50, 0))
	flush()
	advance(0.05)
	local v = spr:get()
	expect(v.Y > 1, `spring moved toward the goal, got {tostring(v)}`)
end)

rtest("motion · UDim2 tween reaches its goal", function()
	local goal = Flux.signal(UDim2.fromScale(0, 0))
	local tw = Flux.tween(goal, TweenInfo.new(0))
	goal:set(UDim2.fromScale(1, 0))
	flush()
	Motion.step() -- 0-duration: alpha clamps to 1 on the first step, value = goal exactly
	local v = tw:get()
	expect(approx(v.X.Scale, 1) and approx(v.X.Offset, 0), `X axis reached the goal exactly, got {tostring(v)}`)
	expect(approx(v.Y.Scale, 0) and approx(v.Y.Offset, 0), `Y axis reached the goal exactly, got {tostring(v)}`)
end)

rtest("motion · tween linear easing is ~quarter-value at quarter-flight", function()
	-- a linear tween reads ~25 at quarter-flight; Cubic-InOut (the default) reads ~6.25,
	-- and sampling OFF-CENTER avoids the midpoint where both curves read 50
	local goal = Flux.signal(0)
	local tw = Flux.tween(goal, TweenInfo.new(1, Enum.EasingStyle.Linear))
	goal:set(100)
	flush()
	local v = tweenAt(tw, 0.25)
	expect(v > 18 and v < 40, `linear tween ~25 at quarter-flight, got {v}`)
end)

rtest("motion · tween Reverses heads back toward the start", function()
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

rtest("motion · tween RepeatCount loops back toward the start", function()
	local goal = Flux.signal(0)
	local tw = Flux.tween(goal, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 2))
	goal:set(100)
	flush()
	-- 0.6s in: 0.1s into the 2nd leg, so the value dropped back near the start (~20)
	local v = tweenAt(tw, 0.6)
	expect(v < 50, `RepeatCount restarted the leg near the start, got {v}`)
end)

rtest("motion · tween DelayTime suppresses movement until the delay elapses", function()
	-- DelayTime is honored only by the engine's setupTween (the public set()/reactive
	-- paths reset startTime and drop it), so drive the Engine directly. Check both the
	-- startTime stamp and, via startTime rewinds, the value either side of the delay.
	local Engine = Motion.Engine
	local node = Graph.new(0)
	local tw = Engine.newTween(1, "number", node)
	Engine.setCurrent(tw, { 0 })
	local setupNow = Engine.now
	-- 0.4s delay, then a 0.3s linear ramp
	Engine.setupTween(tw, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0.4))
	tw.target[1] = 100 -- aim at 100 without resetting startTime (setupTween queued it active)

	-- setupTween stamps startTime = now + DelayTime (drop it and this is just setupNow)
	expect(approx(tw.startTime, setupNow + 0.4, 1e-4), `DelayTime applied to startTime, got +{tw.startTime - setupNow}`)

	-- behaviour: elapsed < 0 (inside the delay) holds the start value...
	tw.startTime = os.clock() + 0.2
	Motion.step()
	expect(approx(node:get(), 0, 1e-3), `no movement during DelayTime, got {node:get()}`)
	-- ...and past the 0.3s ramp it reaches the goal.
	tw.startTime = os.clock() - 0.5
	Motion.step()
	expect(approx(node:get(), 100, 1e-4), `tween moved to the goal after the delay, got {node:get()}`)
end)

rtest("motion · number tween lands EXACTLY on the goal", function()
	local goal = Flux.signal(0)
	local tw = Flux.tween(goal, TweenInfo.new(0, Enum.EasingStyle.Linear))
	goal:set(42)
	flush()
	Motion.step() -- 0-duration: alpha clamps to 1 on the first step, value = goal exactly
	expect(approx(tw:get(), 42, 1e-4), `number tween equals the goal exactly, got {tw:get()}`)
end)

rtest("motion · UDim2 tween lands EXACTLY on the goal on both axes", function()
	local goal = Flux.signal(UDim2.new(0, 0, 0, 0))
	local tw = Flux.tween(goal, TweenInfo.new(0, Enum.EasingStyle.Linear))
	local target = UDim2.new(0.5, 10, 0.25, 20)
	goal:set(target)
	flush()
	Motion.step() -- 0-duration: alpha clamps to 1 on the first step, value = goal exactly
	local v = tw:get()
	expect(approx(v.X.Scale, 0.5, 1e-4), `X.Scale exact, got {v.X.Scale}`)
	expect(approx(v.X.Offset, 10, 1e-4), `X.Offset exact, got {v.X.Offset}`)
	expect(approx(v.Y.Scale, 0.25, 1e-4), `Y.Scale exact, got {v.Y.Scale}`)
	expect(approx(v.Y.Offset, 20, 1e-4), `Y.Offset exact, got {v.Y.Offset}`)
end)

rtest("motion · Vector2 reaches its goal", function()
	local got = tweenToGoal(Vector2.new(-3, 7), Vector2.new(12.5, -4.25))
	expect(got == Vector2.new(12.5, -4.25), `Vector2 round-trip, got {tostring(got)}`)
end)

rtest("motion · Vector2int16 reaches its goal", function()
	local got = tweenToGoal(Vector2int16.new(-3, 7), Vector2int16.new(120, -40))
	expect(got == Vector2int16.new(120, -40), `Vector2int16 round-trip, got {tostring(got)}`)
end)

rtest("motion · Vector3 reaches its goal exactly", function()
	local got = tweenToGoal(Vector3.new(-3, 7, 1), Vector3.new(12.5, -4.25, 9))
	expect(got == Vector3.new(12.5, -4.25, 9), `Vector3 round-trip, got {tostring(got)}`)
end)

rtest("motion · Vector3int16 reaches its goal", function()
	local got = tweenToGoal(Vector3int16.new(-3, 7, 1), Vector3int16.new(120, -40, 33))
	expect(got == Vector3int16.new(120, -40, 33), `Vector3int16 round-trip, got {tostring(got)}`)
end)

rtest("motion · UDim reaches its goal", function()
	-- offset is integer-rounded on unpack; scale is exact
	local got = tweenToGoal(UDim.new(0, 0), UDim.new(0.5, 40))
	expect(got.Scale == 0.5 and got.Offset == 40, `UDim round-trip, got {tostring(got)}`)
end)

rtest("motion · UDim2 reaches its goal exactly", function()
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

rtest("motion · NumberSequenceKeypoint reaches its goal", function()
	-- guards arg order: NumberSequenceKeypoint.new(time, value, envelope)
	-- where pack stores [value, time, envelope] and unpack passes (arr2, arr1, arr3)
	local goal = NumberSequenceKeypoint.new(0.4, 0.8, 0.1) -- (time, value, envelope)
	local got = tweenToGoal(NumberSequenceKeypoint.new(0, 0, 0), goal)
	expect(
		approx(got.Time, 0.4) and approx(got.Value, 0.8) and approx(got.Envelope, 0.1),
		`NSK round-trip time={got.Time} value={got.Value} env={got.Envelope}`
	)
end)

rtest("motion · ColorSequenceKeypoint reaches its goal", function()
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

rtest("motion · Color3 reaches its goal", function()
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

rtest("motion · Region3 reaches its goal", function()
	-- pack stores CFrame center + Size; unpack rebuilds via center ± halfSize.
	-- A wrong center/halfSize reconstruction would shift position or size.
	local start = Region3.new(Vector3.new(0, 0, 0), Vector3.new(2, 2, 2))
	local goal = Region3.new(Vector3.new(2, 4, 6), Vector3.new(12, 16, 20))
	local got = tweenToGoal(start, goal)
	local center = got.CFrame.Position
	local size = got.Size
	expect(
		approx(center.X, 7, 1e-3) and approx(center.Y, 10, 1e-3) and approx(center.Z, 13, 1e-3),
		`Region3 center round-trip, got {tostring(center)}`
	)
	expect(
		approx(size.X, 10, 1e-3) and approx(size.Y, 12, 1e-3) and approx(size.Z, 14, 1e-3),
		`Region3 size round-trip, got {tostring(size)}`
	)
end)

rtest("motion · Region3int16 reaches its goal", function()
	-- integer Min/Max, rounded on unpack; exact integers round-trip exactly
	local start = Region3int16.new(Vector3int16.new(0, 0, 0), Vector3int16.new(1, 1, 1))
	local goal = Region3int16.new(Vector3int16.new(-4, -8, -12), Vector3int16.new(16, 24, 32))
	local got = tweenToGoal(start, goal)
	expect(
		got.Min == Vector3int16.new(-4, -8, -12) and got.Max == Vector3int16.new(16, 24, 32),
		`Region3int16 round-trip, got Min={tostring(got.Min)} Max={tostring(got.Max)}`
	)
end)

rtest("motion · Ray reaches its goal", function()
	-- packs Origin xyz + Direction xyz; unpack rebuilds both Vector3s
	local goal = Ray.new(Vector3.new(1, 2, 3), Vector3.new(4, 5, 6))
	local got = tweenToGoal(Ray.new(Vector3.zero, Vector3.zero), goal)
	expect(
		got.Origin == Vector3.new(1, 2, 3) and got.Direction == Vector3.new(4, 5, 6),
		`Ray round-trip, origin={tostring(got.Origin)} dir={tostring(got.Direction)}`
	)
end)

rtest("motion · PhysicalProperties reaches its goal", function()
	-- packs Density, Friction, Elasticity, FrictionWeight, ElasticityWeight in order
	local goal = PhysicalProperties.new(2.5, 0.6, 0.3, 1.5, 2.0)
	local got = tweenToGoal(PhysicalProperties.new(1, 0.2, 0.1, 1, 1), goal)
	expect(
		approx(got.Density, 2.5, 1e-3)
			and approx(got.Friction, 0.6, 1e-3)
			and approx(got.Elasticity, 0.3, 1e-3)
			and approx(got.FrictionWeight, 1.5, 1e-3)
			and approx(got.ElasticityWeight, 2.0, 1e-3),
		`PhysicalProperties round-trip, got d={got.Density} f={got.Friction} e={got.Elasticity} fw={got.FrictionWeight} ew={got.ElasticityWeight}`
	)
end)

rtest("motion · DateTime reaches its goal", function()
	-- packs UnixTimestampMillis (an integer); at alpha==1 it round-trips exactly
	local goalMs = 1_700_000_000_000
	local goal = DateTime.fromUnixTimestampMillis(goalMs)
	local got = tweenToGoal(DateTime.fromUnixTimestampMillis(0), goal)
	expect(got.UnixTimestampMillis == goalMs, `DateTime round-trip, got {got.UnixTimestampMillis}`)
end)

return {}
