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

local function nextStateId(state: any): number
	state.idCounter += 1
	return state.idCounter
end

local function captureProxy(sut: any, value: any)
	if type(value) == "table" and getmetatable(value) ~= nil then
		local raw = Store.unwrap(value)
		local known = sut.proxies[raw]
		sert(known == nil or known == value, "a reachable raw table kept its proxy")
		sut.proxies[raw] = value
	end
end

local function walkStore(sut: any, path: { any }): any
	local value = sut.store
	for _, key in path do
		if type(value) ~= "table" then
			return nil
		end
		value = value[key]
		captureProxy(sut, value)
	end
	return value
end

local function leafWrite(state: any, t: any, key: any, new: any)
	if t[key] ~= new then
		table.insert(state.touched, { t, key })
	end
	t[key] = new
end

local function checkReaders(state: any, sut: any, where: string)
	for _, reader in sut.readers do
		local seen = if reader.effect then reader.value else reader.node:get()
		sert.eq(
			seen,
			readSpec(state.mirror, reader.spec),
			`{where}: reader of {show(reader.spec)} (effect: {reader.effect})`
		)
		local set = reader.set
		if set and not state.dirtyAll then
			local hit = false
			for _, write in state.touched do
				local keys = set[write[1]]
				hit = hit or (keys ~= nil and (keys[write[2]] or keys["*"]) ~= nil)
			end
			if not hit then
				sert.eq(reader.runs, reader.checkedRuns, `{where}: no write reached {show(reader.spec)}, no re-run`)
			end
		end
	end
	for _, reader in sut.readers do
		reader.set, reader.checkedRuns = readSet(state.mirror, reader.spec), reader.runs
	end
	table.clear(state.touched)
	state.dirtyAll = false
end

local function settleReaders(sut: any): { number }
	Flux.flush()
	local counts = {}
	for index, reader in sut.readers do
		if not reader.effect then
			reader.node:get()
		end
		counts[index] = reader.runs
	end
	return counts
end

local function listOf(state: any, sut: any): ({ any }?, any)
	local list = state.mirror.list
	if type(list) == "table" then
		return list, walkStore(sut, { "list" })
	end
	return nil, nil
end

local function runReconcileStep(op: string, state: any, sut: any, arg: { keyed: boolean, snapshot: any })
	local keyed = arg.keyed
	local list = listOf(state, sut)
	if hasAlias(state.mirror) or (op == "reconcileList" and not list) then
		return
	end
	local snapshot = if op == "reconcileSame" then plain(state.mirror) else plain(arg.snapshot)
	local before, rows, counts = {}, {}, nil
	local function remember(path: { any })
		local value = walkStore(sut, path)
		if type(value) == "table" then
			before[show(path)] = value
		end
	end
	if op == "reconcileSame" then
		counts = settleReaders(sut)
	else
		if op == "reconcileRoot" then
			for _, key in ROOT_KEYS do
				remember({ key })
			end
			remember({ "list" })
		end
		for index, row in list or {} do
			rows[row.id] = walkStore(sut, { "list", index })
			remember({ "list", index })
		end
	end

	local target = if op == "reconcileList" then walkStore(sut, { "list" }) else sut.store
	local result = Store.reconcile(target, plain(snapshot), if keyed then "id" else nil)
	sert(result == target, "returns proxy")
	if op == "reconcileList" then
		state.mirror.list = snapshot
	elseif op == "reconcileRoot" then
		state.mirror = snapshot
	end

	if op == "reconcileRoot" then
		for _, key in ROOT_KEYS do
			local old = before[show({ key })]
			if old and type(state.mirror[key]) == "table" then
				sert(walkStore(sut, { key }) == old, `store[{show(key)}] kept its proxy across the reconcile`)
			end
		end
	end
	local newList = state.mirror.list
	if type(newList) == "table" and (op == "reconcileList" or before[show({ "list" })]) then
		for index, row in newList do
			local old = if keyed then rows[row.id] else before[show({ "list", index })]
			if old then
				sert(walkStore(sut, { "list", index }) == old, `list[{index}] kept its proxy (keyed: {keyed})`)
			end
		end
	end
	if counts then
		sert.eq(settleReaders(sut), counts, "a reconcile that changes nothing runs no reader")
	end
end

local storeModelSpec = {
	init = function()
		local state: any = {
			idCounter = 0,
			mirror = nil,
			touched = {},
			dirtyAll = false,
			teardownHow = "Store.Destroy",
		}
		local initial: { [any]: any } = {
			a = { x = 1 },
			[1] = "s",
			list = {
				{ id = nextStateId(state), v = 1 },
				{ id = nextStateId(state), v = 2 },
				{ id = nextStateId(state), v = 1 },
			},
		}
		state.mirror = plain(initial)
		local store
		local storeScope = Flux.scope(function()
			store = Flux.store(plain(initial))
		end)
		local rawRoot = Store.unwrap(store)
		local readerScope = Flux.scope(function() end)
		local sut = {
			store = store,
			storeScope = storeScope,
			rawRoot = rawRoot,
			readerScope = readerScope,
			proxies = {} :: { [any]: any },
			readers = {},
		}
		return state, sut
	end,
	teardown = function(sut, state)
		local checkOk, checkErr = pcall(function()
			Flux.flush()
			checkReaders(state, sut, "at the end")
		end)
		local how = state.teardownHow
		if how == "scope" then
			sut.storeScope:Destroy()
		elseif how == "Flux.dispose" then
			Flux.dispose(sut.store)
		else
			Store.Destroy(sut.store)
		end
		sut.readerScope:Destroy()
		sut.storeScope:Destroy()
		Flux.flush()
		if not checkOk then
			error(checkErr, 0)
		end
		sert(getmetatable(sut.store) == nil, "the root proxy is stripped")
		for raw, proxy in sut.proxies do
			sert(getmetatable(proxy) == nil, `every nested proxy is torn down ({show(raw)})`)
		end
		sert.eq(sut.rawRoot, state.mirror, "teardown leaves the raw table intact")
	end,
	actions = {
		setRoot = {
			weight = 3,
			gen = function(g, state)
				local key = g:pick({ "a", "b", 1, 2, 5, "list" })
				local value = if key == "list"
					then (if g:bool(0.8)
						then genList(g, nil, function()
							return nextStateId(state)
						end)
						else nil)
					else genRootValue(g)
				return { key = key, value = value }
			end,
			run = function(sut, arg)
				sut.store[arg.key] = plain(arg.value)
			end,
			next = function(state, arg)
				state.teardownHow = arg.teardownHow or state.teardownHow
				if type(arg.value) == "table" or type(state.mirror[arg.key]) == "table" then
					state.dirtyAll = true
					state.mirror[arg.key] = plain(arg.value)
				else
					leafWrite(state, state.mirror, arg.key, arg.value)
				end
			end,
		},
		setField = {
			weight = 3,
			gen = function(g)
				return {
					key = g:pick(ROOT_KEYS),
					field = g:pick({ "x", "y" }),
					value = genField(g),
					viaIteration = g:bool(),
				}
			end,
			run = function(sut, arg, state)
				if type(state.mirror[arg.key]) == "table" then
					local proxy
					if arg.viaIteration then
						for k, item in sut.store do
							if k == arg.key then
								proxy = item
							end
						end
					else
						proxy = sut.store[arg.key]
					end
					captureProxy(sut, proxy)
					proxy[arg.field] = arg.value
				end
			end,
			next = function(state, arg)
				if type(state.mirror[arg.key]) == "table" then
					leafWrite(state, state.mirror[arg.key], arg.field, arg.value)
				end
			end,
		},
		alias = {
			weight = 1,
			gen = function(g)
				return { from = g:pick(ROOT_KEYS), to = g:pick(ROOT_KEYS) }
			end,
			run = function(sut, arg, state)
				if arg.from ~= arg.to and type(state.mirror[arg.from]) == "table" then
					sut.store[arg.to] = walkStore(sut, { arg.from })
				end
			end,
			next = function(state, arg)
				state.dirtyAll = true
				if arg.from ~= arg.to and type(state.mirror[arg.from]) == "table" then
					state.mirror[arg.to] = state.mirror[arg.from]
				end
			end,
		},
		insert = {
			weight = 3,
			gen = function(g, state)
				local list = if type(state.mirror.list) == "table" then state.mirror.list else nil
				local how = g:pick({ "append", "past the end", "at" })
				local pos = if list then g:int(1, #list + 1) else 1
				local row = { id = nextStateId(state), v = g:int(1, 3) }
				return { how = how, pos = pos, row = row }
			end,
			run = function(sut, arg, state)
				local list, proxy = listOf(state, sut)
				if list then
					local pos = math.clamp(arg.pos, 1, #list + 1)
					if arg.how == "append" then
						Store.insert(proxy, plain(arg.row))
					elseif arg.how == "past the end" then
						proxy[#list + 1] = plain(arg.row)
					else
						Store.insert(proxy, pos, plain(arg.row))
					end
				end
			end,
			next = function(state, arg)
				state.dirtyAll = true
				local list = state.mirror.list
				if type(list) == "table" then
					local pos = math.clamp(arg.pos, 1, #list + 1)
					local row = plain(arg.row)
					if arg.how == "append" or arg.how == "past the end" then
						table.insert(list, row)
					else
						table.insert(list, pos, row)
					end
				end
			end,
		},
		remove = {
			weight = 3,
			gen = function(g, state)
				local list = if type(state.mirror.list) == "table" then state.mirror.list else nil
				local pos = if g:bool() and list and #list > 0 then g:int(1, #list) else nil
				return pos
			end,
			run = function(sut, pos, state)
				local list, proxy = listOf(state, sut)
				if list then
					local validPos = if pos ~= nil and pos >= 1 and pos <= #list then pos else nil
					return { removed = Store.remove(proxy, validPos), validPos = validPos, hadList = true }
				end
				return { hadList = false }
			end,
			post = function(state, _pos, res)
				if res.hadList then
					local list = state.mirror.list
					local expected = list[res.validPos or #list]
					sert.eq(res.removed, expected, "Store.remove returns the removed element")
				end
			end,
			next = function(state, _pos, res)
				state.dirtyAll = true
				if res.hadList then
					table.remove(state.mirror.list, res.validPos)
				end
			end,
		},
		move = {
			weight = 2,
			gen = function(g, state)
				local list = if type(state.mirror.list) == "table" then state.mirror.list else nil
				local n = if list and #list > 0 then #list else 1
				return { from = g:int(1, n), to = g:int(1, n) }
			end,
			run = function(sut, arg, state)
				local list, proxy = listOf(state, sut)
				if list and #list > 0 then
					local from, to = math.clamp(arg.from, 1, #list), math.clamp(arg.to, 1, #list)
					Store.move(proxy, from, to)
				end
			end,
			next = function(state, arg)
				state.dirtyAll = true
				local list = state.mirror.list
				if type(list) == "table" and #list > 0 then
					local from, to = math.clamp(arg.from, 1, #list), math.clamp(arg.to, 1, #list)
					table.insert(list, to, table.remove(list, from))
				end
			end,
		},
		setRow = {
			weight = 2,
			gen = function(g, state)
				local list = if type(state.mirror.list) == "table" then state.mirror.list else nil
				local n = if list and #list > 0 then #list else 1
				return { index = g:int(1, n), value = g:int(1, 3) }
			end,
			run = function(sut, arg, state)
				local list = listOf(state, sut)
				if list and #list > 0 then
					local index = math.clamp(arg.index, 1, #list)
					walkStore(sut, { "list", index }).v = arg.value
				end
			end,
			next = function(state, arg)
				local list = state.mirror.list
				if type(list) == "table" and #list > 0 then
					local index = math.clamp(arg.index, 1, #list)
					leafWrite(state, list[index], "v", arg.value)
				end
			end,
		},
		aliasRow = {
			weight = 1,
			gen = function(g, state)
				local list = if type(state.mirror.list) == "table" then state.mirror.list else nil
				local n = if list and #list > 1 then #list else 2
				return { from = g:int(1, n), to = g:int(1, n) }
			end,
			run = function(sut, arg, state)
				local list, proxy = listOf(state, sut)
				if list and #list > 1 then
					local from, to = math.clamp(arg.from, 1, #list), math.clamp(arg.to, 1, #list)
					if from ~= to then
						proxy[to] = walkStore(sut, { "list", from })
					end
				end
			end,
			next = function(state, arg)
				state.dirtyAll = true
				local list = state.mirror.list
				if type(list) == "table" and #list > 1 then
					local from, to = math.clamp(arg.from, 1, #list), math.clamp(arg.to, 1, #list)
					if from ~= to then
						list[to] = list[from]
					end
				end
			end,
		},
		badPos = {
			weight = 1,
			gen = function(g, state)
				local list = if type(state.mirror.list) == "table" then state.mirror.list else nil
				local n = if list then #list else 0
				return {
					kind = g:pick({ "insert", "remove", "move" }),
					bad = g:pick({ 0, n + 2, 1.5, "1" }),
				}
			end,
			run = function(sut, arg, state)
				local list, proxy = listOf(state, sut)
				if list then
					local n = #list
					local bad = if type(arg.bad) == "number" and arg.bad > 1.5 then n + 2 else arg.bad
					local beyond = if bad == n + 2 then n + 1 else bad
					local ok
					if arg.kind == "insert" then
						ok = pcall(Store.insert, proxy, bad, { id = 0, v = 0 })
					elseif arg.kind == "remove" then
						ok = pcall(Store.remove, proxy, beyond)
					else
						ok = pcall(Store.move, proxy, if n > 0 then 1 else bad, beyond)
					end
					sert(not ok, `Store.{arg.kind} rejects position {show(bad)}`)
				end
			end,
		},
		reconcileLeaf = {
			weight = 2,
			gen = function(g, state)
				local keyed = g:bool()
				local choices: { any } = {}
				for _, key in ROOT_KEYS do
					if type(state.mirror[key]) == "table" then
						table.insert(choices, { kind = "nested", key = key, field = g:pick({ "x", "y" }) })
					else
						table.insert(choices, { kind = "root", key = key })
					end
				end
				if type(state.mirror.list) == "table" and #state.mirror.list > 0 then
					table.insert(choices, { kind = "row", index = g:int(1, #state.mirror.list) })
				end
				return { keyed = keyed, target = g:pick(choices), value = g:int(1, 3) }
			end,
			run = function(sut, arg, state)
				if not hasAlias(state.mirror) then
					local target = arg.target
					if target.kind == "nested" and type(state.mirror[target.key]) == "table" then
						leafWrite(state, state.mirror[target.key], target.field, arg.value)
					elseif target.kind == "row" and type(state.mirror.list) == "table" and #state.mirror.list > 0 then
						local idx = math.clamp(target.index, 1, #state.mirror.list)
						leafWrite(state, state.mirror.list[idx], "v", arg.value)
					elseif target.kind == "root" and type(state.mirror[target.key]) ~= "table" then
						leafWrite(state, state.mirror, target.key, arg.value)
					end
					Store.reconcile(sut.store, plain(state.mirror), if arg.keyed then "id" else nil)
				end
			end,
		},
		reconcileList = {
			weight = 2,
			gen = function(g, state)
				local list = if type(state.mirror.list) == "table" then state.mirror.list else nil
				return {
					keyed = g:bool(),
					snapshot = genList(g, list, function()
						return nextStateId(state)
					end),
				}
			end,
			run = function(sut, arg, state)
				state.dirtyAll = true
				runReconcileStep("reconcileList", state, sut, arg)
			end,
		},
		reconcileRoot = {
			weight = 2,
			gen = function(g, state)
				local keyed = g:bool()
				if g.size <= 3 then
					local snapshot = plain(state.mirror)
					snapshot.a = genRootValue(g)
					return { keyed = keyed, snapshot = snapshot }
				end
				local list = if type(state.mirror.list) == "table" then state.mirror.list else nil
				local snapshot = {}
				for _, key in ROOT_KEYS do
					local current = state.mirror[key]
					if g:bool(0.6) then
						snapshot[key] = plain(current)
						if type(current) == "table" and g:bool() then
							snapshot[key][g:pick({ "x", "y" })] = genField(g)
						end
					else
						snapshot[key] = genRootValue(g)
					end
				end
				snapshot.list = if g:bool(0.9)
					then genList(g, list, function()
						return nextStateId(state)
					end)
					else g:pick({ 1, "s" })
				return { keyed = keyed, snapshot = snapshot }
			end,
			run = function(sut, arg, state)
				state.dirtyAll = true
				runReconcileStep("reconcileRoot", state, sut, arg)
			end,
		},
		reconcileSame = {
			weight = 1,
			gen = function(g)
				return { keyed = g:bool(), snapshot = nil }
			end,
			run = function(sut, arg, state)
				runReconcileStep("reconcileSame", state, sut, arg)
			end,
		},
		reader = {
			weight = 3,
			gen = function(g)
				return { spec = g:pick(READ_SPECS), isEffect = g:bool() }
			end,
			run = function(sut, arg)
				local reader = Model.reader(sut.readerScope, arg.isEffect, function()
					return readSpec(sut.store, arg.spec)
				end)
				reader.spec = arg.spec
				table.insert(sut.readers, reader)
			end,
		},
		dropReader = {
			weight = 1,
			gen = function(g)
				return g:int(1, 8)
			end,
			run = function(sut, index)
				if #sut.readers > 0 then
					local i = math.clamp(index, 1, #sut.readers)
					table.remove(sut.readers, i).node:Destroy()
				end
			end,
		},
		flush = {
			weight = 5,
			run = function(sut, _arg, state)
				Flux.flush()
				checkReaders(state, sut, "after flush")
			end,
		},
	},
	never = {
		rootProxyStrippedEarly = function(_state, sut)
			return getmetatable(sut.store) == nil
		end,
		liveProxyTornDown = function(_state, sut)
			local live = reachable(sut.rawRoot)
			for raw, proxy in sut.proxies do
				if live[raw] and getmetatable(proxy) == nil then
					return true
				end
			end
			return false
		end,
		deadProxyLeaked = function(_state, sut)
			local live = reachable(sut.rawRoot)
			for raw, proxy in sut.proxies do
				if not live[raw] and getmetatable(proxy) ~= nil then
					return true
				end
			end
			return false
		end,
	},
	invariants = {
		rawMatchesMirror = function(state, sut)
			sert.eq(Store.unwrap(sut.store), state.mirror, "raw table matches the mirror")
		end,
		proxiesConsistent = function(_state, sut)
			local live = reachable(sut.rawRoot)
			for raw, proxy in sut.proxies do
				if live[raw] then
					sert(getmetatable(proxy) ~= nil, `a reachable table's proxy is live ({show(raw)})`)
				else
					sert(getmetatable(proxy) == nil, `a displaced table's proxy is torn down ({show(raw)})`)
					sut.proxies[raw] = nil
				end
			end
		end,
	},
}

sert.model("store · random writes, array ops and reconciles match a plain-table mirror", storeModelSpec, {
	runs = 200,
	length = 30,
	exhaustive = { size = 1 },
	regressions = { 894361127 },
})

test("store · model replay covers nested writes, array ops, reconciles and readers", function()
	local state, sut = sert.model.replay(storeModelSpec, {
		{ "reader", { spec = { path = { "a", "x" } }, isEffect = false } },
		{ "reader", { spec = { path = { "list" }, len = true }, isEffect = true } },
		{ "flush" },
		{ "setField", { key = "a", field = "x", value = 2, viaIteration = false } },
		{ "flush" },
		{ "insert", { how = "append", pos = 4, row = { id = 10, v = 3 } } },
		{ "move", { from = 1, to = 3 } },
		{ "setRow", { index = 2, value = 1 } },
		{ "reconcileSame", { keyed = true } },
		{ "reconcileLeaf", { keyed = true, target = { kind = "nested", key = "a", field = "x" }, value = 3 } },
		{ "reconcileList", { keyed = true, snapshot = { { id = 2, v = 2 }, { id = 10, v = 3 } } } },
		{ "remove", 1 },
		{ "setRoot", { key = "b", value = { x = 1, y = 2 }, teardownHow = "Flux.dispose" } },
		{ "flush" },
		{ "dropReader", 1 },
	})
	expect(state.mirror.a.x == 3 and #state.mirror.list == 1 and getmetatable(sut.store) == nil)
end)

sert.laws.differential("store · nested proxy mutations, array ops and reconciles match pure functional oracle", {
	gen = sert.gen.list(
		sert.gen.record({
			op = sert.gen.pick({ "addScore", "pushItem", "popItem", "moveItem", "reconcileBonus" }),
			val = sert.gen.int(1, 50),
			idx = sert.gen.int(1, 4),
		}),
		1,
		12
	),
	oracle = function(ops)
		local score = 10
		local bonus = 2
		local items: { number } = { 5, 15, 25 }
		for _, step in ops do
			if step.op == "addScore" then
				score += step.val
			elseif step.op == "pushItem" then
				table.insert(items, step.val)
			elseif step.op == "popItem" then
				if #items > 0 then
					local pos = math.clamp(step.idx, 1, #items)
					table.remove(items, pos)
				end
			elseif step.op == "moveItem" then
				if #items > 1 then
					local from = math.clamp(step.idx, 1, #items)
					local to = math.clamp((step.val % #items) + 1, 1, #items)
					local v = table.remove(items, from) :: number
					table.insert(items, to, v)
				end
			elseif step.op == "reconcileBonus" then
				bonus = step.val
			end
		end
		local sum = 0
		local parts: { string } = {}
		for _, v in items do
			sum += v
			table.insert(parts, tostring(v))
		end
		local total = (score + sum) * bonus
		return `{total}|{#items}:{table.concat(parts, ",")}`
	end,
	sut = function(ops)
		local st = Flux.store({
			stats = { score = 10, bonus = 2 },
			items = { 5, 15, 25 },
		})
		local latestEffect = ""
		local totalNode
		local scope = Flux.scope(function()
			local sumNode = Flux.computed(function()
				local s = 0
				for _, v in st.items do
					s += v
				end
				return s
			end)
			totalNode = Flux.computed(function()
				return (st.stats.score + sumNode()) * st.stats.bonus
			end)
			Flux.effect(function()
				local parts: { string } = {}
				for _, v in st.items do
					table.insert(parts, tostring(v))
				end
				latestEffect = `{totalNode()}|{#st.items}:{table.concat(parts, ",")}`
			end)
		end)
		Flux.flush()

		for _, step in ops do
			if step.op == "addScore" then
				st.stats.score += step.val
			elseif step.op == "pushItem" then
				Store.insert(st.items, step.val)
			elseif step.op == "popItem" then
				if #st.items > 0 then
					local pos = math.clamp(step.idx, 1, #st.items)
					Store.remove(st.items, pos)
				end
			elseif step.op == "moveItem" then
				if #st.items > 1 then
					local from = math.clamp(step.idx, 1, #st.items)
					local to = math.clamp((step.val % #st.items) + 1, 1, #st.items)
					Store.move(st.items, from, to)
				end
			elseif step.op == "reconcileBonus" then
				Store.reconcile(st.stats, { score = st.stats.score, bonus = step.val })
			end
			Flux.flush()
		end

		scope:Destroy()
		Flux.dispose(st)
		Flux.flush()
		return latestEffect
	end,
}, { runs = 80 })

return {}
