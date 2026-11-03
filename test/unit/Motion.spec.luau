--!nonstrict
local env = if game
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Motion = if game
	then require((game :: any).ReplicatedStorage.Flux.Motion) :: any
	else require("../../src/Motion") :: any

local Flux = env.Flux
local Compat = env.Compat
local sert = env.sert
local test = sert.test
local rtest = sert.rtest
local expect = sert
local expectError = sert.fails
local flush = Flux.flush
local Engine = Motion.Engine
local Easing = Motion.Easing
local near = sert.near
local prop = sert.prop
local advance = Flux.Motion.step

local function damping(g: any): number
	local branch = g:pick({ "critical", "under", "over" })
	return if branch == "critical" then 1 elseif branch == "under" then g:float(0.05, 0.98) else g:float(1.02, 3)
end

local function away(g: any, start: number): number
	local gap = g:float(100, 1000)
	return if g:bool() then start + gap else start - gap
end

local STYLES = string.split("Linear Sine Back Quad Quart Quint Bounce Elastic Exponential Circular Cubic", " ")
local DIRECTIONS = { "In", "Out", "InOut" }

local function info(time: number, style: string?, way: string?, repeats: number?, reverses: boolean?, delay: number?)
	local easing, direction = Compat.Enum.EasingStyle[style or "Quad"], Compat.Enum.EasingDirection[way or "Out"]
	return Compat.TweenInfo.new(time, easing, direction, repeats or 0, reverses or false, delay or 0)
end

local function springs(count: number, start: any, frequency: number, ratio: number): ...any
	local list = {}
	local scope = Flux.scope(function()
		for index = 1, count do
			list[index] = Flux.spring(start, frequency, ratio)
		end
	end)
	return scope, table.unpack(list)
end

local function tweenToGoal(start: any, goal: any)
	local tw = Flux.tween(start, info(0, "Linear"))
	tw:set(goal)
	flush()
	advance(0)
	return tw:get()
end

test("motion · nil-goal fallback warns, follows and survives retarget", function()
	local goal = Flux.signal(nil)
	local spr
	local warnings = env.warnings(function()
		spr = Flux.spring(goal)
	end)
	expect.eq(warnings, { "[Flux] Animating a nil value; following the goal without animation" })
	goal:set(5)
	flush()
	expect(spr:get() == 5, "fallback follows the goal")
	spr:set(99)
	expect(spr:get() == 99, "retarget writes")
	goal:set(7)
	flush()
	expect(spr:get() == 7, "STILL follows after retarget")
	spr:Destroy()
end)

test("motion · setCurrent publishes immediately while preserving target and velocity", function()
	local scope, moving, resting = springs(2, 10, 10, 1)
	moving:setVelocity(50)
	moving:setCurrent(3)
	resting:setCurrent(3)
	expect(moving:get() == 3, "the observable value changes before another motion frame")
	advance(0.01)
	expect(moving:get() > resting:get() and resting:get() > 3, "the caller's momentum is kept")
	advance(1)
	sert.near(moving:get(), 10, 1e-2, "the spring settles on its original target, not the set value")
	scope:Destroy()
end)

test("motion · snap jumps to the value at rest", function()
	local scope, spring = springs(1, 10, 10, 1)
	spring:setVelocity(50)
	advance(0.01)
	spring:snap(3)
	expect(spring:get() == 3, "the node reads the snapped value before another motion frame")
	advance(0.1)
	expect(
		spring:get() == 3,
		`a snapped spring is at rest on the value (no velocity, no old target), got {spring:get()}`
	)
	spring:snap(Flux(7))
	expect(spring:get() == 7, "a node argument is read")
	expectError(function()
		spring:snap("far" :: any)
	end, "Cannot snap a number spring to a string value")
	scope:Destroy()
end)

test("motion · initialVelocity and reactive frequency/damping update while converging", function()
	local goal = Flux.signal(0)
	local freq = Flux.signal(10)
	local damp = Flux.signal(1)
	local spr = Flux.spring(goal, freq, damp, 500)
	flush()
	advance(0.02)
	expect(spr:get() > 0, "initialVelocity moved the spring off 0")

	goal:set(250)
	freq:set(20)
	damp:set(0.8)
	flush()
	advance(0.5)
	sert.near(spr(), 250, 0.5, "converged with updated frequency and damping")
	spr:Destroy()
end)

test("motion · values of the wrong type error at the call site and change nothing", function()
	local Color3, UDim2 = Compat.Color3, Compat.UDim2
	local scope, motions = Flux.scope(function()
		return { Flux.spring(10, 10, 1), Flux.spring(Color3.new(1, 0, 0), 10, 1), Flux.tween(UDim2.fromScale(0, 0)) }
	end)
	local number, color, tween = motions[1], motions[2], motions[3]
	for _, case in
		{
			{ Flux.spring, true, nil, "Cannot animate a boolean value" },
			{ Flux.tween, "nope", nil, "Cannot animate a string value" },
			{ number.setCurrent, number, "far", "Cannot set a number spring's current value to a string value" },
			{ number.impulse, number, "bad", "Cannot impulse" },
			{ number.setVelocity, number, "bad", "Cannot set velocity" },
			{ color.set, color, UDim2.fromScale(1, 1), "Cannot retarget a Color3 motion with a UDim2 value" },
			{ color.snap, color, Compat.Vector3.zero, "Cannot snap a Color3 spring to a Vector3 value" },
			{ tween.set, tween, Color3.new(0, 0, 1), "Cannot retarget a UDim2 motion with a Color3 value" },
		}
	do
		expectError(function()
			return case[1](case[2], case[3])
		end, case[4])
	end
	expect(number:get() == 10 and color:get() == Color3.new(1, 0, 0), "a rejected value leaves the motion alone")
	scope:Destroy()
end)

test("motion · impulse kicks a resting spring and wakes a converged one", function()
	local goal = Flux(0)
	local spr = Flux.spring(goal, 10, 1)
	Motion.step()
	sert.near(spr:get(), 0, nil, "starts at rest at 0")
	spr:impulse(500)
	advance(0.05)
	expect(spr:get() > 0, `impulse moved the spring off rest, got {spr:get()}`)
	advance(0.2)
	sert.near(spr:get(), 0, 0.5, `spring returns to target after impulse, got {spr:get()}`)

	goal:set(50)
	flush()
	advance(0.2)
	sert.near(spr:get(), 50, 0.5, "converged to 50")
	spr:impulse(-300)
	advance(0.03)
	expect(spr:get() < 50, `impulse re-woke the converged spring, got {spr:get()}`)
	spr:Destroy()
end)

test("motion · scope teardown unregisters a spring from the engine", function()
	local sc, ms = springs(1, 0, 1, 1)
	ms(100)
	advance(0.01)
	local moved = ms:get()
	expect(moved > 0, "the spring is live and being stepped")
	sc:Destroy()
	advance(0.1)
	expect(ms:get() == moved, "the engine no longer steps the scope-destroyed spring")
end)

test("motion · :set() and call-write on a destroyed motion warn and return early", function()
	local spr = Flux.spring(0)
	spr:Destroy()
	local warnings = env.warnings(function()
		spr:set(100)
		spr(200)
	end)
	expect(#warnings == 2, `warned twice on destroyed motion writes, got {#warnings}`)
	expect(spr:get() == nil, "destroyed motion node remains stripped after :set() and call-write")
end)

test("motion · waking a sleeping motion inside step callback does not corrupt iteration", function()
	local b = Flux.tween(0, info(0, "Linear"))
	local a = Flux.tween(0, info(0, "Linear"))
	local motionA = Motion.NodeToMotion[a]
	local origUnpack = motionA.unpack
	motionA.unpack = function(arr)
		b:set(50)
		return origUnpack(arr)
	end
	a:set(10)
	advance(0)
	sert.near(a:get(), 10, nil, "first tween completed")
	advance(0)
	sert.near(b:get(), 50, nil, "woken second tween completed on subsequent step")
	a:Destroy()
	b:Destroy()
end)

prop("motion · a spring stepped by a then b lands where one step of a + b does", function(g)
	local frequency, ratio = g:float(0.2, 3), damping(g)
	local start = g:float(-1000, 1000)
	local goal, velocity = away(g, start), g:float(-2000, 2000)
	local a, b = g:float(0, 0.25), g:float(0, 0.25)
	g:note(
		"frequency %g damping %g start %g goal %g velocity %g a %g b %g",
		frequency,
		ratio,
		start,
		goal,
		velocity,
		a,
		b
	)
	local function run(steps: { number }): number
		local scope, spring = springs(1, start, frequency, ratio)
		spring(goal)
		spring:setVelocity(velocity)
		for _, dt in steps do
			advance(dt)
		end
		local value = spring:get()
		scope:Destroy()
		return value
	end
	sert.near(run({ a, b }), run({ a + b }), 1e-6, "step(a) + step(b) == step(a + b)")
end, { runs = 200 })

prop("motion · from rest, an underdamped spring crosses the target at its first damped half-period", function(g)
	local frequency = g:float(0.5, 5)
	local ratio = g:float(0.05, 0.95)
	local start = g:float(-1000, 1000)
	local goal = away(g, start)
	local side = if start > goal then 1 else -1
	local scope, spring = springs(1, start, frequency, ratio)
	spring(goal)
	advance(math.pi / (math.tau * frequency * math.sqrt(1 - ratio * ratio)))
	expect((spring:get() - goal) * side < 0, `did not overshoot: {spring:get()}`)
	scope:Destroy()
end, { runs = 100 })

prop("motion · a vector spring moves like three independent number springs", function(g)
	local frequency, ratio = g:float(0.2, 5), damping(g)
	local start, goal, velocity = {}, {}, {}
	for i = 1, 3 do
		start[i] = g:float(-1000, 1000)
		goal[i] = if g:bool(0.2) then start[i] else away(g, start[i])
		velocity[i] = g:float(-2000, 2000)
	end
	local function f32(values: { number }): { number }
		local v = vector.create(values[1], values[2], values[3])
		return { v.x, v.y, v.z }
	end
	start, goal, velocity = f32(start), f32(goal), f32(velocity)
	local origin = vector.create(start[1], start[2], start[3])
	local vec, numbers = nil, {}
	local scope = Flux.scope(function()
		for i = 1, 3 do
			numbers[i] = Flux.spring(start[i], frequency, ratio)
		end
		vec = Flux.spring(origin, frequency, ratio)
	end)
	expect(vec:get() == origin, `a resting vector spring is lossless, got {tostring(vec:get())}`)

	vec(vector.create(goal[1], goal[2], goal[3]))
	vec:setVelocity(vector.create(velocity[1], velocity[2], velocity[3]))
	for i = 1, 3 do
		numbers[i](goal[i])
		numbers[i]:setVelocity(velocity[i])
	end
	advance(g:float(1 / 240, 0.25))
	local v = vec:get()
	for i, component in { v.x, v.y, v.z } do
		local want = numbers[i]:get()
		local close = math.abs(component - want) <= 2e-4 + 1e-6 * math.abs(want)
		expect(close, `component {i}: vector {component}, number {want}`)
	end
	scope:Destroy()
end, { runs = 100 })

prop("motion · impulses add: a run of impulses moves a spring like one impulse of their sum", function(g)
	local frequency, ratio = g:float(0.2, 5), damping(g)
	local rest = g:float(-1000, 1000)
	local kicks = g:list(function()
		return g:float(-2000, 2000)
	end, 1, 5)
	local sum = 0
	for _, kick in kicks do
		sum += kick
	end
	local scope, many, one = springs(2, rest, frequency, ratio)
	for _, kick in kicks do
		many:impulse(kick)
	end
	one:impulse(sum)
	advance(g:float(1 / 240, 0.25))
	expect(many:get() == one:get(), `impulses {table.concat(kicks, ", ")}: {many:get()} vs {one:get()}`)
	scope:Destroy()
end, { runs = 150 })

prop("motion · setVelocity replaces every earlier impulse", function(g)
	local frequency, ratio = g:float(0.2, 5), damping(g)
	local start = g:float(-1000, 1000)
	local goal = if g:bool() then start else away(g, start)
	local velocity = g:weighted({ { 1, 0 }, { 2, g:float(-2000, 2000) } })
	local kicks = g:list(function()
		return g:float(-2000, 2000)
	end, 1, 5)
	local scope, kicked, clean = springs(2, start, frequency, ratio)
	kicked(goal)
	clean(goal)
	for _, kick in kicks do
		kicked:impulse(kick)
	end
	kicked:setVelocity(velocity)
	clean:setVelocity(velocity)
	advance(g:float(1 / 240, 0.25))
	expect(kicked:get() == clean:get(), `velocity {velocity}: {kicked:get()} vs {clean:get()}`)
	scope:Destroy()
end, { runs = 150 })

test("motion · impulse/setVelocity/setCurrent/snap warn on a tween node", function()
	local tw = Flux.tween(0, info(0.2)) :: any
	local warnings = env.warnings(function()
		tw:impulse(100)
		tw:setVelocity(100)
		tw:setCurrent(50)
		tw:snap(50)
	end)
	expect(#warnings == 4, `one warning per spring-only method, got {#warnings}`)
	for index, method in { "impulse", "setVelocity", "setCurrent", "snap" } do
		expect(string.find(warnings[index], `:{method}() is only valid on a spring`, 1, true) ~= nil, warnings[index])
	end
	sert.near(tw:get(), 0, nil, "tween value unchanged by velocity controls")
	tw:Destroy()
end)

test("motion · Vector3 spring impulse moves componentwise", function()
	local spr = Flux.spring(Compat.Vector3.zero, 10, 1)
	advance(0.05)
	spr:impulse(Compat.Vector3.new(0, 200, 0))
	advance(0.05)
	local v = spr:get()
	expect(v.Y > 0 and math.abs(v.X) < 1e-2, `impulse hit Y only, got {tostring(v)}`)
	spr:Destroy()
end)

test("motion · a linear tween, reversing or repeating, reads its fraction of the way", function()
	for _, case in
		{
			{ "quarter-flight", info(1, "Linear"), 0.25, 25 },
			{ "0.25 s into the reverse leg", info(0.3, "Linear", "Out", 0, true), 0.55, 100 / 6 },
			{ "0.1 s into the second leg", info(0.5, "Linear", "Out", 2), 0.6, 20 },
		}
	do
		local goal = Flux.signal(0)
		local tw = Flux.tween(goal, case[2])
		goal:set(100)
		flush()
		advance(case[3])
		sert.near(tw:get(), case[4], 1e-4, `{case[1]}: want {case[4]}, got {tw:get()}`)
		tw:Destroy()
	end
end)

test("motion · tween DelayTime holds the start until the delay elapses", function()
	local node = Flux.signal(0)
	local tw = Engine.newTween(1, "number", node)
	Engine.snap(tw, { 0 })
	Engine.setupTween(tw, info(0.3, "Linear", "Out", 0, false, 0.4))
	tw.target[1] = 100

	advance(0.2)
	expect(node:get() == 0, `no movement during DelayTime, got {node:get()}`)
	advance(0.35)
	sert.near(node:get(), 50, 1e-4, `half way after the delay, got {node:get()}`)
	advance(0.3)
	expect(node:get() == 100, `tween reached the goal after the delay, got {node:get()}`)
	Engine.destroy(tw)
end)

test("motion · a tween retarget drops DelayTime and reactive TweenInfo updates", function()
	local goal = Flux.signal(0)
	local infoSig = Flux.signal(info(1, "Linear", "Out", 0, false, 5))
	local scope, tw = Flux.scope(function()
		return Flux.tween(goal, infoSig)
	end)
	goal:set(100)
	flush()
	advance(0.5)
	sert.near(tw:get(), 50, 1e-4, `a retarget starts at once, got {tw:get()}`)
	infoSig:set(info(0.2, "Quad", "In"))
	goal:set(200)
	flush()
	advance(0.2)
	sert.near(tw:get(), 200, 1e-3, "completed with updated reactive TweenInfo")
	scope:Destroy()
end)

test(
	"motion · unchanged getter target does not reset an in-flight tween, and resting config updates stay asleep",
	function()
		local count = Flux.signal(1)
		local freq = Flux.signal(4)
		local damp = Flux.signal(1)
		local infoSig = Flux.signal(info(1, "Linear"))
		local scope, results = Flux.scope(function()
			local tw = Flux.tween(function()
				return if count() > 0 then 300 else 0
			end, infoSig)
			local spr = Flux.spring(10, freq, damp)
			local restingTw = Flux.tween(10, infoSig)
			return { tw, spr, restingTw }
		end)
		local tw, spr, restingTw = results[1], results[2], results[3]
		local twMotion = Motion.NodeToMotion[tw]
		local sprMotion = Motion.NodeToMotion[spr]
		local restingTwMotion = Motion.NodeToMotion[restingTw]

		flush()
		expect(not Engine.isActive(twMotion), "tween with getter target starts at rest before target changes")
		expect(not Engine.isActive(sprMotion), "spring with reactive freq/damp starts at rest")
		expect(not Engine.isActive(restingTwMotion), "tween with reactive TweenInfo starts at rest")

		freq:set(8)
		damp:set(0.9)
		infoSig:set(info(1, "Linear"))
		flush()
		expect(not Engine.isActive(sprMotion), "updating reactive freq/damp on a resting spring keeps it at rest")
		expect(not Engine.isActive(restingTwMotion), "updating reactive TweenInfo on a resting tween keeps it at rest")

		count:set(0)
		flush()
		advance(1)
		sert.near(tw:get(), 0, 1e-4, "tween reached 0")

		count:set(1)
		flush()
		advance(0.5)
		sert.near(tw:get(), 150, 1e-4, "halfway to 300 at t=0.5s")

		count:set(2)
		flush()
		advance(0.5)
		sert.near(
			tw:get(),
			300,
			1e-4,
			"completed at t=1.0s without resetting progress when getter returned same target"
		)
		expect(not Engine.isActive(twMotion), "finished tween is back at rest")
		scope:Destroy()
	end
)

test("motion · Easing resolves styles by name and rejects unknown ones", function()
	for _, style in STYLES do
		for _, direction in DIRECTIONS do
			local curve = Easing.curve(style, direction)
			near(curve(0), 0, 1e-3, `{style} {direction} starts at 0`)
			sert.near(curve(1), 1, 1e-3, `{style} {direction} ends at 1`)
			expect(Easing.get(2, style, direction) == curve(1), "get clamps alpha")
		end
	end
	expect(Easing.get(0.25, "Linear", "In") == 0.25, "Linear is the identity")
	expectError(function()
		return Easing.curve("Wobbly", "In")
	end, "Unknown EasingStyle Wobbly")
	expectError(function()
		return Easing.curve("Quad", "Sideways")
	end, "Unknown EasingDirection Sideways")
end)

rtest("motion · Easing matches TweenService:GetValue for every style and direction", function()
	local TweenService = game:GetService("TweenService")
	local failures = {}
	for _, style in Enum.EasingStyle:GetEnumItems() do
		if not pcall(TweenInfo.new, 1, style) then
			continue
		end
		for _, direction in Enum.EasingDirection:GetEnumItems() do
			local worst, at = 0, 0
			for i = 0, 100 do
				local alpha = i / 100
				local err =
					math.abs(Easing.get(alpha, style, direction) - TweenService:GetValue(alpha, style, direction))
				if not (err <= worst) then
					worst, at = err, alpha
				end
			end
			if not (worst <= 1e-6) then
				local samples = {}
				for _, alpha in { 0, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 1 } do
					table.insert(
						samples,
						string.format(
							"%g: %.9g/%.9g",
							alpha,
							TweenService:GetValue(alpha, style, direction),
							Easing.get(alpha, style, direction)
						)
					)
				end
				table.insert(
					failures,
					`{style.Name} {direction.Name}: off by {worst} at {at} (want/got {table.concat(samples, ", ")})`
				)
			end
		end
	end
	expect(#failures == 0, `{#failures} curves differ:\n{table.concat(failures, "\n")}`)
end)

local function fields(...: string): (any, any) -> boolean
	local names = { ... }
	return function(got, want)
		for _, name in names do
			if not (math.abs(got[name] - want[name]) <= 3e-3) then
				return false
			end
		end
		return true
	end
end
local nearColor = fields("R", "G", "B")

local function same(got: any, goal: any): boolean
	return got == goal
end

test("motion · a tween of every Compat datatype lands on its goal", function()
	local Color3, UDim, UDim2, Vector2, Vector3 =
		Compat.Color3, Compat.UDim, Compat.UDim2, Compat.Vector2, Compat.Vector3
	local cases: { { any } } = {
		{ "number", 0, 42, same },
		{ "Vector2", Vector2.new(-3, 7), Vector2.new(12.5, -4.25), same },
		{ "Vector3", Vector3.new(-3, 7, 1), Vector3.new(12.5, -4.25, 9), same },
		{ "UDim", UDim.new(0, 0), UDim.new(0.5, 40), same },
		{ "UDim2", UDim2.new(0, 0, 0, 0), UDim2.new(0.25, 30, 0.75, -10), same },
		{ "Color3", Color3.new(0, 0, 0), Color3.new(0.9, 0.1, 0.5), nearColor },
		{
			"Color3 (primary)",
			Color3.new(0, 0, 1),
			Color3.new(1, 0, 0),
			function(got)
				return got.G >= 0 and got.B >= 0 and nearColor(got, Color3.new(1, 0, 0))
			end,
		},
	}
	for _, case in cases do
		local name, start, goal, matches = case[1], case[2], case[3], case[4]
		local got = tweenToGoal(start, goal)
		expect(Compat.typeof(got) == Compat.typeof(goal), `{name}: unpacks to a {Compat.typeof(got)}`)
		expect(matches(got, goal), `{name}: got {tostring(got)}, want {tostring(goal)}`)
	end
end)

rtest("motion · a tween of every engine-only animatable type lands on its goal", function()
	local nearVal = function(a: number, b: number): boolean
		return math.abs(a - b) <= 3e-3
	end
	local function keypoints(compare: (any, any) -> boolean): (any, any) -> boolean
		return function(got, goal)
			if #got.Keypoints ~= #goal.Keypoints then
				return false
			end
			for i, k in goal.Keypoints do
				if not compare(got.Keypoints[i], k) then
					return false
				end
			end
			return true
		end
	end
	local numberKeypoint, range = fields("Time", "Value", "Envelope"), fields("Min", "Max")
	local function colorKeypoint(g: ColorSequenceKeypoint, k: ColorSequenceKeypoint): boolean
		return nearVal(g.Time, k.Time) and nearColor(g.Value, k.Value)
	end
	local function components(g: CFrame, k: CFrame): boolean
		local got, goal = { g:GetComponents() }, { k:GetComponents() }
		for i = 1, 12 do
			if not nearVal(got[i], goal[i]) then
				return false
			end
		end
		return true
	end

	local cases: { { any } } = {
		{ "Rect", Rect.new(0, 0, 1, 1), Rect.new(4, 8, 16, 32), same },
		{ "NumberRange", NumberRange.new(0, 1), NumberRange.new(3.5, 9.25), range },
		{ "NumberRange (Min == Max)", NumberRange.new(2, 2), NumberRange.new(5, 5), range },
		{
			"NumberSequenceKeypoint",
			NumberSequenceKeypoint.new(0, 0, 0),
			NumberSequenceKeypoint.new(0.4, 0.8, 0.1),
			numberKeypoint,
		},
		{
			"NumberSequence",
			NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0, 0),
				NumberSequenceKeypoint.new(0.5, 0.5, 0),
				NumberSequenceKeypoint.new(1, 1, 0),
			}),
			NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.25, 0.05),
				NumberSequenceKeypoint.new(0.4, 0.9, 0.1),
				NumberSequenceKeypoint.new(1, 0.1, 0.2),
			}),
			keypoints(numberKeypoint),
		},
		{
			"ColorSequenceKeypoint",
			ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
			ColorSequenceKeypoint.new(0.6, Color3.new(0.2, 0.4, 0.8)),
			colorKeypoint,
		},
		{
			"ColorSequence",
			ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 0, 0)),
				ColorSequenceKeypoint.new(0.5, Color3.new(0, 1, 0)),
				ColorSequenceKeypoint.new(1, Color3.new(0, 0, 1)),
			}),
			ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(0.2, 0.4, 0.8)),
				ColorSequenceKeypoint.new(0.25, Color3.new(0.9, 0.1, 0.5)),
				ColorSequenceKeypoint.new(1, Color3.new(0.05, 0.95, 0.35)),
			}),
			keypoints(colorKeypoint),
		},
		{ "CFrame", CFrame.new(0, 0, 0), CFrame.new(5, -2, 8) * CFrame.Angles(0, math.rad(90), 0), components },
	}
	for _, case in cases do
		local name, start, goal, matches = case[1], case[2], case[3], case[4]
		local got = tweenToGoal(start, goal)
		expect(matches(got, goal), `{name}: got {tostring(got)}, want {tostring(goal)}`)
	end
end)

-- Color ---------------------------------------------------------------------------------------------------------------

local Color = Flux.Color
local Oklab = Color.Oklab
local Color3 = Compat.Color3
local Vector3 = Compat.Vector3

local function chroma(lab): number
	return math.sqrt(lab.Y ^ 2 + lab.Z ^ 2)
end

local function hueDeg(lab): number
	return math.deg(math.atan2(lab.Z, lab.Y)) % 360
end

local function color(g: any)
	local kind = g:weighted({ { 6, "random" }, { 1, "grey" }, { 1, "corner" } })
	local c
	if kind == "grey" then
		local v = g:float(0, 1)
		c = Color3.new(v, v, v)
	elseif kind == "corner" then
		c = Color3.new(g:int(0, 1), g:int(0, 1), g:int(0, 1))
	else
		c = Color3.new(g:float(0, 1), g:float(0, 1), g:float(0, 1))
	end
	g:note("%s colour %s", kind, tostring(c))
	return c
end

local function inGamut(lab, margin: number): boolean
	local linear = Oklab.toLinear(lab, false)
	for _, channel in { linear.R, linear.G, linear.B } do
		if channel < margin or channel > 1 - margin then
			return false
		end
	end
	return true
end

prop("color · sRGB, linear and Oklab conversions round-trip", function(g)
	local c = color(g)
	near(Color.sRGB.toLinear(Color.sRGB.fromLinear(c)), c, 1e-5, "sRGB toLinear∘fromLinear")
	near(Color.sRGB.fromLinear(Color.sRGB.toLinear(c)), c, 1e-5, "sRGB fromLinear∘toLinear")
	near(Oklab.toLinear(Oklab.fromLinear(c), false), c, 1e-5, "Oklab toLinear∘fromLinear")
	local lab = Oklab.fromRGB(c)
	near(Oklab.toRGB(lab, false), c, 1e-5, "Oklab toRGB∘fromRGB")
	if c.R == c.G and c.G == c.B then
		near(chroma(lab), 0, 1e-5, "a grey sits on the achromatic axis")
	end
end, { runs = 300 })

test("color · sRGB and Oklab anchor values", function()
	local black, white = Color3.new(0, 0, 0), Color3.new(1, 1, 1)
	near(Color.sRGB.fromLinear(black), black, 1e-7, "fromLinear black")
	near(Color.sRGB.fromLinear(white), white, 1e-7, "fromLinear white")
	near(Color.sRGB.toLinear(black), black, 1e-7, "toLinear black")
	near(Color.sRGB.toLinear(white), white, 1e-7, "toLinear white")
	near(Color.sRGB.fromLinear(Color3.new(0.5, 0.5, 0.5)).R, 0.7353569830, 1e-6, "sRGB encode of 0.5")
	local labWhite, labBlack = Oklab.fromLinear(white), Oklab.fromLinear(black)
	near(labWhite, Vector3.new(1, 0, 0), 1e-4, "white is L=1")
	near(labBlack, Vector3.new(0, 0, 0), 1e-6, "black is 0")
end)

prop("color · lighten shifts L alone, clamps to [0, 1], and lighten(-a) undoes lighten(a)", function(g)
	local c = color(g)
	local amount = g:float(-1.5, 1.5)
	g:note("amount %g", amount)
	local lab = Oklab.fromRGB(c)
	local lit = Oklab.lighten(lab, amount)
	near(lit.X, math.clamp(lab.X + amount, 0, 1), 1e-6, "lighten adds to L, clamped to [0, 1]")
	near(lit.Y, lab.Y, 1e-9, "lighten keeps a")
	near(lit.Z, lab.Z, 1e-9, "lighten keeps b")

	local small = g:float(-0.2, 0.2)
	g:note("small %g", small)
	local shifted = Oklab.lighten(lab, small)
	if lab.X + small > 0 and lab.X + small < 1 and inGamut(shifted, 1e-3) then
		near(Color.lighten(Color.lighten(c, small), -small), c, 1e-5, "lighten(-a) after lighten(a)")
	end
end, { runs = 300 })

prop("color · saturate moves chroma along the hue, stopping at grey", function(g)
	local c = color(g)
	local amount = g:float(-0.5, 0.5)
	g:note("amount %g", amount)
	local lab = Oklab.fromRGB(c)
	local sat = Oklab.saturate(lab, amount)
	near(sat.X, lab.X, 1e-9, "saturate keeps L")
	local before = chroma(lab)
	if before < 1e-6 then
		near(sat.Y, lab.Y, 0, "a grey passes through (a)")
		near(sat.Z, lab.Z, 0, "a grey passes through (b)")
		return
	end
	near(chroma(sat), math.max(before + amount, 0), 1e-6, "saturate adds to chroma, bottoming out at grey")
	near(sat.Y * lab.Z, sat.Z * lab.Y, 1e-7, "saturate keeps the hue direction")
	expect(sat.Y * lab.Y >= 0 and sat.Z * lab.Z >= 0, "saturate never flips the hue")
end, { runs = 300 })

test("color · rotateHue rotates around the wheel", function()
	local lab = Oklab.fromRGB(Color3.new(0.8, 0.2, 0.2))
	local full = Oklab.rotateHue(lab, 360)
	near(full.Y, lab.Y, 1e-5, "rotateHue 360° ≈ identity (a)")
	near(full.Z, lab.Z, 1e-5, "rotateHue 360° ≈ identity (b)")
	local rot = Oklab.rotateHue(lab, 90)
	sert.near(rot.X, lab.X, 1e-9, "rotateHue preserves L")
	sert.near(chroma(rot), chroma(lab), 1e-6, "rotateHue preserves chroma")
	local dh = (hueDeg(rot) - hueDeg(lab)) % 360
	sert.near(dh, 90, 1e-3, `hue advances 90°, got {dh}`)
	local c = Color3.new(0.6, 0.3, 0.4)
	near(Color.rotateHue(c, 45), Oklab.toRGB(Oklab.rotateHue(Oklab.fromRGB(c), 45)), 1e-6, "rotateHue")
end)

prop("color · grayscale drops chroma and keeps L", function(g)
	local c = color(g)
	local lab = Oklab.fromRGB(c)
	local grey = Oklab.grayscale(lab)
	near(grey.X, lab.X, 0, "grayscale keeps L")
	near(grey.Y, 0, 0, "grayscale zeroes a")
	near(grey.Z, 0, 0, "grayscale zeroes b")
	local out = Color.grayscale(c)
	near(out.R, out.G, 1e-5, "grayscale is neutral (R = G)")
	near(out.G, out.B, 1e-5, "grayscale is neutral (G = B)")
	local back = Oklab.fromRGB(out)
	near(back.X, lab.X, 1e-5, "grayscale's Color3 keeps L")
	near(chroma(back), 0, 1e-5, "grayscale's Color3 has no chroma")
end, { runs = 300 })

prop("color · mix lands on its endpoints and follows the Oklab lerp between", function(g)
	local a, b = color(g), color(g)
	local t = g:float(0, 1)
	g:note("t %g", t)
	near(Color.mix(a, b, 0), a, 1e-5, "mix t=0 is a")
	near(Color.mix(a, b, 1), b, 1e-5, "mix t=1 is b")
	local la, lb = Oklab.fromRGB(a), Oklab.fromRGB(b)
	near(Color.mix(a, b, t), Oklab.toRGB(Oklab.mix(la, lb, t)), 1e-6, "mix is the Oklab lerp")
	near(Color.mix(a, b, t), Color.mix(b, a, 1 - t), 1e-5, "mix(a, b, t) is mix(b, a, 1 - t)")
end, { runs = 300, regressions = { 2666385905 } })

test("color · luminance and contrast follow WCAG", function()
	sert.near(Color.luminance(Color3.new(1, 1, 1)), 1, 1e-6, "white luminance is 1")
	sert.near(Color.luminance(Color3.new(0, 0, 0)), 0, 1e-6, "black luminance is 0")
	sert.near(Color.contrast(Color3.new(1, 1, 1), Color3.new(0, 0, 0)), 21, 1e-4, "white/black contrast is 21")
end)

prop("color · contrast is symmetric and between 1 and 21; readable picks the higher", function(g)
	local a, b = color(g), color(g)
	local ab, ba = Color.contrast(a, b), Color.contrast(b, a)
	near(ab, ba, 0, "contrast is symmetric")
	expect(ab >= 1 and ab <= 21 + 1e-4, `contrast is in [1, 21], got {ab}`)
	near(Color.contrast(a, a), 1, 0, "contrast with itself is 1")
	local luminance = Color.luminance(a)
	expect(luminance >= 0 and luminance <= 1, `luminance is in [0, 1], got {luminance}`)
	local pick = Color.readable(a, b, Color3.new(1, 1, 1))
	expect(Color.contrast(a, pick) >= Color.contrast(a, if pick == b then Color3.new(1, 1, 1) else b), "readable")
end, { runs = 300 })

test("color · readable picks the more legible text colour", function()
	local white = Color3.new(1, 1, 1)
	local black = Color3.new(0, 0, 0)
	expect(Color.readable(white) == black, "black text on white")
	expect(Color.readable(black) == white, "white text on black")
	local navy = Color3.new(0.05, 0.05, 0.3)
	expect(Color.readable(Color3.new(0.95, 0.95, 0.8), navy, white) == navy, "picks the higher-contrast candidate")
end)

prop("color · gamut clip lands in range, keeps hue, and leaves in-gamut colours alone", function(g)
	local lab = Vector3.new(g:float(0, 1), g:float(-0.4, 0.4), g:float(-0.4, 0.4))
	g:note("lab %s", tostring(lab))
	local clipped = Oklab.toRGB(lab, true)
	for _, channel in { clipped.R, clipped.G, clipped.B } do
		expect(channel >= -1e-6 and channel <= 1 + 1e-6, `clipped channel in range, got {clipped}`)
	end
	local back = Oklab.fromRGB(clipped)
	expect(chroma(back) <= chroma(lab) + 1e-5, "the clip only removes chroma")
	if chroma(back) > 0.02 then
		local dh = math.abs(hueDeg(lab) - hueDeg(back))
		dh = math.min(dh, 360 - dh)
		expect(dh < 0.1, `gamut clip keeps hue within 0.1°, got {dh}`)
	end
	if inGamut(lab, 1e-6) then
		near(clipped, Oklab.toRGB(lab, false), 0, "an in-gamut colour is left alone")
	end
	local pushed = Color.saturate(color(g), g:float(0, 0.5))
	for _, channel in { pushed.R, pushed.G, pushed.B } do
		expect(channel >= -1e-6 and channel <= 1 + 1e-6, `saturated channel in range, got {pushed}`)
	end
end, { runs = 300 })

sert.laws.codec("color · Oklab <-> sRGB Color3 codec laws", {
	gen = function(g)
		return Color3.fromRGB(g:int(0, 255), g:int(0, 255), g:int(0, 255))
	end,
	encode = function(c)
		return Oklab.fromRGB(c)
	end,
	decode = function(lab)
		local rgb = Oklab.toRGB(lab, false)
		return Color3.fromRGB(
			math.clamp(math.round(rgb.R * 255), 0, 255),
			math.clamp(math.round(rgb.G * 255), 0, 255),
			math.clamp(math.round(rgb.B * 255), 0, 255)
		)
	end,
	eq = function(a, b)
		return math.abs(a.R - b.R) <= 1e-5 and math.abs(a.G - b.G) <= 1e-5 and math.abs(a.B - b.B) <= 1e-5
	end,
})

sert.laws.codec("color · Oklch <-> Oklab cylindrical codec laws", {
	gen = function(g)
		return Vector3.new(g:float(0.05, 0.95), g:float(0.01, 0.35), g:float(0, 359.99))
	end,
	encode = function(lch)
		local rad = math.rad(lch.Z)
		local scale = 1e6
		return Vector3.new(
			math.round(lch.X * scale) / scale,
			math.round(lch.Y * math.cos(rad) * scale) / scale,
			math.round(lch.Y * math.sin(rad) * scale) / scale
		)
	end,
	decode = function(lab)
		return Vector3.new(lab.X, chroma(lab), hueDeg(lab))
	end,
	eq = function(a, b)
		local dh = math.abs(a.Z - b.Z)
		dh = math.min(dh, 360 - dh)
		return math.abs(a.X - b.X) <= 1e-4 and math.abs(a.Y - b.Y) <= 1e-4 and dh <= 1e-2
	end,
})

sert.laws.order("color · luminance forms a strict weak order on Color3", {
	gen = color,
	lt = function(a, b)
		return Color.luminance(a) < Color.luminance(b)
	end,
	eq = function(a, b)
		return Color.luminance(a) == Color.luminance(b)
	end,
})

sert.laws.codec("color · Color3 <-> Hex string codec laws", {
	gen = function(g)
		return Color3.fromRGB(g:int(0, 255), g:int(0, 255), g:int(0, 255))
	end,
	encode = function(c)
		return c:ToHex()
	end,
	decode = function(hex)
		return Color3.fromHex(hex)
	end,
	eq = function(a, b)
		return math.abs(a.R - b.R) <= 1e-5 and math.abs(a.G - b.G) <= 1e-5 and math.abs(a.B - b.B) <= 1e-5
	end,
})

sert.laws.codec("color · sRGB <-> Linear RGB quantized codec laws", {
	gen = function(g)
		return Color3.fromRGB(g:int(0, 255), g:int(0, 255), g:int(0, 255))
	end,
	encode = function(c)
		local lin = Color.sRGB.toLinear(c)
		local scale = 1e6
		return Color3.new(
			math.round(lin.R * scale) / scale,
			math.round(lin.G * scale) / scale,
			math.round(lin.B * scale) / scale
		)
	end,
	decode = function(lin)
		local srgb = Color.sRGB.fromLinear(lin)
		return Color3.fromRGB(
			math.clamp(math.round(srgb.R * 255), 0, 255),
			math.clamp(math.round(srgb.G * 255), 0, 255),
			math.clamp(math.round(srgb.B * 255), 0, 255)
		)
	end,
	eq = function(a, b)
		return math.abs(a.R - b.R) <= 1e-5 and math.abs(a.G - b.G) <= 1e-5 and math.abs(a.B - b.B) <= 1e-5
	end,
})

sert.laws.algebra("color · Oklab.mix midpoint (t = 0.5) commutativity and idempotence laws", {
	gen = function(g)
		return Vector3.new(g:float(0, 1), g:float(-0.3, 0.3), g:float(-0.3, 0.3))
	end,
	op = function(a, b)
		return Oklab.mix(a, b, 0.5)
	end,
	associative = false,
	commutative = true,
	idempotent = true,
	eq = function(a, b)
		return math.abs(a.X - b.X) <= 1e-6 and math.abs(a.Y - b.Y) <= 1e-6 and math.abs(a.Z - b.Z) <= 1e-6
	end,
})

local anchorLab = Oklab.fromRGB(Color3.new(0.85, 0.25, 0.35))
sert.laws.algebra("color · Oklab.rotateHue group action associativity, commutativity, identity and inverse laws", {
	gen = function(g)
		return g:float(-360, 360)
	end,
	op = function(a, b)
		return a + b
	end,
	identity = 0,
	inverse = function(a)
		return -a
	end,
	associative = true,
	commutative = true,
	idempotent = false,
	eq = function(a, b)
		local ra = Oklab.rotateHue(anchorLab, a)
		local rb = Oklab.rotateHue(anchorLab, b)
		return math.abs(ra.X - rb.X) <= 1e-6 and math.abs(ra.Y - rb.Y) <= 1e-6 and math.abs(ra.Z - rb.Z) <= 1e-6
	end,
})

sert.laws.differential("color · Color.mix and Color.contrast match analytical Oklab & WCAG 2.1 oracle", {
	gen = sert.gen.record({
		a = color,
		b = color,
		t = sert.gen.float(0, 1),
	}),
	oracle = function(input)
		local labA = Oklab.fromRGB(input.a)
		local labB = Oklab.fromRGB(input.b)
		local mixedLab = labA + (labB - labA) * input.t
		local mixedRgb = Oklab.toRGB(mixedLab, true)

		local function srgbChannelToLinear(c: number): number
			return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
		end
		local function relLum(c: Color3): number
			return 0.2126 * srgbChannelToLinear(c.R)
				+ 0.7152 * srgbChannelToLinear(c.G)
				+ 0.0722 * srgbChannelToLinear(c.B)
		end
		local l1, l2 = relLum(input.a), relLum(input.b)
		local hi, lo = math.max(l1, l2), math.min(l1, l2)
		local ratio = (hi + 0.05) / (lo + 0.05)
		return { mix = mixedRgb, contrast = ratio }
	end,
	sut = function(input)
		return {
			mix = Color.mix(input.a, input.b, input.t),
			contrast = Color.contrast(input.a, input.b),
		}
	end,
	eq = function(a, b)
		local mixClose = math.abs(a.mix.R - b.mix.R) <= 1e-5
			and math.abs(a.mix.G - b.mix.G) <= 1e-5
			and math.abs(a.mix.B - b.mix.B) <= 1e-5
		local contrastClose = math.abs(a.contrast - b.contrast) <= 1e-5
		return mixClose and contrastClose
	end,
}, { runs = 100 })

local finiteBoundary01 = sert.gen.filter(sert.gen.boundaryFloat(0, 1), function(x)
	return x == x and math.abs(x) < math.huge
end)
local finiteBoundarySigned = sert.gen.filter(sert.gen.boundaryFloat(-2, 2), function(x)
	return x == x and math.abs(x) < math.huge
end)
local finiteBoundaryDeg = sert.gen.filter(sert.gen.boundaryFloat(-720, 720), function(x)
	return x == x and math.abs(x) < math.huge
end)

prop(
	"color · boundaryFloat fuzzing across Oklab, sRGB, mix, contrast, lighten, saturate, rotateHue, grayscale upholds gamut and algebraic laws",
	function(g)
		local r1, g1, b1 = finiteBoundary01(g), finiteBoundary01(g), finiteBoundary01(g)
		local r2, g2, b2 = finiteBoundary01(g), finiteBoundary01(g), finiteBoundary01(g)
		local t = finiteBoundary01(g)
		local delta = finiteBoundarySigned(g)
		local deg = finiteBoundaryDeg(g)

		local c1 = Color3.new(math.clamp(r1, 0, 1), math.clamp(g1, 0, 1), math.clamp(b1, 0, 1))
		local c2 = Color3.new(math.clamp(r2, 0, 1), math.clamp(g2, 0, 1), math.clamp(b2, 0, 1))
		local tClamped = math.clamp(t, 0, 1)

		local function checkColor3(c: Color3, label: string)
			expect(c.R == c.R and c.G == c.G and c.B == c.B, `{label} has no NaN components`)
			expect(
				c.R >= -1e-6
					and c.R <= 1 + 1e-6
					and c.G >= -1e-6
					and c.G <= 1 + 1e-6
					and c.B >= -1e-6
					and c.B <= 1 + 1e-6,
				`{label} clamped in [0, 1]: {tostring(c)}`
			)
		end

		local function checkVec3(v: Vector3, label: string)
			expect(
				v.X == v.X
					and v.Y == v.Y
					and v.Z == v.Z
					and math.abs(v.X) < math.huge
					and math.abs(v.Y) < math.huge
					and math.abs(v.Z) < math.huge,
				`{label} is finite Vector3`
			)
		end

		local lab1 = Oklab.fromRGB(c1)
		checkVec3(lab1, "Oklab.fromRGB")
		checkColor3(Oklab.toRGB(lab1, true), "Oklab.toRGB(gamutClip=true)")
		checkColor3(Color.sRGB.toLinear(c1), "sRGB.toLinear")
		checkColor3(Color.sRGB.fromLinear(c1), "sRGB.fromLinear")
		checkColor3(Color.mix(c1, c2, tClamped), "Color.mix")
		checkColor3(Color.lighten(c1, delta), "Color.lighten")
		checkColor3(Color.saturate(c1, delta), "Color.saturate")
		checkColor3(Color.rotateHue(c1, deg), "Color.rotateHue")
		checkColor3(Color.grayscale(c1), "Color.grayscale")

		-- Algebraic mix invariants
		near(Color.mix(c1, c1, tClamped), c1, 1e-4, "mix(c, c, t) == c")
		near(Color.mix(c1, c2, 0), c1, 1e-4, "mix(a, b, 0) == a")
		near(Color.mix(c1, c2, 1), c2, 1e-4, "mix(a, b, 1) == b")
		near(Color.mix(c1, c2, tClamped), Color.mix(c2, c1, 1 - tClamped), 1e-4, "mix(a, b, t) == mix(b, a, 1 - t)")

		-- Contrast & luminance invariants
		local lum = Color.luminance(c1)
		expect(lum == lum and lum >= -1e-6 and lum <= 1 + 1e-6, `luminance in [0, 1]: {lum}`)
		local cr = Color.contrast(c1, c2)
		local crRev = Color.contrast(c2, c1)
		near(cr, crRev, 1e-6, "contrast(a, b) == contrast(b, a)")
		expect(cr == cr and cr >= 1 - 1e-5 and cr <= 21 + 1e-4, `contrast in [1, 21]: {cr}`)
		near(Color.contrast(c1, c1), 1, 1e-6, "contrast(c, c) == 1")
		local rd = Color.readable(c1)
		checkColor3(rd, "Color.readable")

		-- Hue rotation round-trip for chromatic colors
		near(Oklab.rotateHue(Oklab.rotateHue(lab1, deg), -deg), lab1, 1e-4, "Oklab.rotateHue round-trip")
		if chroma(lab1) > 1e-3 and inGamut(Oklab.rotateHue(lab1, deg), 1e-3) then
			near(
				Color.rotateHue(Color.rotateHue(c1, deg), -deg),
				c1,
				1e-4,
				"rotateHue(rotateHue(c, deg), -deg) == c for in-gamut chromatic color"
			)
		end

		-- Luminance & Oklab lightness monotonicity for lighten / darken
		local absDelta = math.abs(delta)
		local lighter = Color.lighten(c1, absDelta)
		local darker = Color.lighten(c1, -absDelta)
		expect(
			Oklab.fromRGB(darker).X <= lab1.X + 1e-4 and Oklab.fromRGB(lighter).X >= lab1.X - 1e-4,
			"Oklab lightness monotonicity for lighten/darken"
		)
		expect(
			Color.luminance(darker) <= lum + 2e-3 and Color.luminance(lighter) >= lum - 2e-3,
			"luminance monotonicity for lighten/darken"
		)
	end,
	{ runs = 120 }
)

sert.laws.differential(
	"motion · spring step matches closed-form damped harmonic oscillator ODE across damping regimes",
	{
		gen = sert.gen.record({
			target = sert.gen.float(-50, 50),
			freq = sert.gen.float(1, 12),
			damping = sert.gen.oneOf({
				sert.gen.float(0.15, 0.95),
				sert.gen.constant(1.0),
				sert.gen.float(1.05, 3.0),
			}),
			dt = sert.gen.float(1 / 240, 1 / 30),
			steps = sert.gen.int(1, 8),
		}),
		oracle = function(cfg: any)
			local p: number = 0
			local v: number = 0
			local target: number = cfg.target
			local w: number = 2 * math.pi * cfg.freq
			local d: number = cfg.damping
			local dt: number = cfg.dt
			for _ = 1, cfg.steps do
				local x0 = p - target
				if d < 1 then
					local wd = w * math.sqrt(1 - d * d)
					local exp = math.exp(-d * w * dt)
					local c = math.cos(wd * dt)
					local s = math.sin(wd * dt)
					local c2 = (v + d * w * x0) / wd
					p = target + exp * (x0 * c + c2 * s)
					v = exp * ((c2 * wd - d * w * x0) * c - (x0 * wd + d * w * c2) * s)
				elseif d == 1 then
					local exp = math.exp(-w * dt)
					local c2 = v + w * x0
					p = target + exp * (x0 + c2 * dt)
					v = exp * (c2 - w * (x0 + c2 * dt))
				else
					local s = math.sqrt(d * d - 1)
					local r1 = -w * (d - s)
					local r2 = -w * (d + s)
					local e1 = math.exp(r1 * dt)
					local e2 = math.exp(r2 * dt)
					local c2 = (v - r1 * x0) / (r2 - r1)
					local c1 = x0 - c2
					p = target + c1 * e1 + c2 * e2
					v = c1 * r1 * e1 + c2 * r2 * e2
				end
				if math.abs(p - target) < 1e-4 and math.abs(v) < 1e-4 then
					p = target
					v = 0
				end
			end
			return p
		end,
		sut = function(cfg)
			local s = Flux.spring(0, cfg.freq, cfg.damping)
			s:set(cfg.target)
			for _ = 1, cfg.steps do
				Flux.Motion.step(cfg.dt)
			end
			local out = s:peek()
			s:Destroy()
			Flux.flush()
			return out
		end,
		eq = function(a, b)
			return math.abs(a - b) <= 1e-4
		end,
	},
	{ runs = 80 }
)

sert.laws.differential(
	"motion · tween step progression across EasingStyle, EasingDirection, repeatCount, reverses, and delayTime matches analytical time-folding oracle",
	{
		gen = sert.gen.record({
			startVal = sert.gen.float(-100, 100),
			endVal = sert.gen.float(-100, 100),
			duration = sert.gen.float(0.1, 1.5),
			style = sert.gen.pick(STYLES),
			direction = sert.gen.pick(DIRECTIONS),
			repeatCount = sert.gen.pick({ -1, 0, 1, 2, 3 }),
			reverses = sert.gen.bool(),
			delayTime = sert.gen.oneOf({ sert.gen.constant(0), sert.gen.float(0.05, 0.5) }),
			steps = sert.gen.list(sert.gen.float(0.02, 0.4), 1, 6),
		}),
		oracle = function(cfg: any)
			local ease = Easing.curve(cfg.style, cfg.direction)
			local now = 0
			local startTime = cfg.delayTime
			local repeatsLeft = cfg.repeatCount
			local reversing = false
			local duration = cfg.duration
			local cur = cfg.startVal
			local active = true
			for _, dt in cfg.steps do
				now += dt
				if active and now >= startTime then
					local elapsed = now - startTime
					local alpha = if duration > 0 then elapsed / duration else 1
					while alpha >= 1 do
						if cfg.reverses and not reversing then
							reversing = true
						elseif repeatsLeft ~= 0 then
							if repeatsLeft > 0 then
								repeatsLeft -= 1
							end
							reversing = false
						else
							active = false
							cur = if reversing then cfg.startVal else cfg.endVal
							break
						end
						startTime += duration
						alpha = (now - startTime) / duration
					end
					if active then
						local eased = ease(math.clamp(alpha, 0, 1))
						if reversing then
							eased = 1 - eased
						end
						cur = cfg.startVal + (cfg.endVal - cfg.startVal) * eased
					end
				end
			end
			return cur
		end,
		sut = function(cfg: any)
			local tweenInfo = info(cfg.duration, cfg.style, cfg.direction, cfg.repeatCount, cfg.reverses, cfg.delayTime)
			local tw = Flux.tween(cfg.startVal, tweenInfo)
			tw:set(cfg.endVal)
			local motion = Motion.NodeToMotion[tw]
			motion.startTime = Engine.now + cfg.delayTime
			for _, dt in cfg.steps do
				Flux.Motion.step(dt)
			end
			local out = tw:peek()
			tw:Destroy()
			Flux.flush()
			return out
		end,
		eq = function(a, b)
			return math.abs(a - b) <= 1e-4
		end,
	},
	{ runs = 100 }
)

local finiteMotionFloat = sert.gen.filter(sert.gen.boundaryFloat(-1e3, 1e3), function(x)
	return x == x and math.abs(x) <= 1e3
end)

local function springMechEnergy(motion: any): number
	local w = math.tau * motion.frequency
	local x = motion.value[1] - motion.target[1]
	local v = motion.vel[1]
	return 0.5 * v * v + 0.5 * w * w * x * x
end

local function syncSpringState(state: any, sut: any, unforcedFromRest: boolean)
	local overPos = sut.over:peek()
	local goal = sut.overMotion.target[1]
	state.goal = goal
	state.unforcedFromRest = unforcedFromRest
	state.initialSign = math.sign(overPos - goal)
	state.prevOverDist = math.abs(overPos - goal)
	local e = springMechEnergy(sut.underMotion)
	state.prevUnderEnergy = e
	state.lastPeakEnergy = e
end

local function observeSpringStep(state: any, sut: any)
	if state.unforcedFromRest then
		local cur = sut.over:peek()
		local dist = math.abs(cur - state.goal)
		local signed = (cur - state.goal) * state.initialSign
		if signed < -1e-6 then
			state.overshotFromRest = true
		end
		if dist > state.prevOverDist + 1e-5 then
			state.nonMonotonicFromRest = true
		end
		state.prevOverDist = dist
	end
	local newE = springMechEnergy(sut.underMotion)
	if newE > state.prevUnderEnergy * (1 + 1e-6) + 1e-7 then
		state.energyIncreased = true
	end
	state.prevUnderEnergy = newE
end

sert.model("motion · physical spring state machine across boundaryFloat goals, impulses, and damping regimes", {
	init = function()
		local over, under
		local scope = Flux.scope(function()
			over = Flux.spring(0, 4, 1.25)
			under = Flux.spring(0, 4, 0.3)
		end)
		local sut = {
			scope = scope,
			over = over,
			under = under,
			overMotion = Motion.NodeToMotion[over],
			underMotion = Motion.NodeToMotion[under],
		}
		local state = {
			goal = 0,
			unforcedFromRest = true,
			initialSign = 0,
			prevOverDist = 0,
			overshotFromRest = false,
			nonMonotonicFromRest = false,
			prevUnderEnergy = 0,
			lastPeakEnergy = 0,
			energyIncreased = false,
		}
		syncSpringState(state, sut, true)
		return state, sut
	end,
	teardown = function(sut)
		sut.scope:Destroy()
		Flux.flush()
	end,
	actions = {
		SetGoal = {
			weight = 3,
			gen = finiteMotionFloat,
			run = function(sut, goal, state)
				local atRest = sut.overMotion.vel[1] == 0
				sut.over:set(goal)
				sut.under:set(goal)
				syncSpringState(state, sut, atRest)
			end,
		},
		Impulse = {
			weight = 2,
			gen = finiteMotionFloat,
			run = function(sut, delta, state)
				sut.over:impulse(delta)
				sut.under:impulse(delta)
				syncSpringState(state, sut, false)
			end,
		},
		SetVelocity = {
			weight = 2,
			gen = finiteMotionFloat,
			run = function(sut, vel, state)
				sut.over:setVelocity(vel)
				sut.under:setVelocity(vel)
				syncSpringState(state, sut, vel == 0)
			end,
		},
		SetPosition = {
			weight = 2,
			gen = finiteMotionFloat,
			run = function(sut, pos, state)
				local atRest = sut.overMotion.vel[1] == 0 and sut.underMotion.vel[1] == 0
				sut.over:setCurrent(pos)
				sut.under:setCurrent(pos)
				syncSpringState(state, sut, atRest)
			end,
		},
		Snap = {
			weight = 2,
			gen = finiteMotionFloat,
			run = function(sut, val, state)
				sut.over:snap(val)
				sut.under:snap(val)
				syncSpringState(state, sut, true)
			end,
		},
		StepFrame = {
			weight = 4,
			gen = function(g)
				return g:float(1 / 240, 1 / 15)
			end,
			run = function(sut, dt, state)
				advance(dt)
				observeSpringStep(state, sut)
			end,
		},
		StepUntilSettled = {
			weight = 2,
			run = function(sut, _arg, state)
				local f = sut.underMotion.frequency
				local d = sut.underMotion.damping
				local halfPeriod = math.pi / (math.tau * f * math.sqrt(1 - d * d))
				for _ = 1, 3 do
					local wasActive = Engine.isActive(sut.underMotion)
					local prevPeak = state.lastPeakEnergy
					advance(halfPeriod)
					observeSpringStep(state, sut)
					local curE = springMechEnergy(sut.underMotion)
					if wasActive and prevPeak > 1e-4 and curE >= prevPeak then
						state.energyIncreased = true
					end
					state.lastPeakEnergy = curE
				end
				advance(30)
				advance(1 / 60)
				observeSpringStep(state, sut)
				syncSpringState(state, sut, true)
			end,
		},
	},
	never = {
		criticallyOrOverdampedOvershotFromRest = function(state)
			return state.overshotFromRest
		end,
		criticallyOrOverdampedMovedAwayFromRest = function(state)
			return state.nonMonotonicFromRest
		end,
		underdampedMechanicalEnergyIncreased = function(state)
			return state.energyIncreased
		end,
	},
	invariants = {
		valuesAndVelocitiesAreFinite = function(_state: any, sut: any)
			local op: number, up: number = sut.over:peek(), sut.under:peek()
			local ov: number, uv: number = sut.overMotion.vel[1], sut.underMotion.vel[1]
			expect(op == op and math.abs(op) < math.huge, `overdamped position finite: {op}`)
			expect(up == up and math.abs(up) < math.huge, `underdamped position finite: {up}`)
			expect(ov == ov and math.abs(ov) < math.huge, `overdamped velocity finite: {ov}`)
			expect(uv == uv and math.abs(uv) < math.huge, `underdamped velocity finite: {uv}`)
		end,
		settledSpringsMatchGoalWithZeroVelocity = function(state, sut)
			if not Engine.isActive(sut.overMotion) then
				sert.eq(sut.over:peek(), state.goal, "inactive overdamped spring peek == goal")
				sert.eq(sut.overMotion.vel[1], 0, "inactive overdamped spring velocity == 0")
			end
			if not Engine.isActive(sut.underMotion) then
				sert.eq(sut.under:peek(), state.goal, "inactive underdamped spring peek == goal")
				sert.eq(sut.underMotion.vel[1], 0, "inactive underdamped spring velocity == 0")
			end
		end,
	},
}, {
	runs = 100,
	length = 16,
})

test(
	"motion · static target with reactive config preserves imperative set, nil fallback methods, and sequence overshoot clamping",
	function()
		local freq = Flux.signal(4)
		local spr = Flux.spring(0, freq)
		spr:set(100)
		freq:set(8)
		Flux.flush()
		Flux.Motion.step(0.1)
		expect(
			spr:peek() > 0,
			"reactive frequency update does not overwrite imperative :set(100) with initial static 0"
		)
		spr:Destroy()

		local tweenCfg = Flux.signal(info(1, "Linear", "Out"))
		local tw = Flux.tween(0, tweenCfg)
		tw:set(100)
		tweenCfg:set(info(0.5, "Linear", "Out"))
		Flux.flush()
		Flux.Motion.step(0.25)
		expect(tw:peek() > 0, "reactive TweenInfo update does not overwrite imperative :set(100) with initial static 0")
		tw:Destroy()

		local nilSpr: any
		env.Compat.setWarnHook(function() end)
		nilSpr = Flux.spring(nil)
		nilSpr:snap(42)
		expect(nilSpr:peek() == 42, "nil-fallback spring supports :snap()")
		nilSpr:setCurrent(7)
		expect(nilSpr:peek() == 7, "nil-fallback spring supports :setCurrent()")
		nilSpr:impulse(1)
		nilSpr:setVelocity(1)
		env.Compat.setWarnHook(nil)
		nilSpr:Destroy()

		local seqSpring = Flux.spring(
			Compat.NumberSequence.new({
				Compat.NumberSequenceKeypoint.new(0, 0, 0),
				Compat.NumberSequenceKeypoint.new(0.1, 0, 0),
				Compat.NumberSequenceKeypoint.new(1, 0, 0),
			}),
			4,
			0.1
		)
		seqSpring:set(Compat.NumberSequence.new({
			Compat.NumberSequenceKeypoint.new(0, 1, 0),
			Compat.NumberSequenceKeypoint.new(0.9, 1, 0),
			Compat.NumberSequenceKeypoint.new(1, 1, 0),
		}))
		for _ = 1, 30 do
			Flux.Motion.step(1 / 60)
		end
		expect(
			Compat.typeof(seqSpring:peek()) == "NumberSequence",
			"underdamped NumberSequence spring clamps keypoint times and envelopes"
		)
		seqSpring:Destroy()

		local outOfGamut = Flux.Color.Oklab.fromLinear(Compat.Color3.new(-1, 2, -0.5))
		expect(
			outOfGamut.X == outOfGamut.X and outOfGamut.Y == outOfGamut.Y and outOfGamut.Z == outOfGamut.Z,
			"Oklab.fromLinear handles negative channels without NaN"
		)
	end
)

rtest(
	"motion · CFrame rotation-vector packing preserves straight translation and smooth axis interpolation",
	function()
		local cfSpring = Flux.spring(CFrame.new(0, 0, 0), 4, 1)
		cfSpring:impulse(CFrame.new(10, 0, 0))
		Flux.Motion.step(1 / 60)
		local _, angle = cfSpring:peek():ToAxisAngle()
		expect(
			math.abs(angle) < 1e-5,
			`pure translation impulse on identity CFrame does not inject Y rotation: {angle}`
		)
		cfSpring:Destroy()
	end
)

return {}
