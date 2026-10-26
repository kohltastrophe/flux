--!nonstrict
local env = if game
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Model = if game
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("Model")) :: any
	else require("../lib/Model") :: any

local Flux = env.Flux
local sert = env.sert
local IS_ROBLOX = env.IS_ROBLOX
local test = sert.test
local expect = sert
local new = Flux
local flush = Flux.flush
local Store = Flux.Store

local function fullCollect(): boolean
	local collect = if IS_ROBLOX then nil else (_G :: any).collectgarbage
	return collect ~= nil and (pcall(collect, "collect"))
end

test("store · metatable'd values stay unwrapped; plain tables proxy", function()
	local innerNode = new(7)
	local Class = {}
	Class.__index = Class
	function Class.getValue(self)
		return self.v
	end
	local instObj = setmetatable({ v = 3 }, Class)
	local s = Flux.store({ node = innerNode, obj = instObj, plain = { count = 1 } })
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
	plainProxy.count = 5
	expect(total:get() == 15, "plain tables stay tracked")
	innerNode:set(9)
	expect(total:get() == 17, "node reads stay tracked")
end)

test("store · node-valued keys never alias user nodes", function()
	local userNode = new(7)
	local s = Flux.store({ slot = userNode })
	local reader = new(function()
		local n = s.slot
		return if Flux.isNode(n) then n:get() else n
	end)
	expect(reader:get() == 7, "baseline read")
	s.slot = 99
	expect(userNode:get() == 7 and Flux.isNode(userNode), "replaced key leaves user node untouched")
	expect(reader:get() == 99, "reader sees the replacement")
	Store.Destroy(s)
	expect(getmetatable(userNode) ~= nil and userNode:get() == 7, "store teardown spares the user node")

	local nodeA, nodeB = new(1), new(2)
	local s2 = Flux.store({ nodeA, nodeB })
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
	local calls = 0
	local fnA = function()
		calls += 1
		return "A"
	end
	local fnB = function()
		calls += 1
		return "B"
	end

	local s = Flux.store({ cb = fnA })
	local reader = new(function()
		return s.cb
	end)
	expect(reader:get() == fnA, "baseline read")
	s.cb = fnB
	expect(reader:get() == fnB, "newindex returns the new fn")

	local arr = Flux.store({ fnA, fnB })
	local first = new(function()
		return arr[1]
	end)
	expect(first:get() == fnA, "array baseline")
	Store.remove(arr, 1)
	expect(first:get() == fnB, "remove shift returns the fn raw")
	Store.insert(arr, 1, fnA)
	expect(first:get() == fnA, "insert shift returns the fn raw")
	Store.reconcile(s, { cb = fnA })
	expect(reader:get() == fnA, "reconcile swaps the fn leaf")
	expect(calls == 0, "stored fns never executed")
end)

test("store.reconcile · rejects non-store and non-table args", function()
	local s = Flux.store({ a = 1 })
	expect((pcall(Store.reconcile, {}, { a = 1 })) == false, "non-proxy target rejected")
	expect((pcall(Store.reconcile, s, 5 :: any)) == false, "non-table newData rejected")
end)

test("store · a raw table can be re-wrapped after its store's scope is destroyed", function()
	local raw = { hp = 100 }
	local s
	Flux.scope(function()
		s = Flux.store(raw)
	end):Destroy()
	local s2 = Flux.store(raw)
	expect(getmetatable(s2) ~= nil and s2 ~= s, "a fresh proxy over the same raw table")
	Store.Destroy(s2)
end)

test("store.reconcile · duplicate keys alias one element, with a warning", function()
	local s = Flux.store({ { id = 1, name = "a" } })
	local warnings = env.warnings(function()
		Store.reconcile(s, { { id = 1, name = "b" }, { id = 1, name = "c" } }, "id")
	end)
	expect(#warnings == 1 and string.find(warnings[1], "duplicate key", 1, true) ~= nil, "warned once")
	local raw = Store.unwrap(s)
	expect(raw[1] == raw[2], "duplicate keys collapse onto one reused element")
end)

test("store · a dropped unowned store is garbage collected", function()
	if not fullCollect() then
		return
	end
	local weak = setmetatable({}, { __mode = "v" })
	do
		local s = Flux.store({ hp = 100, nested = { mp = 50 }, list = { 1, 2 } })
		local c = new(function()
			return s.hp + s.nested.mp + #s.list
		end)
		expect(c:get() == 152, "the store is read through a computed")
		weak.store, weak.nested = s, s.nested
	end
	fullCollect()
	expect(weak.store == nil, "the root proxy was collected")
	expect(weak.nested == nil, "the nested proxy went with it")
end)

test("store · a live store keeps its nested proxies and their nodes across a collection", function()
	local s = Flux.store({ player = { hp = 100 } })
	local runs, last = 0, 0
	local e = Flux.effect(function()
		runs += 1
		last = s.player.hp
	end)
	flush()
	fullCollect()
	s.player.hp = 90
	flush()
	expect(runs == 2 and last == 90, "the write reaches the reader through the same nested node")
	e:Destroy()
	Store.Destroy(s)
end)

test("store · Store.Destroy tears down every proxy, and its readers stop depending on it", function()
	local s = Flux.store({ count = 1, nested = { mp = 50 } })
	local nested = s.nested
	local runs = 0
	local c = new(function()
		runs += 1
		return s.count + s.nested.mp + #s
	end)
	expect(c:get() == 51 and runs == 1, "the computed read three nodes")
	Store.Destroy(s)
	expect(getmetatable(s) == nil and getmetatable(nested) == nil, "the proxies are stripped")
	local before = runs
	expect(c:get() == 51 and runs == before, "the computed no longer depends on the store")
end)

test("store · Flux.dispose and Flux.cleanup tear the store down, not its elements", function()
	local a, b = Flux.signal(1), Flux.signal(2)
	local s = Flux.store({ a, b })
	local c = new(function()
		return s[1]:get() + #s
	end)
	expect(c:get() == 3, "the array store is read")
	Flux.dispose(s)
	expect(getmetatable(s) == nil, "dispose destroyed the store")
	expect(a:get() == 1 and b:get() == 2, "its node elements are untouched")
	Flux.dispose(s)
	expect(a:get() == 1, "a second dispose does not reach the elements either")

	local scoped
	local owner = Flux.scope(function()
		scoped = Flux.store({ a, b })
	end)
	local outer = Flux.store({ a })
	owner:Destroy()
	Flux.scope(function()
		Flux.cleanup(outer)
	end):Destroy()
	expect(getmetatable(scoped) == nil and getmetatable(outer) == nil, "cleanup(store) runs the same teardown")
	expect(a:get() == 1 and b:get() == 2, "the elements survive")
	a:Destroy()
	b:Destroy()
end)

test("store.reconcile · regression: elements past an array border survive", function()
	local s = Flux.store({ "a", "b" })
	Store.reconcile(s, { [2] = "c" })
	sert.eq(Store.unwrap(s), { [2] = "c" }, "the sparse [2] past the new border is kept")

	local keyed = Flux.store({ [1] = "s", [2] = { n = 1 } })
	local row = keyed[2]
	Store.reconcile(keyed, { [2] = { n = 1 }, [5] = 1 }, "id")
	expect(keyed[2] == row and Store.unwrap(keyed)[1] == nil, "keyed: [2] past the new border reconciles in place")

	local sparse = Flux.store({ [2] = { n = 1 } })
	local sparseRow = sparse[2]
	Store.reconcile(sparse, { 1, { n = 2 } }, "id")
	expect(sparse[2] == sparseRow and sparseRow.n == 2, "keyed: [2] past the old border reconciles in place")
end)

test("store.reconcile · regression: keyed rows without the key reconcile by position", function()
	local s = Flux.store({ { x = 1 } })
	local row = s[1]
	local runs = 0
	local reader = Flux.effect(function()
		runs += 1
		local _ = s[1].x
	end)
	flush()
	Store.reconcile(s, { { x = 1 } }, "id")
	flush()
	expect(s[1] == row and runs == 1, "an unchanged keyless row keeps its proxy and fires nothing")
	Store.reconcile(s, { { x = 2 } }, "id")
	flush()
	expect(s[1] == row and runs == 2 and row.x == 2, "a changed keyless row is updated in place")
	reader:Destroy()
end)

test("store.reconcile · regression: an identical unread row fires nothing", function()
	local s = Flux.store({ list = { { id = 1, v = 1 } } })
	local raw = Store.unwrap(s).list[1]
	local runs = 0
	local length = Flux.computed(function()
		runs += 1
		return #s.list
	end)
	expect(length:get() == 1 and runs == 1, "baseline")
	for _, keyed in { false, true } do
		Store.reconcile(s, { list = { { id = 1, v = 1 } } }, if keyed then "id" else nil)
		expect(length:get() == 1 and runs == 1, `no length re-run (keyed: {keyed})`)
	end
	Store.reconcile(s, { list = { { id = 1, v = 2 } } })
	expect(Store.unwrap(s).list[1] == raw and raw.v == 2, "the unread row is updated in place")
	length:Destroy()
end)

test("store · a cleared key keeps serving its readers, observed or not", function()
	local s = Flux.store({ a = 1, b = 1, c = 1 })
	local reader = Flux.computed(function()
		return (s.a or 0) + (s.b or 0) + (s.c or 0)
	end)
	expect(reader:get() == 3, "a read makes per-key nodes")
	reader:Destroy()
	s.a = nil

	local runs, last = 0, nil
	local watcher = Flux.effect(function()
		runs += 1
		last = s.b
	end)
	flush()
	s.b = nil
	flush()
	expect(last == nil and runs == 2, "an observed key's reader sees the clear")

	local writer = Flux.effect(function()
		if s.c ~= nil then
			s.c = nil
		end
	end)
	flush()
	s.c = 5
	flush()
	expect(s.c == nil, "the run still tracks the key it cleared, and clears it again")

	s.a = 2
	local again = Flux.computed(function()
		return s.a
	end)
	expect(again:get() == 2, "a dropped key is read through a fresh node")
	s.a = 3
	expect(again:get() == 3, "which tracks writes")
	watcher:Destroy()
	writer:Destroy()
	again:Destroy()
end)

-- Store model property ------------------------------------------------------------------------------------------------

local ROOT_KEYS = { "a", "b", 1, 2, 5 }
local READ_SPECS = {
	{ path = {} },
	{ path = { "a" } },
	{ path = { "b" } },
	{ path = { 2 } },
	{ path = { 5 } },
	{ path = { "a", "x" } },
	{ path = { "b", "y" } },
	{ path = { "list" } },
	{ path = { "list" }, len = true },
	{ path = { "list", 1 } },
	{ path = { "list", 2, "v" } },
	{ path = { "list", 3 } },
	{ path = { "list", 1, "v" } },
	{ path = { "list", 3, "v" } },
}
local MOVES_TABLES = {
	alias = true,
	insert = true,
	remove = true,
	move = true,
	aliasRow = true,
	reconcileList = true,
	reconcileRoot = true,
}

local function plain(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, item in value do
		out[key] = plain(item)
	end
	return out
end

local function readSpec(root: any, spec: any): any
	local value = root
	for _, key in spec.path do
		if type(value) ~= "table" then
			value = nil
			break
		end
		value = value[key]
	end
	if spec.len then
		return if type(value) == "table" then #value else nil
	end
	return plain(value)
end

local function readSet(root: any, spec: any): { [any]: { [any]: boolean } }
	local set = {}
	local function mark(t: any, key: any)
		local keys = set[t] or {}
		keys[key] = true
		set[t] = keys
	end
	local value = root
	for _, key in spec.path do
		if type(value) ~= "table" then
			return set
		end
		mark(value, key)
		value = value[key]
	end
	local function deep(t: any)
		if type(t) == "table" then
			mark(t, "*")
			if not spec.len then
				for _, item in t do
					deep(item)
				end
			end
		end
	end
	deep(value)
	return set
end

local function reachable(root: any): ({ [any]: boolean }, boolean)
	local seen, aliased = {}, false
	local function visit(t: any)
		if seen[t] then
			aliased = true
			return
		end
		seen[t] = true
		for _, item in t do
			if type(item) == "table" then
				visit(item)
			end
		end
	end
	visit(root)
	return seen, aliased
end

local function hasAlias(root: any): boolean
	return (select(2, reachable(root)))
end

local function show(value: any): string
	if type(value) ~= "table" then
		return if type(value) == "string" then `"{value}"` else tostring(value)
	end
	local keys = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, key in keys do
		table.insert(parts, `{key}={show(value[key])}`)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function genField(g): number?
	local n = g:int(0, 2)
	return if n == 0 then nil else n
end

local function genRootValue(g): any
	local kind = g:weighted({ { 2, "nil" }, { 3, "scalar" }, { 3, "record" } })
	if kind == "nil" then
		return nil
	elseif kind == "scalar" then
		return g:pick({ 1, 2, "s" })
	end
	return { x = genField(g), y = genField(g) }
end

local function genList(g, current: { any }?, nextId: () -> number): { any }
	local pool = if current then table.clone(current) else {}
	local out = {}
	for _ = 1, g:int(0, math.min(4, g.size + 1)) do
		if #pool > 0 and g:bool(0.7) then
			local row = table.remove(pool, g:int(1, #pool))
			table.insert(out, { id = row.id, v = if g:bool() then row.v else g:int(1, 3) })
		else
			table.insert(out, { id = nextId(), v = g:int(1, 3) })
		end
	end
	return out
end

sert.prop("store · random writes, array ops and reconciles match a plain-table mirror", function(g)
	Model.isolated(function(owners)
		local small = g.size <= 3
		local idCounter = 0
		local function nextId(): number
			idCounter += 1
			return idCounter
		end

		local initial: { [any]: any } = {
			a = { x = 1 },
			[1] = "s",
			list = { { id = nextId(), v = 1 }, { id = nextId(), v = 2 }, { id = nextId(), v = 1 } },
		}
		local mirror = plain(initial)
		local store
		local inScope = g:bool()
		if inScope then
			table.insert(owners, (Flux.scope(function()
				store = Flux.store(plain(initial))
			end)))
		else
			store = Flux.store(plain(initial))
		end
		local rawRoot = Store.unwrap(store)
		local readerScope = Flux.scope(function() end)
		table.insert(owners, readerScope)

		local proxies: { [any]: any } = {}
		local function capture(value: any)
			if type(value) == "table" and getmetatable(value) ~= nil then
				local raw = Store.unwrap(value)
				local known = proxies[raw]
				sert(known == nil or known == value, "a reachable raw table kept its proxy")
				proxies[raw] = value
			end
		end
		local function walkStore(path: { any }): any
			local value = store
			for _, key in path do
				if type(value) ~= "table" then
					return nil
				end
				value = value[key]
				capture(value)
			end
			return value
		end

		local readers = {}
		local function checkState(where: string)
			sert.eq(Store.unwrap(store), mirror, `{where}: raw table matches the mirror`)
			local live = reachable(rawRoot)
			for raw, proxy in proxies do
				if live[raw] then
					sert(getmetatable(proxy) ~= nil, `{where}: a reachable table's proxy is live ({show(raw)})`)
				else
					sert(getmetatable(proxy) == nil, `{where}: a displaced table's proxy is torn down ({show(raw)})`)
					proxies[raw] = nil
				end
			end
		end
		local touched: { { any } } = {}
		local dirtyAll = false
		local function leafWrite(t: any, key: any, new: any)
			if t[key] ~= new then
				table.insert(touched, { t, key })
			end
			t[key] = new
		end
		local function checkReaders(where: string)
			for _, reader in readers do
				local seen = if reader.effect then reader.value else reader.node:get()
				sert.eq(
					seen,
					readSpec(mirror, reader.spec),
					`{where}: reader of {show(reader.spec)} (effect: {reader.effect})`
				)
				local set = reader.set
				if set and not dirtyAll then
					local hit = false
					for _, write in touched do
						local keys = set[write[1]]
						hit = hit or (keys ~= nil and (keys[write[2]] or keys["*"]) ~= nil)
					end
					if not hit then
						sert.eq(
							reader.runs,
							reader.checkedRuns,
							`{where}: no write reached {show(reader.spec)}, no re-run`
						)
					end
				end
			end
			for _, reader in readers do
				reader.set, reader.checkedRuns = readSet(mirror, reader.spec), reader.runs
			end
			table.clear(touched)
			dirtyAll = false
		end
		local function settle(): { number }
			Flux.flush()
			local counts = {}
			for index, reader in readers do
				if not reader.effect then
					reader.node:get()
				end
				counts[index] = reader.runs
			end
			return counts
		end
		local function listOf(): ({ any }?, any)
			local list = mirror.list
			if type(list) == "table" then
				return list, walkStore({ "list" })
			end
			return nil, nil
		end

		for _, op in
			Model.ops(g, {
				{ 3, "setRoot" },
				{ 3, "setField" },
				{ 1, "alias" },
				{ 3, "insert" },
				{ 3, "remove" },
				{ 2, "move" },
				{ 2, "setRow" },
				{ 1, "aliasRow" },
				{ 1, "badPos" },
				{ 2, "reconcileList" },
				{ if small then 0 else 2, "reconcileRoot" },
				{ 1, "reconcileSame" },
				{ 2, "reconcileLeaf" },
				{ 3, "reader" },
				{ 1, "dropReader" },
				{ 5, "flush" },
			})
		do
			dirtyAll = dirtyAll or MOVES_TABLES[op] == true
			if op == "setRoot" then
				local key = g:pick({ "a", "b", 1, 2, 5, "list" })
				local value = if key == "list"
					then (if g:bool(0.8) then genList(g, nil, nextId) else nil)
					else genRootValue(g)
				g:note("store[%s] = %s", show(key), show(value))
				store[key] = plain(value)
				if type(value) == "table" or type(mirror[key]) == "table" then
					dirtyAll = true
					mirror[key] = plain(value)
				else
					leafWrite(mirror, key, value)
				end
			elseif op == "setField" then
				local key = g:pick(ROOT_KEYS)
				local field, value = g:pick({ "x", "y" }), genField(g)
				local viaIteration = g:bool()
				if type(mirror[key]) == "table" then
					g:note(
						"store[%s].%s = %s%s",
						show(key),
						field,
						show(value),
						if viaIteration then " (iterated)" else ""
					)
					local proxy
					if viaIteration then
						for k, item in store do
							if k == key then
								proxy = item
							end
						end
					else
						proxy = store[key]
					end
					capture(proxy)
					proxy[field] = value
					leafWrite(mirror[key], field, value)
				end
			elseif op == "alias" then
				local from, to = g:pick(ROOT_KEYS), g:pick(ROOT_KEYS)
				if from ~= to and type(mirror[from]) == "table" then
					g:note("store[%s] = store[%s]", show(to), show(from))
					store[to] = walkStore({ from })
					mirror[to] = mirror[from]
				end
			elseif op == "insert" then
				local list, proxy = listOf()
				if list then
					local how = g:pick({ "append", "past the end", "at" })
					local pos = g:int(1, #list + 1)
					local row = { id = nextId(), v = g:int(1, 3) }
					if how == "append" then
						g:note("Store.insert(list, %s)", show(row))
						Store.insert(proxy, plain(row))
						table.insert(list, row)
					elseif how == "past the end" then
						g:note("list[%d] = %s", #list + 1, show(row))
						proxy[#list + 1] = plain(row)
						table.insert(list, row)
					else
						g:note("Store.insert(list, %d, %s)", pos, show(row))
						Store.insert(proxy, pos, plain(row))
						table.insert(list, pos, row)
					end
				end
			elseif op == "remove" then
				local list, proxy = listOf()
				if list then
					local pos = if g:bool() and #list > 0 then g:int(1, #list) else nil
					g:note("Store.remove(list, %s)", show(pos))
					sert.eq(
						Store.remove(proxy, pos),
						table.remove(list, pos),
						"Store.remove returns the removed element"
					)
				end
			elseif op == "move" then
				local list, proxy = listOf()
				if list and #list > 0 then
					local from, to = g:int(1, #list), g:int(1, #list)
					g:note("Store.move(list, %d, %d)", from, to)
					Store.move(proxy, from, to)
					table.insert(list, to, table.remove(list, from))
				end
			elseif op == "setRow" then
				local list = listOf()
				if list and #list > 0 then
					local index, value = g:int(1, #list), g:int(1, 3)
					g:note("list[%d].v = %d", index, value)
					walkStore({ "list", index }).v = value
					leafWrite(list[index], "v", value)
				end
			elseif op == "aliasRow" then
				local list, proxy = listOf()
				if list and #list > 1 then
					local from, to = g:int(1, #list), g:int(1, #list)
					if from ~= to then
						g:note("list[%d] = list[%d]", to, from)
						proxy[to] = walkStore({ "list", from })
						list[to] = list[from]
					end
				end
			elseif op == "badPos" then
				local list, proxy = listOf()
				if list then
					local n = #list
					local kind = g:pick({ "insert", "remove", "move" })
					local bad = g:pick({ 0, n + 2, 1.5, "1" })
					g:note("Store.%s(list, bad %s)", kind, show(bad))
					local beyond = if bad == n + 2 then n + 1 else bad
					local ok
					if kind == "insert" then
						ok = pcall(Store.insert, proxy, bad, { id = 0, v = 0 })
					elseif kind == "remove" then
						ok = pcall(Store.remove, proxy, beyond)
					else
						ok = pcall(Store.move, proxy, if n > 0 then 1 else bad, beyond)
					end
					sert(not ok, `Store.{kind} rejects position {show(bad)}`)
				end
			elseif op == "reconcileLeaf" then
				local keyed = g:bool()
				local leaves = {}
				for _, key in ROOT_KEYS do
					local value = mirror[key]
					if type(value) == "table" then
						table.insert(leaves, { value, g:pick({ "x", "y" }) })
					else
						table.insert(leaves, { mirror, key })
					end
				end
				local list = listOf()
				if list and #list > 0 then
					table.insert(leaves, { list[g:int(1, #list)], "v" })
				end
				local leaf = g:pick(leaves)
				local value = g:int(1, 3)
				if not hasAlias(mirror) then
					leafWrite(leaf[1], leaf[2], value)
					g:note(
						"Store.reconcile(store, <mirror with %s = %d>%s)",
						show(leaf[2]),
						value,
						if keyed then ', "id"' else ""
					)
					Store.reconcile(store, plain(mirror), if keyed then "id" else nil)
				end
			elseif op == "reconcileList" or op == "reconcileRoot" or op == "reconcileSame" then
				local keyed = g:bool()
				local list = listOf()
				if not hasAlias(mirror) and (op ~= "reconcileList" or list) then
					local snapshot
					if op == "reconcileSame" then
						snapshot = plain(mirror)
					elseif op == "reconcileList" then
						snapshot = genList(g, list, nextId)
					else
						snapshot = {}
						for _, key in ROOT_KEYS do
							local current = mirror[key]
							if g:bool(0.6) then
								snapshot[key] = plain(current)
								if type(current) == "table" and g:bool() then
									snapshot[key][g:pick({ "x", "y" })] = genField(g)
								end
							else
								snapshot[key] = genRootValue(g)
							end
						end
						snapshot.list = if g:bool(0.9) then genList(g, list, nextId) else g:pick({ 1, "s" })
					end
					g:note(
						"Store.reconcile(%s, %s%s)",
						if op == "reconcileList" then "list" else "store",
						show(snapshot),
						if keyed then ', "id"' else ""
					)

					local before, rows, counts = {}, {}, nil
					local function remember(path: { any })
						local value = walkStore(path)
						if type(value) == "table" then
							before[show(path)] = value
						end
					end
					if op == "reconcileSame" then
						counts = settle()
					else
						if op == "reconcileRoot" then
							for _, key in ROOT_KEYS do
								remember({ key })
							end
							remember({ "list" })
						end
						for index, row in list or {} do
							rows[row.id] = walkStore({ "list", index })
							remember({ "list", index })
						end
					end

					local target = if op == "reconcileList" then walkStore({ "list" }) else store
					local result = Store.reconcile(target, plain(snapshot), if keyed then "id" else nil)
					sert(result == target, "returns proxy")
					if op == "reconcileList" then
						mirror.list = snapshot
					elseif op == "reconcileRoot" then
						mirror = snapshot
					end

					if op == "reconcileRoot" then
						for _, key in ROOT_KEYS do
							local old = before[show({ key })]
							if old and type(mirror[key]) == "table" then
								sert(
									walkStore({ key }) == old,
									`store[{show(key)}] kept its proxy across the reconcile`
								)
							end
						end
					end
					local newList = mirror.list
					if type(newList) == "table" and (op == "reconcileList" or before[show({ "list" })]) then
						for index, row in newList do
							local old = if keyed then rows[row.id] else before[show({ "list", index })]
							if old then
								sert(
									walkStore({ "list", index }) == old,
									`list[{index}] kept its proxy (keyed: {keyed})`
								)
							end
						end
					end
					if counts then
						sert.eq(settle(), counts, "a reconcile that changes nothing runs no reader")
					end
				end
			elseif op == "reader" then
				local spec = g:pick(READ_SPECS)
				local isEffect = g:bool()
				g:note("reader %s (effect: %s)", show(spec), tostring(isEffect))
				local reader = Model.reader(readerScope, isEffect, function()
					return readSpec(store, spec)
				end)
				reader.spec = spec
				table.insert(readers, reader)
			elseif op == "dropReader" then
				if #readers > 0 then
					local index = g:int(1, #readers)
					g:note("drop reader %d", index)
					table.remove(readers, index).node:Destroy()
				end
			else
				g:note("flush")
				Flux.flush()
				checkReaders("after flush")
			end
			checkState(op)
		end

		Flux.flush()
		checkReaders("at the end")

		local how = g:pick({ "Store.Destroy", "Flux.dispose", "scope" })
		g:note("teardown: %s", how)
		if how == "scope" and inScope then
			owners[1]:Destroy()
		elseif how == "Flux.dispose" then
			Flux.dispose(store)
		else
			Store.Destroy(store)
		end
		sert(getmetatable(store) == nil, "the root proxy is stripped")
		for raw, proxy in proxies do
			sert(getmetatable(proxy) == nil, `every nested proxy is torn down ({show(raw)})`)
		end
		sert.eq(rawRoot, mirror, "teardown leaves the raw table intact")
	end)
end, {
	runs = 200,
	size = 30,
	exhaustive = { size = 1 },
	regressions = { 894361127 },
})

return {}
