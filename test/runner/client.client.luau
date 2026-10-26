--!nonstrict
-- Flux's Studio runner, client side (from ReplicatedFirst): runs the specs once the server hands it the run.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local Runner = require(ReplicatedStorage:WaitForChild("sert"):WaitForChild("roblox"):WaitForChild("Runner")) :: any
local config = require(ReplicatedStorage:WaitForChild("Flux.Tests")) :: any
assert(type(config) == "table", "Flux.Tests config must be a table")
Runner.client(config)
