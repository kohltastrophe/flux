--!nonstrict
local env = if game ~= nil
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Flux, sert = env.Flux, env.sert

local test = sert.test
local rtest = sert.rtest
local expect = sert

test("frame · effects auto-flush on the frame hookup", function()
	local a = Flux(1)
	local seen = {}
	local e = Flux.effect(function()
		table.insert(seen, a:get())
	end)
	-- No manual flush: run frames (engine frames in Roblox, Clock.step headless) until the hookup has run the effect.
	expect(
		env.frames(function()
			return seen[1] == 1
		end),
		"creation run flushed by the frame hookup"
	)
	a:set(2)
	expect(
		env.frames(function()
			return seen[#seen] == 2
		end),
		"set flushed by the frame hookup"
	)
	e:Destroy()
end)

rtest("frame · the hookup flushes at PreRender on a client and at Heartbeat elsewhere", function()
	local RunService = game:GetService("RunService")
	local client = RunService:IsClient()
	local frame = if client then RunService.PreRender else RunService.Heartbeat
	local a = Flux(1)
	local seen
	local e = Flux.effect(function()
		seen = a:get()
	end)
	Flux.flush()
	RunService.Heartbeat:Wait() -- start right after a frame's Heartbeat
	a:set(2)
	-- The engine may call this handler before Flux's own; a thread it defers runs after both, in the same frame step.
	local atStep
	local connection
	connection = frame:Connect(function()
		connection:Disconnect()
		task.defer(function()
			atStep = seen
		end)
	end)
	expect(
		sert.frames(function()
			return atStep ~= nil
		end),
		"the step ran"
	)
	expect.eq(atStep, 2, `the {if client then "PreRender" else "Heartbeat"} step itself flushed the effect`)
	e:Destroy()
end)

return {}
