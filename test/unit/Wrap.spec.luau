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

test("split · partitions keys into group tables and a rest table", function()
	local input = { label = "Click", count = 3, Size = "big", [1] = "child" }
	local own, rest = Flux.split(input, { "label", "count" })
	expect(own.label == "Click" and own.count == 3, "picked keys placed into own")
	expect(own.Size == nil and own[1] == nil, "unpicked keys excluded from own")
	expect(rest.Size == "big" and rest[1] == "child", "remaining keys and numeric children placed into rest")
	expect(rest.label == nil and rest.count == nil, "picked keys excluded from rest")
	expect(input.label == "Click" and input.Size == "big", "input table left untouched")
end)

test("split · accepts a schema table and multiple groups; first group wins on overlap", function()
	local SCHEMA = { a = 1, b = 2 }
	local g1, g2, rest = Flux.split({ a = 10, b = 20, c = 30, d = 40 }, SCHEMA, { "b", "c" })
	expect(g1.a == 10 and g1.b == 20 and g1.c == nil, "first group claims a and b")
	expect(g2.b == nil and g2.c == 30, "overlapping key b goes only to the first group")
	expect(rest.d == 40 and rest.a == nil and rest.b == nil and rest.c == nil, "rest receives unclaimed keys")
end)

test("split · nil props returns empty tables", function()
	local own, rest = Flux.split(nil, { "a", "b" })
	expect(next(own) == nil and next(rest) == nil, "nil props produces empty tables")
end)

test("fallback · returns static value when present, or default when nil", function()
	expect(Flux.fallback("custom", "default")() == "custom", "present static value kept")
	expect(Flux.fallback(false, true)() == false, "false is preserved, not replaced by default")
	expect(Flux.fallback(nil, "default")() == "default", "nil falls back to default")
end)

test("fallback · reactive source or default returns a node that falls back on nil", function()
	local src = Flux.signal(nil :: string?)
	local def = Flux.signal("fallback")
	local resolved = Flux.fallback(src, def)
	expect(Flux.isNode(resolved), "fallback produces a reactive node")
	expect(resolved() == "fallback", "nil reactive source yields reactive default")
	def:set("updated-fallback")
	expect(resolved() == "updated-fallback", "tracks changes to the default while source is nil")
	src:set("live")
	expect(resolved() == "live", "non-nil source value wins over default")
	src:set(false :: any)
	expect(resolved() == false, "false from a reactive source is kept, not treated as nil")
end)

return {}
