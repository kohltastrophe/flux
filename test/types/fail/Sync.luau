--!strict
--[[
	Compile-fail checks for Flux.Sync: a synced signal keeps its value type like `Flux.signal`.
]]

local Flux = require("../../../src")

local coins = Flux.Sync("Coins", 0)
coins:set("not a number") -- expect-error: a number signal takes numbers
local _name: string = coins() -- expect-error: reads keep the value type
local _player: Flux.State<string> = coins:of((nil :: any) :: Player) -- expect-error: per-player keeps the type

return {}
