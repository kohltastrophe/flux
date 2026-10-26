--!nonstrict
-- Flux's Studio runner, server side: sert's Runner with `Config` (does nothing in an ordinary Play session).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Runner = require(ReplicatedStorage:WaitForChild("sert"):WaitForChild("roblox"):WaitForChild("Runner")) :: any
local config = require(ReplicatedStorage:WaitForChild("Flux.Tests")) :: any
assert(type(config) == "table", "Flux.Tests config must be a table")
Runner.server(config)
