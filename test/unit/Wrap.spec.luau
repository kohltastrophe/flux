--!nonstrict
local IS_ROBLOX = game ~= nil

local Flux
local sert
if IS_ROBLOX then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	Flux = require(ReplicatedStorage:WaitForChild("Flux")) :: any
	sert = require(ReplicatedStorage:WaitForChild("sert")) :: any
else
	Flux = require("../../src") :: any
	sert = require("../sert") :: any
end

local test = sert.test
local expect = sert

test("wrap · replaces primitives with nodes", function()
	local t = { hp = 100, mp = 50, alive = true }
	Flux.wrap(t)
	expect(Flux.isNode(t.hp), "hp became a node")
	expect(Flux.isNode(t.mp), "mp became a node")
	expect(Flux.isNode(t.alive), "alive became a node")
	expect(t.hp() == 100, "node holds the original value")
	t.hp(90)
	expect(t.hp() == 90, "wrapped node is writable")
end)

test("wrap · recurses and preserves existing nodes", function()
	local existing = Flux(7)
	local t = {
		name = "x",
		keep = existing,
		stats = { atk = 5 },
	}
	Flux.wrap(t)
	expect(Flux.isNode(t.name), "top-level primitive wrapped")
	expect(t.keep == existing, "pre-existing node left untouched")
	expect(type(t.stats) == "table" and not Flux.isNode(t.stats), "nested table traversed, not replaced")
	expect(Flux.isNode(t.stats.atk), "nested primitive wrapped")
end)

test("wrap · wrapped signals survive scope teardown (GC-managed)", function()
	-- Flux.wrap replaces primitives with plain signals, which the enclosing scope does not own:
	-- they outlive its Destroy and the GC reclaims them once unreferenced.
	local t = { a = 1, b = 2 }
	local s = Flux.scope(function()
		Flux.wrap(t)
	end)
	expect(Flux.isNode(t.a), "scoped wrap creates nodes")
	s:Destroy()
	expect(Flux.isNode(t.a) and t.a() == 1, "wrapped signal survives scope teardown")
	t.a(7)
	expect(t.a() == 7, "and is still usable after the scope is gone")
end)

return {}
