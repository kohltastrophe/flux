--!strict
--[[
	Compile-time checks for `Flux.Sync`: shared signals, validators, per-player `:of` / `:clear`, `:unreliable`,
	`Flux.Sync.ready`, and `Flux.Unwrap`. Lint type-checks this file; it is never run.
]]

local Flux = require("../../src")

type Node<T> = Flux.Node<T>
type Reactive<T> = Flux.Reactive<T>

local coins = Flux.Sync("Coins", 0)
local name = Flux.Sync("Name", "Kohl")
local theme = Flux.Sync("Theme", "Dark", function(_player: Player, value: string)
	return value == "Dark" or value == "Light"
end)
local dynamic = Flux.Sync.Dynamic
local volume: Flux.SyncSignal<number> = Flux.Sync("Volume", 5, function(_, value)
	return true, math.clamp(value, 0, 10)
end)

local n: number = coins()
local s: string = name:get()
local t: string = theme:peek()
coins:set(5)
name:set("Kohl2")
dynamic("anything")
assert(coins() == 5 and name() == "Kohl2", "synced")

local function forPlayer(player: Player)
	local own: Flux.State<number> = coins:of(player)
	own:set(10)
	coins:clear(player)
end

local chained: Flux.SyncSignal<number> = coins:unreliable(true):validate(function(_, value)
	return value >= 0
end)

local asNode: Node<number> = coins
local label: Reactive<string> = name
local unwrapped: Flux.Unwrap<Flux.SyncSignal<number>> = 1
local doubled = Flux.computed(function()
	return coins() * 2
end)
Flux.Sync.flush()
local ready: boolean = Flux.Sync.ready()
assert(coins:peek() == 5)

return { ready, n, s, t, forPlayer, chained, asNode, label, unwrapped, doubled, volume }
