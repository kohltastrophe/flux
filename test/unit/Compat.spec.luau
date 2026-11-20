--!nonstrict
local env = if game ~= nil
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Compat, Flux, sert = env.Compat, env.Flux, env.sert

local test = sert.test
local expect = sert
local Clock = Flux.Clock

test("compat · no synthetic datatype fallbacks are shipped", function()
	expect.eq((Compat :: any)._fallbacks, nil, "Compat._fallbacks must not exist")
	expect.eq((Compat :: any)._setEnv, nil, "Compat._setEnv must not exist")
	expect.eq(Compat.isRoblox, game ~= nil, "Compat.isRoblox matches game presence")
end)

test("compat · typeof and getService delegate to the active environment", function()
	expect.eq(Compat.typeof(42), "number")
	expect.eq(Compat.typeof("flux"), "string")
	expect.eq(Compat.typeof(nil), "nil")
	expect.eq(Compat.typeof({}), "table")
	expect.eq(Compat.typeof(Compat.Color3.new()), "Color3")
	expect.eq(Compat.typeof(Compat.UDim.new()), "UDim")
	expect.eq(Compat.typeof(Compat.Vector2.new()), "Vector2")
	expect.eq(Compat.typeof(Compat.Vector3.new()), "Vector3")
	expect.eq(Compat.typeof(Compat.TweenInfo.new()), "TweenInfo")
	expect.eq(Compat.typeof(Compat.Enum.EasingStyle.Quad), "EnumItem")

	expect(Compat.getService("RunService") ~= nil, "getService resolves RunService")
	expect(Compat.getService("Players") ~= nil, "getService resolves Players")
	expect.eq(
		Compat.getService("RunService"),
		Compat.services.RunService,
		"getService shares cache with Compat.services"
	)
	if game == nil then
		expect.eq(
			Compat.getService("NonExistentService"),
			nil,
			"headless getService returns nil for unmounted services"
		)
	end
end)

test("compat · task delegates to Clock and warn/traceback preserve custom values", function()
	local seen = {}
	Compat.setWarnHook(function(message)
		table.insert(seen, message)
	end)
	Compat.warn("alpha", 123, true)
	Compat.setWarnHook(nil)
	expect.eq(#seen, 1)
	expect.eq(seen[1], "alpha 123 true")

	local customErr = { code = "E_TEST" }
	expect.eq(Compat.traceback(customErr, 1), customErr, "non-string errors pass through unchanged")
	local formatted = Compat.traceback("boom", 1)
	expect(type(formatted) == "string" and string.find(formatted, "boom", 1, true) ~= nil, "string errors keep message")

	local wasManual = Clock.isManual()
	Clock.manual(true)
	Clock.reset()
	local ran = false
	Compat.task.delay(0.05, function()
		ran = true
	end)
	Clock.step(0.05)
	expect.eq(ran, true, "Compat.task.delay schedules onto Clock")
	Clock.reset()
	if not wasManual then
		Clock.manual(false)
	end
end)

test("compat · requireRoblox and robloxStubs enforce Roblox boundaries", function()
	-- When Compat.Instance is present, requireRoblox returns cleanly
	Compat.requireRoblox("Flux.test")

	if game == nil then
		local prevInstance = Compat.Instance
		Compat.Instance = nil
		local ok, err = pcall(function()
			Compat.requireRoblox("Flux.test")
		end)
		Compat.Instance = prevInstance
		expect(not ok, "requireRoblox throws when Compat.Instance is nil")
		expect(
			string.find(tostring(err), "Flux.test requires a Roblox environment", 1, true) ~= nil,
			"requireRoblox throws clear error message"
		)
	end

	local stubs = Compat.robloxStubs("Flux.Mock", { "alpha", "beta" })
	expect.eq(table.isfrozen(stubs), true, "robloxStubs returns a frozen table")
	expect.throws(function()
		stubs.alpha()
	end, "Flux.Mock.alpha requires a Roblox environment")
	expect.throws(function()
		stubs.beta()
	end, "Flux.Mock.beta requires a Roblox environment")
end)
