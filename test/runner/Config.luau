--!nonstrict
--[[
	The Flux core suite's configuration for sert's Studio runner (`<sert>/roblox/Runner`; `sert studio --suite core`
	calls `Runner.edit` with it in the edit DataModel, with no player, like the Open Cloud task). One side, whose entry
	is the unit aggregator: it requires every spec and returns the suite's hooks, which the side installs while it runs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local unit = ReplicatedStorage:WaitForChild("Flux.unit")

-- The aggregator's hooks, read when a test runs (the runner has loaded the aggregator by then).
local function hook(name: string): () -> ()
	return function()
		local fn = (require(unit) :: any)[name]
		if fn then
			fn()
		end
	end
end

return {
	name = "Flux",
	characters = false,
	warmup = function()
		local Players = game:GetService("Players")
		local localPlayer = assert(Players.LocalPlayer, "LocalPlayer expected for warmup")
		local gui = Instance.new("ScreenGui")
		gui.Name = "Flux.WarmUp"
		gui.ResetOnSpawn = false
		gui.Parent = assert(localPlayer:WaitForChild("PlayerGui", 10), "PlayerGui expected for warmup")
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromOffset(100, 40)
		btn.Parent = gui
		return function()
			gui:Destroy()
		end
	end,
	sides = {
		core = { entry = unit, setup = { beforeEach = hook("beforeEach"), afterEach = hook("afterEach") } },
	},
}
