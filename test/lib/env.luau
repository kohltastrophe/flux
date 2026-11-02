--!nonstrict
local IS_ROBLOX = game ~= nil

local Flux
local Compat
local sert
local engine
local bridge: () -> () = nil :: any
if IS_ROBLOX then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	Flux = require(ReplicatedStorage:WaitForChild("Flux")) :: any
	Compat = require(ReplicatedStorage.Flux:WaitForChild("Compat")) :: any
	sert = require(ReplicatedStorage:WaitForChild("sert")) :: any
else
	-- Headless: a sert.env engine on Flux's own manual clock, handed to Compat before Flux loads (Responsive reads
	-- the services at module load). Its Instances, services and RunService stand in for the engine's; its game is
	-- never the global `game`, so Flux keeps its headless Compat and Clock paths.
	sert = require("@sert") :: any
	local HeadlessClock = require("../../src/Clock") :: any
	Compat = require("../../src/Compat") :: any
	engine = sert.env.new({
		isClient = true,
		isStudio = true,
		strict = true,
		datatypes = Compat,
		host = {
			clock = HeadlessClock.now,
			spawn = Compat.task.spawn,
			defer = HeadlessClock.defer,
			delay = HeadlessClock.delay,
			wait = HeadlessClock.wait,
			cancel = HeadlessClock.cancel,
		},
	})
	Compat.Instance = engine.Instance
	Compat.services = setmetatable({}, {
		__index = function(_, name: string): any
			return engine.game:GetService(name)
		end,
	})
	-- The engine's RunService phases run in Flux's Heartbeat; Clock.reset drops subscribers, so env.reset re-bridges.
	function bridge()
		HeadlessClock.connect("Heartbeat", function(dt: number)
			engine:step(dt)
		end)
	end
	bridge()
	Flux = require("../../src") :: any
end

local Clock = Flux.Clock

local env = {
	IS_ROBLOX = IS_ROBLOX,
	Flux = Flux,
	Compat = Compat,
	sert = sert,
	engine = engine,
	workspace = if IS_ROBLOX then workspace else engine.workspace,
	Instance = Compat.Instance,
	Color3 = Compat.Color3,
	UDim = Compat.UDim,
	UDim2 = Compat.UDim2,
	Vector2 = Compat.Vector2,
	ColorSequence = Compat.ColorSequence,
	NumberSequence = Compat.NumberSequence,
	Enum = Compat.Enum,
	task = Compat.task,
}

function env.settle()
	if IS_ROBLOX then
		task.wait()
	else
		Clock.drain()
	end
end

function env.frame(dt: number?)
	if IS_ROBLOX then
		game:GetService("RunService").Heartbeat:Wait()
	else
		Clock.step(dt or 1 / 60)
	end
end

function env.frames(done: () -> boolean, count: number?): boolean
	return sert.frames(done, count, nil, env.frame)
end

function env.mountUi(parent: any, viewport: Vector2): (any, () -> ())
	if not IS_ROBLOX then
		return parent, function() end
	end
	local screen = Instance.new("ScreenGui")
	local host = Instance.new("Frame")
	host.Name = "ViewportHost"
	host.Size = UDim2.fromOffset(viewport.X, viewport.Y)
	host.BackgroundTransparency = 1
	host.Parent = screen
	return host, function()
		screen:Destroy()
	end
end

function env.warnings(fn: () -> ()): { string }
	assert(type(fn) == "function", "env.warnings expects a function")
	local messages = {}
	Compat.setWarnHook(function(message: string)
		table.insert(messages, message)
	end)
	local ok, err = pcall(fn)
	Compat.setWarnHook(nil)
	if not ok then
		error(err, 0)
	end
	return messages
end

local freshCount = 0
function env.fresh(prefix: string): string
	freshCount += 1
	return `{prefix}{freshCount}`
end

function env.reset()
	if IS_ROBLOX and Clock.isManual() then
		Clock.manual(false)
	else
		Clock.reset()
		if engine ~= nil then
			bridge()
		end
	end
	Compat.setWarnHook(nil)
end

-- Probe helpers for global reactive state quiescence
function env.idle(targetFlux: any?, expectOpts: { contexts: { { context: any, default: any } }? }?): string?
	local F = targetFlux or Flux
	if F.getOwner() ~= nil then
		return "an owner leaked: Flux.getOwner() is not nil at top level"
	elseif F.isReactive() then
		return "a reaction leaked: Flux.isReactive() is true at top level"
	end
	F.retrack()
	if F.isReactive() then
		return "a suspended reaction leaked: Flux.retrack() at top level resumed tracking"
	elseif pcall(F.cleanup, function() end) then
		return "Flux.cleanup accepted a value at top level (an owner leaked)"
	end
	if expectOpts and expectOpts.contexts then
		for _, entry in expectOpts.contexts do
			local value = entry.context:get()
			if value ~= entry.default then
				return `a provided context leaked: it reads {value} at top level, expected its default {entry.default}`
			end
		end
	end
	return nil
end

function env.drained(targetFlux: any?): string?
	local F = targetFlux or Flux
	local runs = 0
	local probe = F.effect(function()
		runs += 1
	end)
	F.flush()
	local first = runs
	F.flush()
	probe:Destroy()
	if first ~= 1 then
		return `a fresh effect ran {first} times on flush, expected 1 (queue or flushing flag stuck)`
	elseif runs ~= first then
		return `a fresh effect ran again on a second flush ({runs - first} more runs)`
	end
	return nil
end

return table.freeze(env)
