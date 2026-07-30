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

test("props · merges declared overrides over defaults, ignores unknown keys", function()
	local DEFAULTS = { label = "hi", count = 0, active = true }
	local p = Flux.props(DEFAULTS, { count = 5, active = false, Size = "for hydration" })
	expect(p.label() == "hi", "default used when override absent")
	expect(p.count() == 5, "override replaces default")
	expect(p.active() == false, "a false override still applies")
	expect(p.Size == nil, "unknown override keys are not taken")
	expect(DEFAULTS.count == 0, "defaults table left untouched")
end)

test("props · converts functions to computeds and passes nodes through", function()
	local src = Flux(2)
	local shared = Flux("theme")
	local p = Flux.props({
		double = function()
			return src() * 2
		end,
		theme = shared,
	})
	expect(Flux.isNode(p.double), "function default became a node")
	expect(p.double() == 4, "computed derives from its source")
	src(3)
	expect(p.double() == 6, "computed recomputes")
	expect(p.theme == shared, "node default passes through by reference")
end)

test("props · deep-copies plain table defaults so instances never share state", function()
	local DEFAULTS = { nested = { value = 1 } }
	local a = Flux.props(DEFAULTS)
	local b = Flux.props(DEFAULTS)
	expect(DEFAULTS.nested.value == 1, "schema leaf still a plain value")
	expect(Flux.isNode(a.nested.value), "nested leaf wrapped per instance")
	a.nested.value(5)
	expect(b.nested.value() == 1, "sibling instance unaffected")
	expect(a.nested ~= b.nested, "nested tables are per-instance copies")
end)

test("props · a table override replaces the default table wholesale", function()
	local p = Flux.props({ opts = { a = 1 } }, { opts = { a = 2, b = 3 } })
	expect(p.opts.a() == 2, "override table wins")
	expect(p.opts.b() == 3, "override-only nested keys survive (schema filters top level only)")
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
