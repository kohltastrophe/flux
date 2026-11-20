--!strict
-- Bare-Luau compatibility smoke suite (runs directly under `luau` without sert mocks).

assert(
	game == nil
		and workspace == nil
		and Instance == nil
		and Enum == nil
		and Color3 == nil
		and Vector3 == nil
		and UDim == nil
		and UDim2 == nil
		and TweenInfo == nil
		and task == nil,
	"standalone smoke suite must run with zero Roblox globals"
)

local Flux = require("../src")

local function expectError(fn: () -> (), pattern: string, label: string)
	local ok, err = pcall(fn)
	assert(not ok and string.find(tostring(err), pattern, 1, true) ~= nil, `{label}: got {err}`)
end
local function callWith(fn: any, ...: any): () -> ()
	local args = { ... }
	return function()
		fn(table.unpack(args))
	end
end
local function ret(v: any)
	return function()
		return v
	end
end

-- Clock defaults to manual outside Roblox and supports opting into live mode.
local Clock, trace, waited = Flux.Clock, {}, false
assert(Clock.isManual() == true and type(Clock.now()) == "number" and type(Clock.wall()) == "number")
local disconnectHb = Clock.connect("Heartbeat", function(dt)
	table.insert(trace, `hb:{dt}`)
end)
Clock.delay(0.1, function()
	table.insert(trace, "delay")
end)
Clock.defer(function()
	table.insert(trace, "defer")
end)
coroutine.resume(coroutine.create(function()
	Clock.wait(0.05)
	waited = true
end))
Clock.drain()
Clock.step(0.1, 0.05)
assert(trace[1] == "defer" and waited and table.find(trace, "delay") ~= nil and table.find(trace, "hb:0.05") ~= nil)
disconnectHb()
Clock.reset()

Clock.manual(false)
local deferRanSync = false
Clock.defer(function()
	deferRanSync = true
end)
assert(not Clock.isManual() and deferRanSync and type(Clock.now()) == "number" and type(Clock.wall()) == "number")
expectError(callWith(Clock.connect, "Heartbeat", function() end), "requires Roblox RunService", "live connect")
expectError(callWith(Clock.delay, 0.01, function() end), "requires a task scheduler", "live delay")
expectError(callWith(Clock.wait, 0.01), "requires a task scheduler", "live wait")
Clock.manual(true)

-- Core reactive graph, stores, control flow, and async.
local cleanupScope = Flux.scope(function()
	local count, seen = Flux.signal(1), 0
	local doubled = Flux.computed(function()
		return count() * 2
	end)
	Flux.effect(function()
		seen = doubled()
	end)
	Flux.flush()
	assert(seen == 2)
	count(3)
	count(4)
	Flux.flush()
	assert(seen == 8 and doubled() == 8)

	local ctx = Flux.context("fallback")
	assert(ctx:get() == "fallback" and ctx:provide("scoped", function()
		return ctx:get()
	end) == "scoped")
	assert(Flux.safe(function(): string
		return error("boom")
	end, ret("off"))() == "off")

	local st = Flux.store({ items = { "a", "b" }, nested = { n = 10 } })
	local sum = Flux.computed(function()
		return st.nested.n + #st.items
	end)
	st.nested.n = 20
	assert(sum() == 22)

	local flag, arr = Flux.signal(true), Flux.signal({ "x", "y" })
	local shown = Flux.show(flag, ret("on"), ret("off"))
	local picked = Flux.switch(flag :: any)({ [true] = ret("ok") })
	local vals = Flux.forValue(arr, function(_i, v)
		return string.upper(v)
	end)
	local idxs = Flux.forIndex(arr, function(i, v)
		return `{i}={v}`
	end)
	local keys = Flux.forKey(arr, function(v)
		return v
	end, function(i, v)
		return `{v}:{i}`
	end)
	local sel = Flux.selector(Flux.signal("x"))
	Flux.flush()
	assert(
		shown() == "on"
			and picked() == "ok"
			and vals()[2] == "Y"
			and idxs()[2] == "2=y"
			and keys()[1] == "x:1"
			and sel("x")
	)
	flag(false)
	Flux.flush()
	local res = Flux.async(ret("ok"))
	Flux.flush()
	assert(shown() == "off" and picked() == nil and res.data() == "ok" and res.state() == "ready" and not res.loading())
end)
cleanupScope:Destroy()

-- Pure-Luau motion, Oklab vectors, and Responsive defaults.
local motionScope = Flux.scope(function()
	local nSpring = Flux.spring(0, 4, 1)
	nSpring(10)
	local vTween = Flux.tween(vector.create(0, 0, 0), { Time = 0.2, EasingStyle = "Linear" })
	vTween(vector.create(10, 20, 30))
	Clock.step(0.1)
	assert(nSpring() > 0 and vTween().x > 0 and vTween().x < 10)
	Clock.step(2)
	assert(math.abs(nSpring() - 10) < 1e-2 and math.abs(vTween().y - 20) < 1e-4)
end)
motionScope:Destroy()

local Oklab, lab: any = Flux.Color.Oklab, vector.create(0.5, 0.1, -0.05)
local lighter = Oklab.lighten(lab, 0.2)
assert(lighter.X > 0.69 and Oklab.saturate(lab, 0.1).Y ~= lab.Y and Oklab.rotateHue(lab, 90).Z ~= lab.Z)
assert(Oklab.grayscale(lab).Y == 0 and math.abs(Oklab.mix(lab, lighter, 0.5).X - 0.6) < 1e-5)
assert(Flux.Responsive.viewport:get().X == 1920 and Flux.Responsive.scale:get() == 1)
assert(Flux.Responsive.breakpoint:get() == "desktop" and type(Flux.Responsive.platform:get()) == "string")

-- Roblox-only boundaries fail fast outside Roblox.
expectError(function()
	Flux.new("Frame")({})
end, "requires a Roblox environment", "Flux.new")
expectError(function()
	Flux.edit({} :: any)({})
end, "requires a Roblox environment", "Flux.edit")
expectError(function()
	local _ = Flux.Sync.server
end, "Flux.Sync needs Roblox", "Flux.Sync.server")
expectError(function()
	local _ = Flux.Sync.client
end, "Flux.Sync needs Roblox", "Flux.Sync.client")
for _, name in
	string.split(
		"padding,corner,stroke,aspectRatio,list,grid,flex,scale,gradient,sizeConstraint,textSizeConstraint",
		","
	)
do
	expectError(callWith((Flux :: any)[name]), "requires a Roblox environment", `Flux.{name}`)
end
for _, name in string.split("pointIn,sunk,covered,hover,press,selected,focused", ",") do
	expectError(callWith((Flux.Interact :: any)[name]), "requires a Roblox environment", `Flux.Interact.{name}`)
end
local fakeColor: any = vector.create(0.5, 0.5, 0.5)
for _, name in string.split("luminance,readable,contrast", ",") do
	expectError(callWith((Flux.Color :: any)[name], fakeColor, fakeColor), "Flux.Color requires Roblox Color3", name)
end
expectError(callWith(Flux.Color.lighten, fakeColor, 0.1), "Flux.Color requires Roblox Color3", "Color.lighten")
for _, name in string.split("fromLinear,toLinear", ",") do
	expectError(callWith((Flux.Color.sRGB :: any)[name], fakeColor), "Flux.Color requires Roblox Color3", `sRGB.{name}`)
	expectError(callWith((Oklab :: any)[name], lab), "Flux.Color requires Roblox Color3", `Oklab.{name}`)
end
expectError(callWith(Oklab.fromRGB, fakeColor), "Flux.Color requires Roblox Color3", "Oklab.fromRGB")
expectError(callWith(Oklab.toRGB, lab), "Flux.Color requires Roblox Color3", "Oklab.toRGB")
print("standalone ok")
