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
local flush = Flux.flush
local Store = Flux.Store

test("store · deep reactivity per key", function()
	local state = Flux.store({
		player = { health = 100, name = "Guest" },
		settings = { volume = 0.5 },
	})
	local healthRuns, volumeRuns = 0, 0
	Flux(function()
		healthRuns += 1
		local _ = state.player.health
	end, true)
	Flux(function()
		volumeRuns += 1
		local _ = state.settings.volume
	end, true)
	flush()
	expect(healthRuns == 1 and volumeRuns == 1, "both effects run once initially")
	state.player.health = 90
	flush()
	expect(state.player.health == 90, "deep write persisted")
	expect(healthRuns == 2, "health observer re-ran")
	expect(volumeRuns == 1, "unrelated branch observer did NOT re-run")
end)

test("store · structural (length) tracking", function()
	local s = Flux.store({ items = { "a", "b" } })
	local lenRuns, lastLen = 0, 0
	Flux(function()
		lenRuns += 1
		lastLen = #s.items
	end, true)
	flush()
	expect(lenRuns == 1 and lastLen == 2, "tracks length initially")
	s.items[#s.items + 1] = "c"
	flush()
	expect(lenRuns == 2 and lastLen == 3, "length observer re-runs on structural change")
end)

test("store · iteration yields proxies; writes through them track", function()
	local store = Flux.store({ list = { { n = 1 }, { n = 2 } } })
	local total = new(function()
		local sum = 0
		for _, item in store.list do
			sum += item.n -- item must be a live proxy, not the raw table
		end
		return sum
	end)
	expect(total:get() == 3, "store iter sum")
	local firstProxy
	for _, item in store.list do
		firstProxy = item
		break
	end
	firstProxy.n = 10 -- write through an iterated value
	expect(total:get() == 12, "store iter write tracked")
end)

test("store · unwrap returns the raw table", function()
	local s = Flux.store({ a = 1, nested = { b = 2 } })
	local raw = Store.unwrap(s)
	expect(type(raw) == "table", "unwrap returns a table")
	expect(getmetatable(raw) == nil, "raw table has no proxy metatable")
	expect(raw.a == 1, "values are intact")
	expect(getmetatable(raw.nested) == nil, "nested raw table is also un-proxied")
end)

test("store · metatable'd values stay unwrapped; plain tables proxy", function()
	local innerNode = new(7)
	local Class = {}
	Class.__index = Class
	function Class.getValue(self)
		return self.v
	end
	local instObj = setmetatable({ v = 3 }, Class)
	local s = Store.new({ node = innerNode, obj = instObj, plain = { count = 1 } })
	local sawNode, sawObj, plainProxy = false, false, nil
	local total = new(function()
		local sum = 0
		for key, value in s do
			if key == "node" then
				sawNode = Flux.isNode(value)
				sum += value:get()
			elseif key == "obj" then
				sawObj = getmetatable(value) == Class
				sum += value:getValue()
			else
				plainProxy = value
				sum += value.count
			end
		end
		return sum
	end)
	expect(total:get() == 11 and sawNode and sawObj, "iteration yields callable values")
	expect(s.node == innerNode and s.obj == instObj, "__index leaves metatable'd values raw")
	plainProxy.count = 5 -- plain tables still proxy: writes through them track
	expect(total:get() == 15, "plain tables stay tracked")
	innerNode:set(9) -- node read through iteration was a real tracked get
	expect(total:get() == 17, "node reads stay tracked")
end)

test("store · node-valued keys never alias user nodes", function()
	local userNode = new(7)
	local s = Store.new({ slot = userNode })
	local reader = new(function()
		local n = s.slot
		return if Flux.isNode(n) then n:get() else n
	end)
	expect(reader:get() == 7, "baseline read")
	s.slot = 99 -- replace the key: must not write through to the user node
	expect(userNode:get() == 7 and Flux.isNode(userNode), "replaced key leaves user node untouched")
	expect(reader:get() == 99, "reader sees the replacement")
	Store.destroy(s)
	expect(getmetatable(userNode) ~= nil and userNode:get() == 7, "store teardown spares the user node")

	-- array of nodes: remove must not cross-write or destroy them
	local nodeA, nodeB = new(1), new(2)
	local s2 = Store.new({ nodeA, nodeB })
	local first = new(function()
		local n = s2[1]
		return if Flux.isNode(n) then n:get() else n
	end)
	local second = new(function()
		local n = s2[2]
		return if Flux.isNode(n) then n:get() else n
	end)
	expect(first:get() == 1 and second:get() == 2, "node array baseline")
	expect(Store.remove(s2, 1) == nodeA, "remove returns the user node")
	expect(nodeA:get() == 1 and nodeB:get() == 2 and getmetatable(nodeA) ~= nil, "user nodes uncorrupted")
	expect(first:get() == 2 and second:get() == nil, "readers shift")
end)

test("store · function values stay opaque leaves through every set path", function()
	-- __newindex / insert / remove route through Graph.set, so a stored
	-- callback never becomes a tracker's computation and never executes
	local calls = 0
	local fnA = function()
		calls += 1
		return "A"
	end
	local fnB = function()
		calls += 1
		return "B"
	end

	local s = Store.new({ cb = fnA })
	local reader = new(function()
		return s.cb
	end)
	expect(reader:get() == fnA, "baseline read")
	s.cb = fnB
	expect(reader:get() == fnB, "newindex returns the new fn")

	local arr = Store.new({ fnA, fnB })
	local first = new(function()
		return arr[1]
	end)
	expect(first:get() == fnA, "array baseline")
	Store.remove(arr, 1)
	expect(first:get() == fnB, "remove shift returns the fn raw")
	Store.insert(arr, 1, fnA)
	expect(first:get() == fnA, "insert shift returns the fn raw")
	expect(calls == 0, "stored fns never executed")
end)

test("store.remove · shifted readers, trackers, pos validation", function()
	local s = Store.new({ 10, 20, 30, 40 })
	local r2 = new(function()
		return s[2]
	end)
	local r4 = new(function()
		return s[4]
	end)
	local len = new(function()
		return #s
	end)
	local total = new(function()
		local sum = 0
		for _, v in s do
			sum += v
		end
		return sum
	end)
	expect(r2:get() == 20 and r4:get() == 40 and len:get() == 4 and total:get() == 100, "baseline")
	expect(Store.remove(s, 2) == 20, "middle returns removed value")
	expect(r2:get() == 30 and r4:get() == nil and len:get() == 3 and total:get() == 80, "readers shift")
	expect(Store.remove(s) == 40, "default pos removes the tail")
	expect(r2:get() == 30 and len:get() == 2 and total:get() == 40, "tail removal tracked")
	expect(
		(pcall(Store.remove, s, 5)) == false
			and (pcall(Store.remove, s, 0)) == false
			and (pcall(Store.remove, s, 1.5)) == false
			and (pcall(Store.remove, s, "2")) == false,
		"out-of-range / fractional / string pos errors"
	)
	expect(len:get() == 2 and total:get() == 40, "rejected pos leaves state intact")
	local empty = Store.new({})
	expect(Store.remove(empty) == nil, "empty store with no pos is a nil no-op")
end)

test("store.remove · alias survival and displaced teardown", function()
	-- same raw table at two keys: removing one must keep the survivor live
	local shared = { x = 1 }
	local s = Store.new({ shared, shared })
	local reader = new(function()
		return s[1].x
	end)
	expect(reader:get() == 1, "baseline")
	expect(Store.remove(s, 1) == shared, "returns the raw table")
	s[1].x = 5
	expect(reader:get() == 5, "survivor stays reactive")

	-- non-aliased: removed table's proxy torn down; reader follows the shifted survivor
	local s2 = Store.new({ { v = 1 }, { v = 2 } })
	local first = new(function()
		return s2[1].v
	end)
	expect(first:get() == 1, "shift baseline")
	Store.remove(s2, 1)
	expect(first:get() == 2, "reader follows the survivor")
end)

test("store · displacement via assignment runs the same alias scan", function()
	-- overwriting one occurrence of a shared raw table must not sever
	-- readers of the surviving occurrence (mirrors Store.remove's scan)
	local shared = { x = 1 }
	local s = Store.new({ shared, shared, "filler" })
	local reader = new(function()
		return s[2].x
	end)
	expect(reader:get() == 1, "baseline")
	s[1] = "other"
	s[2].x = 5
	expect(reader:get() == 5, "survivor stays reactive")
end)

test("store.insert · middle/append with readers and a length tracker", function()
	local s = Store.new({ 10, 30 })
	local r1 = new(function()
		return s[1]
	end)
	local r2 = new(function()
		return s[2]
	end)
	local r3 = new(function()
		return s[3]
	end)
	local len = new(function()
		return #s
	end)
	expect(r1:get() == 10 and r2:get() == 30 and r3:get() == nil and len:get() == 2, "baseline")
	Store.insert(s, 2, 20) -- middle: shifts 30 from index 2 to 3
	expect(r1:get() == 10 and r2:get() == 20 and r3:get() == 30 and len:get() == 3, "middle shifts readers")
	Store.insert(s, 40) -- append
	expect(s[4] == 40 and len:get() == 4, "append updates the length tracker")
end)

test("store.insert · validates explicit positions", function()
	-- Luau's table.insert silently accepts fractional/out-of-range pos,
	-- which would desync the per-index nodes from the raw table
	local s = Store.new({ 10, 20, 30 })
	local r1 = new(function()
		return s[1]
	end)
	expect(r1:get() == 10, "baseline")
	expect((pcall(Store.insert, s, 1.5, 99)) == false, "fractional pos rejected")
	expect((pcall(Store.insert, s, 50, 99)) == false, "out-of-range pos rejected")
	expect((pcall(Store.insert, s, "2", 99)) == false, "string pos rejected")
	Store.insert(s, 4, 40) -- length+1 is a valid append position
	expect(s[4] == 40 and r1:get() == 10, "append at length+1")
end)

test("store.reconcile · sparse and out-of-band integer keys", function()
	local s = Store.new({ [2] = "old", name = "n" })
	Store.reconcile(s, { [2] = "new", name = "n" })
	expect(Store.unwrap(s)[2] == "new", "sparse [2] (no [1]) updated")

	local s2 = Store.new({ name = "n" })
	Store.reconcile(s2, { [2] = "added", name = "n" })
	expect(Store.unwrap(s2)[2] == "added", "sparse [2] added")

	local s3 = Store.new({ [3] = "x", name = "n" })
	Store.reconcile(s3, { name = "n" })
	expect(Store.unwrap(s3)[3] == nil, "hole [3] removed")

	local s4 = Store.new({ 10, 20, [5] = "x" })
	Store.reconcile(s4, { 10, 20, [5] = "z" })
	expect(Store.unwrap(s4)[5] == "z", "out-of-band [5] past a real array updated")
end)

test("store.reconcile · fires only changed leaves, leaves others untouched", function()
	local s = Store.new({ player = { health = 100, name = "Guest" }, settings = { volume = 0.5 } })
	local healthRuns, nameRuns, volRuns = 0, 0, 0
	Flux(function()
		healthRuns += 1
		local _ = s.player.health
	end, true)
	Flux(function()
		nameRuns += 1
		local _ = s.player.name
	end, true)
	Flux(function()
		volRuns += 1
		local _ = s.settings.volume
	end, true)
	flush()
	expect(healthRuns == 1 and nameRuns == 1 and volRuns == 1, "baseline runs")

	Store.reconcile(s, { player = { health = 90, name = "Guest" }, settings = { volume = 0.5 } })
	flush()
	expect(s.player.health == 90, "changed leaf applied")
	expect(healthRuns == 2, "only the changed leaf observer re-ran")
	expect(nameRuns == 1 and volRuns == 1, "unchanged leaves did not fire")
end)

test("store.reconcile · identical snapshot is a no-op", function()
	local s = Store.new({ a = 1, nested = { b = 2 } })
	local runs = 0
	Flux(function()
		runs += 1
		local _ = s.a + s.nested.b
	end, true)
	flush()
	expect(runs == 1, "baseline")
	Store.reconcile(s, { a = 1, nested = { b = 2 } })
	flush()
	expect(runs == 1, "identical reconcile fired nothing")
end)

test("store.reconcile · reuses nested proxy identity, no teardown", function()
	local s = Store.new({ nested = { b = 2 } })
	local nestedBefore = s.nested
	local reader = new(function()
		return s.nested.b
	end)
	expect(reader:get() == 2, "baseline")
	Store.reconcile(s, { nested = { b = 5 } })
	expect(s.nested == nestedBefore, "nested proxy identity preserved")
	expect(reader:get() == 5, "leaf updated through the reused proxy")
end)

test("store.reconcile · adds and removes keys, fires the tracker once", function()
	local s = Store.new({ a = 1, b = 2 })
	local keyRuns, sawKeys = 0, {}
	Flux(function()
		keyRuns += 1
		sawKeys = {}
		for k in s do
			sawKeys[k] = true
		end
	end, true)
	flush()
	expect(keyRuns == 1 and sawKeys.a and sawKeys.b, "baseline keys")
	Store.reconcile(s, { a = 1, c = 3 })
	flush()
	expect(keyRuns == 2, "key-set change fired the tracker exactly once")
	expect(s.a == 1 and s.b == nil and s.c == 3, "key set reconciled")
	expect(sawKeys.c and sawKeys.b == nil, "iteration reflects new key set")
end)

test("store.reconcile · array positional diff with grow and shrink", function()
	local s = Store.new({ 10, 20, 30 })
	local r2 = new(function()
		return s[2]
	end)
	local len = new(function()
		return #s
	end)
	expect(r2:get() == 20 and len:get() == 3, "baseline")

	Store.reconcile(s, { 10, 99, 30, 40 })
	expect(r2:get() == 99 and len:get() == 4, "changed index + grow")
	expect(Store.unwrap(s)[4] == 40, "appended value present")

	Store.reconcile(s, { 10 })
	expect(len:get() == 1, "length tracker followed the shrink")
	expect(Store.unwrap(s)[2] == nil and Store.unwrap(s)[3] == nil, "tail cleared")
end)

test("store.reconcile · scalar replaces nested table tears down the displaced proxy", function()
	local s = Store.new({ slot = { v = 1 } })
	local innerRaw = Store.unwrap(s).slot
	local _ = s.slot.v
	expect(getmetatable(s.slot) ~= nil, "nested proxy exists")
	Store.reconcile(s, { slot = "gone" })
	expect(s.slot == "gone", "scalar replacement applied")
	local reproxied = Store.new(innerRaw)
	expect(getmetatable(reproxied) ~= nil, "displaced proxy was torn down")
end)

test("store.reconcile · nested array inside hash reconciles positionally", function()
	local s = Store.new({ items = { "a", "b" }, count = 2 })
	local lenRuns, lastLen = 0, 0
	Flux(function()
		lenRuns += 1
		lastLen = #s.items
	end, true)
	flush()
	expect(lenRuns == 1 and lastLen == 2, "baseline")
	Store.reconcile(s, { items = { "a", "b", "c" }, count = 3 })
	flush()
	expect(lastLen == 3, "nested array length followed reconcile")
	expect(s.items[3] == "c" and s.count == 3, "nested + sibling scalar applied")
end)

test("store.reconcile · stored functions stay opaque leaves", function()
	local calls = 0
	local fnA = function()
		calls += 1
	end
	local fnB = function()
		calls += 1
	end
	local s = Store.new({ cb = fnA })
	local reader = new(function()
		return s.cb
	end)
	expect(reader:get() == fnA, "baseline")
	Store.reconcile(s, { cb = fnB })
	expect(reader:get() == fnB, "fn leaf swapped")
	expect(calls == 0, "stored fns never executed by reconcile")
end)

test("store.reconcile · rejects non-store and non-table args", function()
	local s = Store.new({ a = 1 })
	expect((pcall(Store.reconcile, {}, { a = 1 })) == false, "non-proxy target rejected")
	expect((pcall(Store.reconcile, s, 5 :: any)) == false, "non-table newData rejected")
end)

test("store · per-key nodes are owned by the store, not the reading reaction", function()
	-- A store created at the root owns the nodes its reads materialize. Destroying a
	-- reader must not take those nodes with it, or the next reader would track a corpse.
	local s = Store.new({ count = 1 })
	local first = new(function()
		return s.count -- materializes the per-key node for `count`
	end)
	expect(first:get() == 1, "first reader sees the value")
	first:Destroy() -- the per-key node is owned by the store, not this reader

	local runs, last = 0, 0
	Flux(function()
		runs += 1
		last = s.count
	end, true)
	flush()
	expect(runs == 1 and last == 1, "a fresh reader still sees the live store node")
	s.count = 2
	flush()
	expect(runs == 2 and last == 2, "the surviving store node still propagates writes")
	Store.destroy(s)
end)

test("store · created in a scope is destroyed with the scope", function()
	local raw = { hp = 100, nested = { mp = 50 } }
	local s, nestedProxy
	local owner = Flux.scope(function()
		s = Flux.store(raw)
		Flux(function()
			local _ = s.hp
		end, true)
		nestedProxy = s.nested -- materialize the nested proxy (owned by the store)
		Flux(function()
			local _ = s.nested.mp
		end, true)
	end)
	flush()
	expect(getmetatable(s) ~= nil and getmetatable(nestedProxy) ~= nil, "proxies are live inside the scope")

	owner:Destroy()
	expect(getmetatable(s) == nil, "root proxy is stripped when its scope is destroyed")
	expect(getmetatable(nestedProxy) == nil, "nested proxy is torn down by the cascade too")
	expect(raw.hp == 100 and raw.nested.mp == 50, "the raw table is left intact")

	local s2 = Flux.store(raw)
	expect(getmetatable(s2) ~= nil and s2 ~= s, "the raw table can be re-wrapped after teardown")
	Store.destroy(s2)
end)

test("store.reconcile · duplicate keys alias one element (expected warn)", function()
	-- Keys must be unique; a duplicate reuses the same matched element across slots. This
	-- now warns (parity with For.value), but the aliasing behavior itself is unchanged.
	local s = Flux.store({ { id = 1, name = "a" } })
	Store.reconcile(s, { { id = 1, name = "b" }, { id = 1, name = "c" } }, "id")
	local raw = Store.unwrap(s)
	expect(raw[1] == raw[2], "duplicate keys collapse onto one reused element")
end)

return {}
