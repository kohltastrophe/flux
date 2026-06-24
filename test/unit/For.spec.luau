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
local new = Flux.Graph.new
local For = { value = Flux.forValue, index = Flux.forIndex }

test("for · mapFn reads are untracked; item nodes update", function()
	local noise = new(0)
	local list = new({ "a", "b" })
	local mapRuns = 0
	local mapped = For.value(list, function(indexNode, value)
		mapRuns += 1
		noise:get() -- must NOT become a dependency of the mapper
		return value .. tostring(indexNode:get())
	end)
	local out = mapped:get()
	expect(out[1] == "a1" and out[2] == "b2" and mapRuns == 2, "initial map")
	noise:set(1)
	expect(mapped:get() == out and mapRuns == 2, "mapFn untracked")
	list:set({ "b", "a" })
	local out2 = mapped:get()
	-- keyed: cached mapped results move with their values (no re-run)
	expect(mapRuns == 2 and out2[1] == "b2" and out2[2] == "a1", "keyed reuse")
end)

test("forValue · updates in place, caches by value", function()
	local a, b = { id = "a" }, { id = "b" }
	local list = Flux({ a, b })
	local calls = 0
	local mapped = Flux.forValue(list, function(indexNode, value)
		calls += 1
		expect(Flux.isNode(indexNode), "forValue first arg is a reactive index")
		return { value = value, indexNode = indexNode }
	end)
	local r1 = mapped()
	expect(calls == 2, "mapped once per value")
	expect(r1[1].value == a and r1[2].value == b, "values mapped to positions")
	expect(r1[1].indexNode() == 1 and r1[2].indexNode() == 2, "index nodes track position")
	-- reorder: cached by identity, so no remap; index nodes update in place
	list({ b, a })
	local r2 = mapped()
	expect(calls == 2, "reorder reuses cached results (no remap)")
	expect(r2[1].value == b and r2[2].value == a, "result follows new order")
	expect(r1[1].indexNode() == 2, "value a's index node moved to 2")
	expect(r2[2] == r1[1], "same cached object follows the value across positions")
end)

test("forIndex · updates in place, caches by position", function()
	local list = Flux({ 10, 20, 30 })
	local calls = 0
	local mapped = Flux.forIndex(list, function(index, itemNode)
		calls += 1
		expect(Flux.isNode(itemNode), "forIndex second arg is a reactive node")
		return {
			read = function()
				return itemNode()
			end,
		}
	end)
	local r1 = mapped()
	expect(calls == 3, "one map call per slot")
	expect(r1[1].read() == 10 and r1[2].read() == 20 and r1[3].read() == 30, "initial values")
	-- change a value -> node updates in place, no new map call
	list({ 10, 99, 30 })
	local r2 = mapped()
	expect(calls == 3, "value change does not remap")
	expect(r2[2].read() == 99, "underlying item node updated")
	expect(r2[1] == r1[1], "unchanged slot's cached result reused")
	-- shrink -> removed slots cleaned out of the result
	list({ 10 })
	local r3 = mapped()
	expect(calls == 3, "shrinking does not remap")
	expect(r3[1].read() == 10 and r3[2] == nil and r3[3] == nil, "removed slots cleared")
end)

test("forValue · duplicates share one mapped instance (expected warn)", function()
	local list = new({ "x", "x", "y" })
	local mapRuns = 0
	local mapped = For.value(list, function(indexNode, value)
		mapRuns += 1
		return { value = value }
	end)
	local out = mapped:get()
	expect(out[1] == out[2] and out[1] ~= out[3], "shared mapped instance")
	expect(mapRuns == 2, "mapper runs once per unique value")
end)

test("forIndex · node and function elements stay opaque", function()
	-- the per-index item node BOXES node/function elements (mirrors Store's
	-- tracker rule) instead of aliasing the user's node or executing the fn
	local userNode = new(5)
	local items = {}
	local list = new({ userNode })
	local mapped = For.index(list, function(index, item)
		table.insert(items, item)
		return item
	end)
	mapped:get()
	expect(items[1] ~= userNode and items[1]:get() == userNode, "item node boxes the user node")
	list:set({ 42 })
	mapped:get()
	expect(userNode:get() == 5, "reassignment leaves the user node intact")
	list:set({})
	mapped:get()
	expect(getmetatable(userNode) ~= nil, "eviction doesn't destroy the user node")
	mapped:Destroy()
	expect(getmetatable(userNode) ~= nil, "mapper destroy doesn't destroy the user node")

	local fnCalls = 0
	local fnEl = function()
		fnCalls += 1
	end
	local list2 = new({ fnEl })
	local mapped2 = For.index(list2, function(index, item)
		return item:get()
	end)
	expect(mapped2:get()[1] == fnEl and fnCalls == 0, "fn element returned raw, never executed")
end)

test("forValue · removed value's mapped result is cleaned and item node destroyed once", function()
	-- eviction Cleans the mapped result and Destroys the per-value index node, once
	-- each; surviving values keep theirs
	local cleaned = {}
	local nodeDestroyed = {}
	local list = new({ "a", "b", "c" })
	local mapped = For.value(list, function(indexNode, value)
		-- the index node is the per-value node that gets Destroyed on eviction
		indexNode:onDestroy(function()
			nodeDestroyed[value] = (nodeDestroyed[value] or 0) + 1
		end)
		-- the mapped result is Clean()ed on eviction; a function result is invoked
		return function()
			cleaned[value] = (cleaned[value] or 0) + 1
		end
	end)
	mapped:get()
	expect(next(cleaned) == nil and next(nodeDestroyed) == nil, "nothing cleaned while all present")

	-- remove "b"
	list:set({ "a", "c" })
	mapped:get()
	expect(cleaned.b == 1, "removed value's mapped result Cleaned exactly once")
	expect(nodeDestroyed.b == 1, "removed value's index node Destroyed exactly once")
	expect(cleaned.a == nil and cleaned.c == nil, "surviving values' results NOT cleaned")
	expect(nodeDestroyed.a == nil and nodeDestroyed.c == nil, "surviving values' nodes NOT destroyed")
end)

test("for · eviction-scan reads stay untracked (no leaked mapper dependency)", function()
	-- the removal scan runs onDestroy handlers and Clean()s mapped results; if a
	-- cleanup reads a node it must NOT subscribe the mapper, or the mapper would
	-- spuriously recompute on that unrelated node's changes
	local dep = new(0)
	local list = new({ "a", "b" })
	local mapped = For.value(list, function(indexNode, value)
		return function()
			dep:get() -- tracked read invoked by Clean() on eviction
		end
	end)
	mapped:get()
	list:set({ "a" }) -- evicts "b"; its cleanup reads dep
	mapped:get()
	-- white-box: node deps live at node._[7] (SOURCES), holding source data tables
	local sources = mapped._[7]
	expect(sources ~= nil and table.find(sources, dep._) == nil, "cleanup read did not leak into deps")
	expect(table.find(sources, list._) ~= nil, "list remains the mapper's only dependency")
end)

test("for · cleanup inside mapFn scopes to the row (Solid <For> per-row root)", function()
	-- mapFn runs under its per-row node as owner: a cleanup registered inside
	-- fires once, when THAT row is evicted -- not on every reconcile, not for rows
	-- that survive
	local cleaned = {}
	local list = new({ "a", "b" })
	local mapped = For.value(list, function(indexNode, value)
		Flux.cleanup(function()
			cleaned[value] = (cleaned[value] or 0) + 1
		end)
		return value
	end)
	mapped:get()
	list:set({ "b", "a" }) -- reconcile that removes nothing
	mapped:get()
	expect(next(cleaned) == nil, "no row cleanup on a reconcile that evicts nothing")
	list:set({ "b" }) -- evict "a"
	mapped:get()
	expect(cleaned.a == 1 and cleaned.b == nil, "only the evicted row's cleanup fired, exactly once")
end)

test("forIndex · shrinking cleans the removed slot's result and item node once", function()
	-- shrinking Cleans the dropped slot's result and Destroys its item node, once
	-- each; surviving slots are untouched
	local cleaned = {}
	local nodeDestroyed = {}
	local list = new({ 10, 20, 30 })
	local mapped = For.index(list, function(index, itemNode)
		-- the item node is the per-index node that gets Destroyed on eviction
		itemNode:onDestroy(function()
			nodeDestroyed[index] = (nodeDestroyed[index] or 0) + 1
		end)
		return function()
			cleaned[index] = (cleaned[index] or 0) + 1
		end
	end)
	mapped:get()
	expect(next(cleaned) == nil and next(nodeDestroyed) == nil, "nothing cleaned while all present")

	-- shrink from 3 to 1: slots 2 and 3 are evicted
	list:set({ 10 })
	mapped:get()
	expect(cleaned[2] == 1 and cleaned[3] == 1, "dropped slots' results Cleaned exactly once")
	expect(nodeDestroyed[2] == 1 and nodeDestroyed[3] == 1, "dropped slots' item nodes Destroyed exactly once")
	expect(cleaned[1] == nil, "surviving slot's result NOT cleaned")
	expect(nodeDestroyed[1] == nil, "surviving slot's item node NOT destroyed")
end)

test("forIndex · reorder keeps results BY POSITION, mutating item nodes (unkeyed)", function()
	-- forIndex is keyed by INDEX, not value: a reorder keeps each position's cached
	-- result and feeds the new element into that slot's item node (no remap)
	local list = new({ "a", "b", "c" })
	local calls = 0
	local mapped = For.index(list, function(index, itemNode)
		calls += 1
		return { slot = index, item = itemNode }
	end)
	local r1 = mapped:get()
	expect(calls == 3, "one map call per slot")
	expect(r1[1].item:get() == "a" and r1[2].item:get() == "b" and r1[3].item:get() == "c", "initial values per slot")

	-- reverse the list
	list:set({ "c", "b", "a" })
	local r2 = mapped:get()
	expect(calls == 3, "reorder does NOT remap (no new map calls)")
	-- same cached result objects stay at the same POSITION...
	expect(r2[1] == r1[1] and r2[2] == r1[2] and r2[3] == r1[3], "cached results stay by position")
	expect(r2[1].slot == 1 and r2[3].slot == 3, "the per-slot result identity is positional")
	-- ...but the item node value at each position is updated to the new element
	expect(r2[1].item:get() == "c", "position 1's item node now holds the new element")
	expect(r2[2].item:get() == "b", "position 2 unchanged element")
	expect(r2[3].item:get() == "a", "position 3's item node now holds the new element")
end)

return {}
