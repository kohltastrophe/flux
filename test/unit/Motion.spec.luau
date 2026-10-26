--!nonstrict
local env = if game
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Model = if game
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("Model")) :: any
	else require("../lib/Model") :: any
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
local float = Model.float
local advance = Flux.Motion.step

local function damping(g: any): number
	local branch = g:pick({ "critical", "under", "over" })
	return if branch == "critical" then 1 elseif branch == "under" then float(g, 0.05, 0.98) else float(g, 1.02, 3)
end

local function away(g: any, start: number): number
	local gap = float(g, 100, 1000)
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

local function walk(g: any, check: () -> ())
	for _ = 1, g:int(1, g.size) do
		advance(float(g, 0, 0.1))
		check()
	end
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
	local frequency, ratio = float(g, 0.2, 3), damping(g)
	local start = float(g, -1000, 1000)
	local goal, velocity = away(g, start), float(g, -2000, 2000)
	local a, b = float(g, 0, 0.25), float(g, 0, 0.25)
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

prop("motion · from rest, damping >= 1 never crosses the target and damping < 1 does", function(g)
	local frequency, ratio = float(g, 0.2, 5), damping(g)
	local start = float(g, -1000, 1000)
	local goal = away(g, start)
	local side = if start > goal then 1 else -1
	g:note("frequency %g damping %g start %g goal %g", frequency, ratio, start, goal)
	local scope, spring = springs(1, start, frequency, ratio)
	spring(goal)
	if ratio >= 1 then
		local gap = math.abs(start - goal)
		walk(g, function()
			local now = (spring:get() - goal) * side
			expect(now >= -1e-9, `crossed the target: {spring:get()}`)
			expect(now <= gap + 1e-9, `moved away from the target: gap {gap} -> {now}`)
			gap = now
		end)
	else
		advance(math.pi / (math.tau * frequency * math.sqrt(1 - ratio * ratio)))
		expect((spring:get() - goal) * side < 0, `did not overshoot: {spring:get()}`)
	end
	scope:Destroy()
end, { runs = 200 })

prop("motion · a spring settles exactly on its target and leaves the stepped set", function(g)
	local frequency, ratio = float(g, 1, 8), damping(g)
	if ratio < 1 then
		ratio = math.max(ratio, 0.2)
	end
	local start = float(g, -1000, 1000)
	local goal, velocity = away(g, start), float(g, -2000, 2000)
	g:note("frequency %g damping %g start %g goal %g velocity %g", frequency, ratio, start, goal, velocity)
	local scope, spring = springs(1, start, frequency, ratio)
	spring(goal)
	spring:setVelocity(velocity)
	local motion = Motion.NodeToMotion[spring]
	for _ = 1, 4000 do
		if not Engine.isActive(motion) then
			break
		end
		advance(float(g, 1 / 240, 1 / 30))
	end
	expect(not Engine.isActive(motion), `still moving at {spring:get()}`)
	expect(spring:get() == goal, `settled at {spring:get()}, not exactly {goal}`)
	advance(1)
	expect(spring:get() == goal, "a settled spring stays put")
	scope:Destroy()
end, { runs = 100 })

prop("motion · a vector spring moves exactly like three number springs", function(g)
	local frequency, ratio = float(g, 0.2, 5), damping(g)
	local start, goal, velocity = {}, {}, {}
	for i = 1, 3 do
		start[i] = float(g, -1000, 1000)
		goal[i] = if g:bool(0.2) then start[i] else away(g, start[i])
		velocity[i] = float(g, -2000, 2000)
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
	walk(g, function()
		local v = vec:get()
		for i, component in { v.x, v.y, v.z } do
			local want = numbers[i]:get()
			local close = math.abs(component - want) <= 2e-4 + 1e-6 * math.abs(want)
			expect(close, `component {i}: vector {component}, number {want}`)
		end
	end)
	scope:Destroy()
end, { runs = 100 })

prop("motion · impulses add: a run of impulses moves a spring like one impulse of their sum", function(g)
	local frequency, ratio = float(g, 0.2, 5), damping(g)
	local rest = float(g, -1000, 1000)
	local kicks = g:list(function()
		return float(g, -2000, 2000)
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
	walk(g, function()
		expect(many:get() == one:get(), `impulses {table.concat(kicks, ", ")}: {many:get()} vs {one:get()}`)
	end)
	scope:Destroy()
end, { runs = 200 })

prop("motion · setVelocity replaces every earlier impulse", function(g)
	local frequency, ratio = float(g, 0.2, 5), damping(g)
	local start = float(g, -1000, 1000)
	local goal = if g:bool() then start else away(g, start)
	local velocity = g:weighted({ { 1, 0 }, { 2, float(g, -2000, 2000) } })
	local kicks = g:list(function()
		return float(g, -2000, 2000)
	end, 1, 5)
	local scope, kicked, clean = springs(2, start, frequency, ratio)
	kicked(goal)
	clean(goal)
	for _, kick in kicks do
		kicked:impulse(kick)
	end
	kicked:setVelocity(velocity)
	clean:setVelocity(velocity)
	walk(g, function()
		expect(kicked:get() == clean:get(), `velocity {velocity}: {kicked:get()} vs {clean:get()}`)
	end)
	scope:Destroy()
end, { runs = 200 })

prop("motion · a tween follows its eased curve across repeats and reverses and ends exactly", function(g)
	local style, direction = g:pick(STYLES), g:pick(DIRECTIONS)
	local repeats = g:weighted({ { 3, 0 }, { 2, 1 }, { 2, 2 }, { 1, 3 }, { 1, -1 } })
	local reverses = g:bool()
	local tweenInfo = info(float(g, 0.05, 2), style, direction, repeats, reverses)
	local time = tweenInfo.Time
	local start = float(g, -1000, 1000)
	local goal = away(g, start)
	g:note(
		"time %g %s %s repeats %d reverses %s start %g goal %g",
		time,
		style,
		direction,
		repeats,
		tostring(reverses),
		start,
		goal
	)
	local scope, tween = Flux.scope(function()
		return Flux.tween(start, tweenInfo)
	end)
	tween(goal)
	local motion = Motion.NodeToMotion[tween]
	local ease = Easing.curve(style, direction)
	local cycle = if reverses then 2 * time else time
	local total = if repeats < 0 then math.huge else cycle * (repeats + 1)

	local elapsed = 0
	for _ = 1, g.size do
		local dt = float(g, 0, 1.5 * time)
		advance(dt)
		elapsed += dt
		g:note("elapsed %g", elapsed)
		local into = elapsed % cycle
		local legAt = into % time
		local onEdge = math.min(legAt, time - legAt) < 1e-6 or math.abs(elapsed - total) < 1e-6
		if elapsed > total and not onEdge then
			expect(tween:get() == (if reverses then start else goal), `ended at {tween:get()}`)
			expect(not Engine.isActive(motion), "a finished tween leaves the stepped set")
			break
		elseif not onEdge then
			local alpha = if into < time then ease(into / time) else 1 - ease((into - time) / time)
			local want = start + (goal - start) * alpha
			expect(
				math.abs(tween:get() - want) <= 1e-6 * (1 + math.abs(want)),
				`at {elapsed}: {tween:get()}, want {want}`
			)
		end
	end
	scope:Destroy()
end, { runs = 200 })

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
		local v = float(g, 0, 1)
		c = Color3.new(v, v, v)
	elseif kind == "corner" then
		c = Color3.new(g:int(0, 1), g:int(0, 1), g:int(0, 1))
	else
		c = Color3.new(float(g, 0, 1), float(g, 0, 1), float(g, 0, 1))
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
	local amount = float(g, -1.5, 1.5)
	g:note("amount %g", amount)
	local lab = Oklab.fromRGB(c)
	local lit = Oklab.lighten(lab, amount)
	near(lit.X, math.clamp(lab.X + amount, 0, 1), 1e-6, "lighten adds to L, clamped to [0, 1]")
	near(lit.Y, lab.Y, 1e-9, "lighten keeps a")
	near(lit.Z, lab.Z, 1e-9, "lighten keeps b")

	local small = float(g, -0.2, 0.2)
	g:note("small %g", small)
	local shifted = Oklab.lighten(lab, small)
	if lab.X + small > 0 and lab.X + small < 1 and inGamut(shifted, 1e-3) then
		near(Color.lighten(Color.lighten(c, small), -small), c, 1e-5, "lighten(-a) after lighten(a)")
	end
end, { runs = 300 })

prop("color · saturate moves chroma along the hue, stopping at grey", function(g)
	local c = color(g)
	local amount = float(g, -0.5, 0.5)
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
	local t = float(g, 0, 1)
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
	local lab = Vector3.new(float(g, 0, 1), float(g, -0.4, 0.4), float(g, -0.4, 0.4))
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
	local pushed = Color.saturate(color(g), float(g, 0, 0.5))
	for _, channel in { pushed.R, pushed.G, pushed.B } do
		expect(channel >= -1e-6 and channel <= 1 + 1e-6, `saturated channel in range, got {pushed}`)
	end
end, { runs = 300 })

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
