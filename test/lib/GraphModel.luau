--!nonstrict
local env = require("./env")

local GraphModel = {}

export type Options = {
	faults: boolean?, -- fault injection: a fault signal makes bodies throw after their reads
	teardown: boolean?, -- weight scopes, destroys, children and cleanups up
	trackedOnly: boolean?, -- bodies read tracked only, so quiescent values don't depend on run order
	lazy: boolean?, -- check laziness (default true)
	solid: boolean?, -- exercise getter/setter/createSignal/createMemo/createEffect
}

GraphModel.RERUN_LIMIT = 100
local RUNAWAY = 1000 -- runs of one node within one top-level op that count as a hang
local FALLBACK = 7 -- Flux.safe's fallback

local Fault = {
	__tostring = function(fault)
		return `[GraphModel] injected fault {fault.fault}`
	end,
}

local function modEq(a: any, b: any): boolean
	if type(a) == "number" and type(b) == "number" then
		return a % 10 == b % 10
	end
	return a == b
end

local function rawEq(a: any, b: any): boolean
	return a == b
end

local function norm(v: any): number
	return if type(v) == "number" then v % 10 else 0
end

--------------------------------------------------------------------------------------------------------------------
-- Generator

local TRACKED = { get = true, read = true, pcallRaw = true, getter = true }

type Def = { kind: string, level: number, closure: { [number]: boolean }, dead: boolean, owner: number? }

local function closureOfBody(defs: { Def }, body: any): ({ [number]: boolean }, number)
	local set, level = {}, -1
	local function add(id: number)
		if set[id] then
			return
		end
		set[id] = true
		local def = defs[id]
		if def.kind == "signal" then
			level = math.max(level, def.level)
		end
		for other in def.closure do
			if not set[other] then
				add(other)
			end
		end
	end
	for _, read in body.reads do
		add(read.id)
	end
	if body.child then
		for _, read in body.child.body.reads do
			add(read.id)
		end
	end
	return set, level
end

local function newGenerator(g: any, options: Options)
	local tiny = g.size < 8
	local maxDepth = if tiny then 1 else 3
	local st = { defs = {} :: { Def }, loopDone = false, written = {} }

	local function ids(filter: (Def) -> boolean): { number }
		local list = {}
		for id, def in st.defs do
			if filter(def) then
				table.insert(list, id)
			end
		end
		table.sort(list)
		return list
	end
	local function readables()
		return ids(function(def)
			return def.kind == "signal" or def.kind == "computed"
		end)
	end
	local function pool(owner: number?, encl: { number }?): { number }
		local chain = {}
		local function walk(id: number?)
			while id do
				chain[id] = true
				id = st.defs[id].owner
			end
		end
		walk(owner)
		for _, id in encl or {} do
			walk(id)
		end
		local list = {}
		for _, id in readables() do
			local ok = not chain[id]
			if ok then
				for other in chain do
					if st.defs[id].closure[other] then
						ok = false
						break
					end
				end
			end
			if ok then
				table.insert(list, id)
			end
		end
		return list
	end
	local function with(encl: { number }, id: number?): { number }
		local list = table.clone(encl)
		if id then
			table.insert(list, id)
		end
		return list
	end
	local function signals()
		return ids(function(def)
			return def.kind == "signal"
		end)
	end

	local function define(kind: string, level: number, closure, owner: number?): number
		table.insert(st.defs, { kind = kind, level = level, closure = closure or {}, dead = false, owner = owner })
		return #st.defs
	end

	local function readMode(): string
		if options.trackedOnly then
			return if options.solid then g:pick({ "get", "read", "getter" }) else g:pick({ "get", "read" })
		elseif tiny then
			return g:pick({ "get", "peek" })
		elseif options.solid then
			return g:weighted({
				{ 4, "get" },
				{ 4, "getter" },
				{ 2, "read" },
				{ 1, "untrack" },
				{ 1, "peek" },
				{ 1, "raw" },
				{ 1, "rawGetter" },
				{ 1, "bare" },
				{ 2, "pcallRaw" },
			})
		end
		return g:weighted({
			{ 6, "get" },
			{ 2, "read" },
			{ 1, "untrack" },
			{ 1, "peek" },
			{ 1, "raw" },
			{ 1, "rawGetter" },
			{ 1, "bare" },
			{ 3, "pcallRaw" },
		})
	end

	local function genBody(kind: string, ctxKnown: boolean, child: boolean, owner: number?): any
		local body = { reads = {} }
		local pool = pool(owner)
		local count = if tiny then 1 else g:int(1, 3)
		for i = 1, count do
			local read = { id = g:pick(pool), mode = if kind == "on" then "get" else readMode() }
			if kind == "on" then
				read.dep = i == 1 or options.trackedOnly or g:bool(0.5)
				if not read.dep then
					read.mode = "peek"
				end
			elseif not tiny and i > 1 and g:bool(0.25) then
				read.cond = { at = g:int(1, i - 1), k = g:int(0, 1) }
			end
			body.reads[i] = read
		end
		local pCleanup = if options.teardown then 0.6 else 0.35
		if g:bool(pCleanup) then
			body.cleanup = {}
			if not tiny and g:bool(0.3) then
				body.cleanup.read = g:pick(signals())
			end
		end
		if options.faults and g:bool(0.35) then
			body.fault = true
		end
		if child then
			return body
		end
		if not tiny and g:bool(0.1) then
			body.dispose = g:pick(signals())
		end
		if ctxKnown and not tiny and g:bool(0.3) then
			body.ctx = true
		end
		if kind ~= "on" and not tiny and g:bool(if options.teardown then 0.35 else 0.15) then
			body.child = { kind = g:pick({ "effect", "computed" }), body = genBody("child", false, true, owner) }
		end
		if kind == "effect" then
			if not tiny and g:bool(0.1) then
				body.flush = true
			end
			local _, level = closureOfBody(st.defs, body)
			local targets = ids(function(def)
				return def.kind == "signal" and def.level > level
			end)
			if options.trackedOnly then
				local free = {}
				for _, id in targets do
					if not st.written[id] then
						table.insert(free, id)
					end
				end
				targets = free
			end
			if #targets > 0 and g:bool(0.3) then
				body.write = { id = g:pick(targets) }
				st.written[body.write.id] = true
			end
		end
		return body
	end

	local genOps

	local function genOp(depth: number, ctxKnown: boolean, owner: number?, encl: { number }): any
		local nRead, nSig = #pool(owner), #signals()
		local teardown = options.teardown
		local kind = g:weighted({
			{ if nRead == 0 then 10 else 3, "signal" },
			{ if nRead > 0 then 3 else 0, "computed" },
			{ if nRead > 0 then 3 else 0, "effect" },
			{ if nSig > 0 and not tiny and not options.trackedOnly then 1 else 0, "converge" },
			{ if nSig > 0 then 4 else 0, "set" },
			{ if nSig > 0 and not tiny then 1 else 0, "force" },
			{ if nSig > 0 and not tiny then 1 else 0, "update" },
			{ if #readables() > 0 then 2 else 0, "read" },
			{ if depth < maxDepth then (if teardown then 3 else 1) else 0, "scope" },
			{ if depth < 3 and not tiny then 1 else 0, "provide" },
			{ if depth < maxDepth and #st.defs > 0 then (if teardown then 2 else 1) else 0, "withOwner" },
			{ if depth == 0 and #st.defs > 0 then (if teardown then 3 else 1) else 0, "destroy" },
			{ if depth == 0 then 3 elseif tiny then 0 else 1, "flush" },
			{ if options.faults then 2 else 0, "fault" },
			{ if depth == 0 and not st.loopDone then 3 else 0, "loop" },
		})
		if kind == "signal" then
			local value, eqMod = g:int(0, if tiny then 1 else 9), not tiny and g:bool(0.25)
			local level = if tiny then 0 else g:int(0, 3)
			local id = define("signal", level, nil, nil)
			st.defs[id].closure = {}
			local solid = if options.solid then g:bool(0.5) else nil
			return {
				op = "signal",
				id = id,
				value = value,
				eqMod = eqMod or nil,
				level = level,
				onDestroy = (not tiny and not solid and g:bool(0.2)) or nil,
				solid = solid or nil,
			}
		elseif kind == "computed" then
			local variant = if tiny then "computed" else g:weighted({ { 6, "computed" }, { 1, "safe" }, { 1, "on" } })
			local body = genBody(variant, ctxKnown, false, owner)
			local eqMod = not tiny and g:bool(0.25)
			local closure, level = closureOfBody(st.defs, body)
			local id = define("computed", level, closure, owner)
			local solid = if options.solid and variant == "computed" and body.child == nil then g:bool(0.5) else nil
			return {
				op = "computed",
				id = id,
				variant = variant,
				body = body,
				eqMod = eqMod or nil,
				onDestroy = (not tiny and not solid and g:bool(0.2)) or nil,
				solid = solid or nil,
			}
		elseif kind == "effect" then
			local body = genBody("effect", ctxKnown, false, owner)
			local closure, level = closureOfBody(st.defs, body)
			local id = define("effect", level, closure, owner)
			local solid = if options.solid and body.child == nil then g:bool(0.5) else nil
			return {
				op = "effect",
				id = id,
				body = body,
				onDestroy = (not tiny and not solid and g:bool(0.2)) or nil,
				solid = solid or nil,
			}
		elseif kind == "converge" then
			local target = g:pick(signals())
			local body = { reads = { { id = target, mode = "get" } }, write = { id = target, cap = g:int(1, 5) } }
			local extra = pool(owner)
			if #extra > 0 and g:bool(0.4) then
				table.insert(body.reads, { id = g:pick(extra), mode = readMode() })
			end
			if g:bool(0.3) then
				body.cleanup = {}
			end
			local closure, level = closureOfBody(st.defs, body)
			local id = define("effect", level, closure, owner)
			return { op = "effect", id = id, body = body }
		elseif kind == "set" or kind == "force" then
			local viaSetter = if options.solid then g:bool(0.5) else nil
			return {
				op = kind,
				id = g:pick(signals()),
				value = g:int(0, if tiny then 1 else 9),
				setter = viaSetter or nil,
			}
		elseif kind == "update" then
			return { op = "update", id = g:pick(signals()) }
		elseif kind == "read" then
			local modes = if options.solid then { "get", "peek", "raw", "getter" } else { "get", "peek", "raw" }
			return {
				op = "read",
				id = g:pick(readables()),
				mode = if tiny then "peek" else g:pick(modes),
			}
		elseif kind == "scope" then
			local id = define("scope", -1, nil, owner)
			local ops = genOps(depth + 1, ctxKnown, id, with(encl, id))
			return { op = "scope", id = id, ops = ops, cleanup = g:bool(0.4) or nil }
		elseif kind == "provide" then
			local value = g:int(1, 9)
			return { op = "provide", value = value, ops = genOps(depth + 1, true, owner, encl) }
		elseif kind == "withOwner" then
			local owners = ids(function(def)
				return def.kind == "scope" or def.kind == "computed" or def.kind == "effect"
			end)
			local target = if #owners > 0 and g:bool(0.8) then g:pick(owners) else nil
			return {
				op = "withOwner",
				target = target,
				cleanup = (target ~= nil and g:bool(0.4)) or nil,
				ops = genOps(depth + 1, ctxKnown, target, with(encl, target)),
			}
		elseif kind == "destroy" then
			local id = g:int(1, #st.defs)
			st.defs[id].dead = true
			return { op = "destroy", id = id }
		elseif kind == "flush" then
			local arg = if depth == 0 and g:bool(0.5) then 0.016 else nil
			return { op = "flush", arg = arg }
		elseif kind == "fault" then
			return { op = "fault", value = g:int(0, if tiny then 1 else 2) }
		elseif kind == "loop" then
			st.loopDone = true
			local signalId = define("signal", 4, nil, nil)
			local id = define("effect", 4, { [signalId] = true }, owner)
			return { op = "loop", signal = signalId, id = id, cleanup = g:bool(0.5) or nil }
		end
		error(`unknown op kind {kind}`)
	end

	function genOps(depth: number, ctxKnown: boolean, owner: number?, encl: { number }): { any }
		local max = if depth == 0 then g.size else (if tiny then 1 else 3)
		return g:list(function()
			return genOp(depth, ctxKnown, owner, encl)
		end, 1, max)
	end

	return genOps
end

local format

function GraphModel.generate(g: any, options: Options?): any
	local opts = options or {}
	local genOps = newGenerator(g, opts)
	local ops = genOps(0, false, nil, {})
	local program = { ops = ops }
	for _, op in ops do
		g:note("%s", format(op))
	end
	return program
end

function format(value: any): string
	if type(value) == "table" then
		if #value > 0 or next(value) == nil then
			local parts = {}
			for _, item in value do
				table.insert(parts, format(item))
			end
			return "{ " .. table.concat(parts, ", ") .. " }"
		end
		local keys = {}
		for key in value do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			if a == "op" then
				return b ~= "op"
			elseif b == "op" then
				return false
			end
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		for _, key in keys do
			table.insert(parts, `{key} = {format(value[key])}`)
		end
		return "{ " .. table.concat(parts, ", ") .. " }"
	elseif type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

GraphModel.format = format

--------------------------------------------------------------------------------------------------------------------
-- Model

local Model = {}
Model.__index = Model

local PREFIX = {
	signal = "s",
	computed = "c",
	safe = "f",
	on = "o",
	effect = "e",
	scope = "x",
	root = "r",
	loop = "l",
}

local READERS = {
	get = function(_, node)
		return node:get()
	end,
	getter = function(Flux, node)
		if rawget(node, "_solid") then
			return node:get()
		end
		return Flux.getter(node)()
	end,
	read = function(Flux, node)
		if rawget(node, "_solid") then
			return Flux.read(node._get)
		end
		return Flux.read(node)
	end,
	untrack = function(Flux, node)
		return Flux.untrack(function()
			return node:get()
		end)
	end,
	peek = function(_, node)
		return node:peek()
	end,
	raw = function(Flux, node)
		if rawget(node, "_solid") then
			return Flux.raw(node._get)
		end
		return Flux.raw(node)
	end,
	rawGetter = function(Flux, node)
		return Flux.raw(function()
			return node:get()
		end)
	end,
	bare = function(Flux, node)
		Flux.untrack()
		local value = node:get()
		Flux.retrack()
		return value
	end,
	pcallRaw = function(Flux, node)
		pcall(Flux.raw, function()
			node:get()
			error("model: throwing getter", 0)
		end)
		return node:get()
	end,
}

local function isComputed(rec: any): boolean
	return rec.kind == "computed" or rec.kind == "safe" or rec.kind == "on"
end

function Model.new(Flux: any, options: Options)
	local self = setmetatable({}, Model)
	self.Flux = Flux
	self.options = options
	self.lazy = options.lazy ~= false
	self.recs = {}
	self.all = {}
	self.epoch = 0
	self.seq = 0
	self.execs = 0
	self.fails = {}
	self.kills = 0
	self.curOwner = nil
	self.ctxVal = nil
	self.stack = {}
	self.flushing = false
	self.dynamic = 0
	self.tokens = {}
	self.ctx = Flux.context(0)
	self.F = self:newRec("signal", "F", nil)
	self.F.name = "fault"
	self.F.value, self.F.held = 0, 0
	self.F.node = Flux.signal(0)
	return self
end

function Model:fail(message: string)
	table.insert(self.fails, message)
end

function Model:raise(where: string)
	local first = self.fails[1]
	if first then
		error(`{first}\n   (at {where}; {#self.fails} violation(s))`, 0)
	end
end

function Model:newRec(kind: string, id: any, owner: any): any
	local rec = {
		kind = kind,
		id = id,
		owner = owner,
		children = {},
		tokens = {},
		dtokens = {},
		alive = true,
		lastChange = 0,
		burst = 0,
		closure = {},
		closureSet = {},
	}
	rec.name = if type(id) == "number" then (PREFIX[kind] or "?") .. id else tostring(id)
	table.insert(self.all, rec)
	if owner then
		table.insert(owner.children, rec)
	end
	return rec
end

function Model:setClosure(rec: any, body: any)
	local list, set = {}, {}
	local function add(target: any)
		if set[target] then
			return
		end
		set[target] = true
		table.insert(list, target)
		for _, other in target.closure do
			add(other)
		end
	end
	for _, read in body.reads do
		add(self.recs[read.id])
	end
	if body.child then
		for _, read in body.child.body.reads do
			add(self.recs[read.id])
		end
	end
	rec.closure, rec.closureSet = list, set
end

function Model:tainted(rec: any, dying: boolean?): boolean
	if rec.ctxTaint or (not rec.alive and not dying) then
		return true
	end
	for _, other in rec.closure do
		if not other.alive then
			return true
		end
	end
	return false
end

function Model:changed(rec: any)
	self.epoch += 1
	rec.lastChange = self.epoch
end

function Model:token(owner: any, kind: string, checkOld: boolean): any
	local token = { owner = owner, kind = kind, fired = 0, checkOld = checkOld }
	token.name = `{kind} of {owner.name}`
	table.insert(self.tokens, token)
	return token
end

function Model:fire(token: any, old: any, destroyed: any)
	token.fired += 1
	self.seq += 1
	token.seq = self.seq
	if token.fired > 1 then
		self:fail(`{token.name} ran {token.fired} times`)
	end
	token.old, token.destroyed = old, destroyed
end

function Model:expectFired(token: any, destroyed: boolean, old: any, why: string)
	if token.fired ~= 1 then
		self:fail(`{token.name} ran {token.fired} times by {why}, expected once`)
		return
	end
	if token.kind == "cleanup" and token.destroyed ~= destroyed then
		self:fail(`{token.name} got destroyed = {token.destroyed} at {why}, expected {destroyed}`)
	end
	if token.checkOld and not self:tainted(token.owner, true) then
		local eq = if token.owner.eqMod then modEq else rawEq
		if not eq(token.old, old) then
			self:fail(`{token.name} got old value {token.old} at {why}, expected {old}`)
		end
	end
end

local function subtreeMaxSeq(rec: any, acc: number): number
	for _, token in rec.tokens do
		acc = math.max(acc, token.seq or 0)
	end
	for _, token in rec.dtokens do
		acc = math.max(acc, token.seq or 0)
	end
	for _, child in rec.children do
		acc = subtreeMaxSeq(child, acc)
	end
	return acc
end

function Model:checkOrder(rec: any, children: { any }, tokens: { any }, why: string)
	local last = 0
	for _, child in children do
		last = subtreeMaxSeq(child, last)
	end
	for _, token in tokens do
		if token.seq and token.seq < last then
			self:fail(`{token.name} ran before {rec.name}'s children were torn down ({why})`)
			return
		end
	end
end

local function untrackedCause(rec: any): boolean
	local seen = {}
	while rec and not seen[rec] do
		seen[rec] = true
		local cur = rec.cur
		local cause = cur and not cur.ok and cur.cause
		if not cause or cause.fault then
			return false
		elseif not cause.tracked then
			return true
		end
		rec = cause.rec
	end
	return false
end

function Model:kill(rec: any, why: string)
	if not rec.alive then
		return
	end
	rec.alive = false
	self.kills += 1
	local children, tokens = rec.children, rec.tokens
	for _, child in children do
		self:kill(child, why)
	end
	if rec.kind ~= "signal" then
		self:checkOrder(rec, children, tokens, why)
	end
	for _, token in tokens do
		self:expectFired(token, true, rec.held, why)
	end
	for _, token in rec.dtokens do
		self:expectFired(token, true, rec.held, why)
	end
	rec.tokens = {}
end

function Model:reap(rec: any, why: string)
	if rec.alive then
		return
	end
	for _, child in rec.children do
		self:kill(child, why)
	end
	for _, token in rec.tokens do
		self:expectFired(token, true, nil, why)
	end
end

function Model:legitRun(rec: any): boolean
	for _, target in self.stack do
		if target == rec or target.closureSet[rec] then
			return true
		end
		if rec.dynamic and (target == rec.owner or target.closureSet[rec.owner]) then
			return true
		end
	end
	if self.flushing then
		if rec.dynamic then
			return true
		end
		for _, other in self.all do
			if other.kind == "effect" and other.alive and other.closureSet[rec] then
				return true
			end
		end
	end
	return false
end

function Model:beginRun(rec: any)
	self.execs += 1
	rec.burst += 1
	rec.flushRuns = (rec.flushRuns or 0) + 1
	if rec.burst > RUNAWAY then
		self:fail(`{rec.name} ran more than {RUNAWAY} times in one op (a loop the graph did not stop)`)
		error("[GraphModel] runaway", 0)
	end
	if not rec.alive then
		self:fail(`{rec.name} ran after it was destroyed`)
	end
	if isComputed(rec) and self.lazy and not self:legitRun(rec) then
		self:fail(`{rec.name} ran while nothing read it (not lazy)`)
	end

	local prev = rec.cur
	if prev and prev.ok and not rec.ctxTaint then
		local justified = false
		for _, read in prev.reads do
			if read.tracked and (read.rec.lastChange > read.epoch or not read.rec.alive) then
				justified = true
				break
			end
		end
		if not justified then
			self:fail(`{rec.name} re-ran though nothing it tracked changed (spurious run)`)
		end
	end

	local children, tokens = rec.children, rec.tokens
	for _, child in children do
		self:kill(child, `{rec.name}'s re-run`)
	end
	self:checkOrder(rec, children, tokens, `{rec.name}'s re-run`)
	for _, token in tokens do
		self:expectFired(token, false, rec.held, `{rec.name}'s re-run`)
	end
	rec.children, rec.tokens = {}, {}
	rec.cur = { reads = {} }
end

function Model:endRun(rec: any, ok: boolean, result: any)
	local cur = rec.cur
	if rec.kind == "safe" and not ok then
		ok, result = true, FALLBACK
	end
	if rec.kind == "effect" then
		result = nil
	end
	cur.ok = ok
	if ok then
		local eq = if rec.eqMod then modEq else rawEq
		if rec.lastOk ~= true or not eq(rec.held, result) then
			self:changed(rec)
		end
		rec.held, rec.lastOk = result, true
	else
		cur.err = result
		self:changed(rec)
		rec.lastOk = false
	end
end

function Model:readIn(rec: any, target: any, mode: string): any
	local stack = self.stack
	table.insert(stack, target)
	local ok, value = pcall(READERS[mode], self.Flux, target.node)
	table.remove(stack)
	local cur = rec.cur
	if not ok then
		cur.cause = { rec = target, tracked = TRACKED[mode] == true }
		table.insert(cur.reads, { rec = target, tracked = TRACKED[mode] == true, epoch = self.epoch, failed = true })
		error(value, 0)
	end
	table.insert(cur.reads, { rec = target, v = norm(value), tracked = TRACKED[mode] == true, epoch = self.epoch })
	return value
end

function Model:write(target: any, value: any, mode: string, useSetter: boolean?)
	if not target.alive then
		return
	end
	local node = target.node
	if mode == "update" then
		node:update()
		self:changed(target)
		return
	end
	local eq = if target.eqMod then modEq else rawEq
	local changing = mode == "force" or not eq(target.value, value)
	local setFn = if useSetter and not rawget(node, "_solid") then self.Flux.setter(node) else nil
	if mode == "force" then
		if setFn then
			setFn(value, true)
		else
			node:set(value, true)
		end
	else
		if setFn then
			setFn(value)
		else
			node:set(value)
		end
	end
	if changing then
		target.value, target.held = value, value
		self:changed(target)
	end
end

function Model:bodyFn(rec: any): (any) -> any
	local Flux = self.Flux
	local body = rec.body

	local function finish(total: number, raws: { any }): number
		if body.ctx then
			total += norm(self.ctx:get())
		end
		if body.dispose then
			local target = self.recs[body.dispose]
			Flux.dispose(function()
				target.node:get()
			end)
		end
		if body.flush then
			Flux.flush()
		end
		if body.fault then
			local fault = self:readIn(rec, self.F, "get")
			if norm(fault) ~= 0 then
				rec.cur.cause = { fault = true, tracked = true }
				error(setmetatable({ fault = fault }, Fault), 0)
			end
		end
		local write = body.write
		if write then
			local target = self.recs[write.id]
			local value
			if write.cap then
				value = math.min((raws[1] or 0) + 1, write.cap)
				if value <= (raws[1] or 0) then
					value = nil
				end
			elseif write.loop then
				value = (raws[1] or 0) + 1
			else
				value = total % 10
			end
			if value ~= nil then
				self:write(target, value, "set")
				target.writer = rec
			end
		end
		return total
	end

	local function start()
		if body.cleanup then
			local token = self:token(rec, "cleanup", not rec.solid)
			local readId = body.cleanup.read
			Flux.cleanup(function(old, destroyed)
				self:fire(token, old, destroyed)
				if readId then
					self.recs[readId].node:get()
				end
			end)
			table.insert(rec.tokens, token)
		end
	end

	local function child(): number
		local spec = body.child
		if not spec then
			return 0
		end
		self.dynamic += 1
		local kid = self:newRec(spec.kind, `k{self.dynamic}<{rec.name}`, rec)
		kid.dynamic = true
		kid.body = spec.body
		self:setClosure(kid, spec.body)
		local fn = self:bodyFn(kid)
		kid.node = if spec.kind == "effect" then Flux.effect(fn) else Flux.computed(fn)
		local token = self:token(kid, "onDestroy", true)
		kid.node:onDestroy(function(old)
			self:fire(token, old, true)
		end)
		table.insert(kid.dtokens, token)
		if spec.kind == "computed" then
			return norm(self:readIn(rec, kid, "get"))
		end
		return 0
	end

	local inner
	if rec.kind == "on" then
		local deps, extras = {}, {}
		for _, read in body.reads do
			local target = self.recs[read.id]
			if read.dep then
				table.insert(deps, function()
					return self:readIn(rec, target, "get")
				end)
			else
				table.insert(extras, target)
			end
		end
		if body.fault then
			table.insert(deps, function()
				return self:readIn(rec, self.F, "get")
			end)
		end
		local onFn = Flux.on(deps, function(input)
			local total = 0
			for i = 1, #input do
				if body.fault and i == #input then
					if norm(input[i]) ~= 0 then
						rec.cur.cause = { fault = true, tracked = true }
						error(setmetatable({ fault = input[i] }, Fault), 0)
					end
				else
					total += norm(input[i])
				end
			end
			for _, target in extras do
				total += norm(self:readIn(rec, target, "peek"))
			end
			if body.ctx then
				total += norm(self.ctx:get())
			end
			return total
		end)
		inner = function(prev)
			start()
			return onFn(prev)
		end
	else
		inner = function()
			start()
			local vals, raws, total = {}, {}, 0
			for i, read in body.reads do
				local cond = read.cond
				if cond and (vals[cond.at] == nil or vals[cond.at] % 2 ~= cond.k) then
					continue
				end
				local value = self:readIn(rec, self.recs[read.id], read.mode)
				raws[i] = value
				vals[i] = norm(value)
				total += vals[i]
			end
			total += child()
			return finish(total, raws)
		end
	end

	return function(prev)
		if self.closed then
			return 0
		end
		self:beginRun(rec)
		local ok, result = pcall(inner, prev)
		self:endRun(rec, ok, result)
		self:reap(rec, `the end of {rec.name}'s run, after its death`)
		if not ok then
			error(result, 0)
		end
		return result
	end
end

local TAINT = { taint = true }
local ERR = { err = true }

function Model:ref(rec: any, memo: any): any
	if not rec.alive then
		return TAINT
	end
	if rec.kind == "signal" then
		return { v = rec.value }
	end
	if memo and memo[rec] then
		return memo[rec]
	end
	local result = self:cached(rec, memo)
	if result == nil then
		result = self:evalBody(rec, rec.body, memo)
		if rec.kind == "safe" and result.err then
			result = { v = FALLBACK }
		end
	end
	if memo then
		memo[rec] = result
	end
	return result
end

function Model:cached(rec: any, memo: any): any
	local last = rec.cur
	if last and not last.ok and untrackedCause(rec) then
		return TAINT
	elseif last == nil or not last.ok or rec.lastOk ~= true then
		return nil
	end
	for _, read in last.reads do
		if read.tracked then
			local target = read.rec
			if not target.alive then
				return TAINT
			elseif target.lastChange > read.epoch then
				return nil
			elseif target.kind ~= "signal" then
				local now = self:ref(target, memo)
				if now.taint then
					return TAINT
				end
				local eq = if target.eqMod then modEq else rawEq
				if now.err or target.lastOk ~= true or not eq(target.held, now.v) then
					return nil
				end
			end
		end
	end
	return { v = rec.held }
end

function Model:evalBody(rec: any, body: any, memo: any): any
	if rec.ctxTaint or self:tainted(rec) then
		return TAINT
	end
	local vals, total = {}, 0
	for i, read in body.reads do
		local cond = read.cond
		if cond and (vals[cond.at] == nil or vals[cond.at] % 2 ~= cond.k) then
			continue
		end
		local result = self:ref(self.recs[read.id], memo)
		if result.taint or result.err then
			return result
		end
		vals[i] = norm(result.v)
		total += vals[i]
	end
	if body.child and body.child.kind == "computed" then
		local result = self:evalBody({ closure = {}, alive = true }, body.child.body, memo)
		if result.taint or result.err then
			return result
		end
		total += norm(result.v)
	end
	if body.ctx then
		total += norm(rec.ctx)
	end
	if body.fault and norm(self.F.value) ~= 0 then
		return ERR
	end
	return { v = total }
end

function Model:checkRead(rec: any, mode: string, memo: any)
	local Flux = self.Flux
	local kills = self.kills
	table.insert(self.stack, rec)
	local ok, value = pcall(READERS[mode], Flux, rec.node)
	table.remove(self.stack)
	if memo and self.kills ~= kills then
		table.clear(memo)
	end
	if not rec.alive then
		if not ok or value ~= nil then
			self:fail(`destroyed {rec.name} read {if ok then tostring(value) else "an error"} via {mode}, expected nil`)
		end
		return
	end
	local ref = self:ref(rec, memo)
	if ref.taint then
		return
	elseif ref.err then
		if ok then
			self:fail(`{rec.name} read {value} via {mode}, expected an error (fault)`)
		end
	elseif not ok then
		self:fail(`{rec.name} raised via {mode}: {tostring(value)}; expected {ref.v}`)
	elseif norm(value) ~= norm(ref.v) then
		self:fail(`{rec.name} read {value} via {mode}, expected {ref.v} (mod 10)`)
	end
end

function Model:idle(where: string)
	local message = env.idle(self.Flux, {
		contexts = { { context = self.ctx, default = 0 } },
	})
	if message then
		self:fail(message)
	end
	self:raise(where)
end

function Model:quiescent(where: string)
	local Flux = self.Flux
	local execs = self.execs
	self.flushing = true
	local drained = env.drained(Flux)
	self.flushing = false
	if drained then
		self:fail(drained)
	end
	if self.execs ~= execs then
		self:fail(`{self.execs - execs} reaction run(s) were still pending after a flush`)
	end
	local memo = {}
	for _, rec in self.all do
		if rec.kind == "effect" and rec.alive and not self:tainted(rec) then
			local last = rec.cur
			if last == nil then
				self:fail(`{rec.name} never ran though it is alive after a flush`)
			elseif last.ok then
				local failing = false
				for _, read in last.reads do
					if read.tracked and self:ref(read.rec, memo).err then
						failing = true
					end
				end
				for _, read in last.reads do
					if read.tracked and not failing then
						local ref = self:ref(read.rec, memo)
						if not ref.taint and norm(ref.v) ~= read.v then
							self:fail(
								`{rec.name} last saw {read.rec.name} = {read.v}, but it is {norm(ref.v)} (missed update)`
							)
						end
					end
				end
			else
				local cause = last.cause
				if cause == nil then
					self:fail(`{rec.name} failed with an unexpected error: {tostring(last.err)}`)
				elseif cause.fault then
					if norm(self.F.value) == 0 then
						self:fail(`{rec.name} failed on a fault that has been cleared (did not recover)`)
					end
				elseif cause.tracked and not cause.rec.dynamic and not untrackedCause(cause.rec) then
					local ref = self:ref(cause.rec, memo)
					if not ref.taint and not ref.err then
						self:fail(`{rec.name} failed reading {cause.rec.name}, which has recovered (did not recover)`)
					end
				end
			end
		end
	end
	for _, rec in self.all do
		if isComputed(rec) and not rec.dynamic then
			self:checkRead(rec, "peek", memo)
		end
	end
	self:raise(where)
end

local function makeSolidSignalAdapter(Flux: any, value: any, eq: any): any
	local get, set
	local scope = Flux.scope(function()
		get, set = Flux.createSignal(value, eq)
	end)
	local dead = false
	local function getWrapped()
		if dead then
			return nil
		end
		return get()
	end
	return {
		_solid = true,
		_get = getWrapped,
		get = getWrapped,
		peek = function()
			if dead then
				return nil
			end
			return Flux.untrack(get)
		end,
		set = function(_, v: any, force: boolean?)
			if not dead then
				set(v, force)
			end
		end,
		update = function()
			if not dead then
				set(Flux.untrack(get), true)
			end
		end,
		Destroy = function()
			if not dead then
				dead = true
				scope:Destroy()
			end
		end,
	}
end

local function makeSolidMemoAdapter(Flux: any, fn: any, eq: any): any
	local get
	local scope = Flux.scope(function()
		get = Flux.createMemo(fn, eq)
	end)
	return {
		_solid = true,
		_get = get,
		get = function()
			return get()
		end,
		peek = function()
			return Flux.untrack(get)
		end,
		Destroy = function()
			scope:Destroy()
		end,
	}
end

local function makeSolidEffectAdapter(Flux: any, fn: any): any
	local scope = Flux.scope(function()
		Flux.createEffect(fn)
	end)
	return {
		_solid = true,
		Destroy = function()
			scope:Destroy()
		end,
	}
end

function Model:create(op: any, kind: string): any
	local Flux = self.Flux
	local rec = self:newRec(kind, op.id, if kind == "signal" then nil else self.curOwner)
	self.recs[op.id] = rec
	rec.ctx = self.ctxVal
	rec.solid = op.solid == true
	if kind == "signal" then
		rec.value, rec.held, rec.eqMod = op.value, op.value, op.eqMod
		local eq = if op.eqMod then modEq else nil
		if op.solid then
			rec.node = makeSolidSignalAdapter(Flux, op.value, eq)
		else
			rec.node = Flux.signal(op.value, eq)
		end
	else
		rec.body = op.body
		rec.eqMod = op.eqMod
		if op.body.ctx and rec.ctx == nil then
			rec.ctxTaint = true
		end
		self:setClosure(rec, op.body)
		local fn = self:bodyFn(rec)
		local eq = if op.eqMod then modEq else nil
		if kind == "effect" then
			if op.solid and self.curOwner == nil then
				rec.node = makeSolidEffectAdapter(Flux, fn)
			else
				rec.solid = false
				rec.node = Flux.effect(fn)
			end
		elseif kind == "safe" then
			rec.node = Flux.safe(fn, FALLBACK, eq)
		else
			if op.solid and self.curOwner == nil then
				rec.node = makeSolidMemoAdapter(Flux, fn, eq)
			else
				rec.solid = false
				rec.node = Flux.computed(fn, eq)
			end
		end
	end
	if op.onDestroy then
		local token = self:token(rec, "onDestroy", kind ~= "scope")
		rec.node:onDestroy(function(old)
			self:fire(token, old, true)
		end)
		table.insert(rec.dtokens, token)
	end
	return rec
end

function Model:block(ops: { any }, depth: number)
	local Flux = self.Flux
	local owner = Flux.getOwner()
	for _, op in ops do
		self:exec(op, depth)
		if Flux.getOwner() ~= owner then
			self:fail(`the owner was not restored after {op.op} inside a block`)
		end
	end
end

function Model:exec(op: any, depth: number)
	local Flux = self.Flux
	local kind = op.op
	if kind == "signal" then
		self:create(op, "signal")
	elseif kind == "computed" then
		self:create(op, op.variant or "computed")
	elseif kind == "effect" then
		self:create(op, "effect")
	elseif kind == "loop" then
		self:create({ id = op.signal, value = 0 }, "signal")
		local body = { reads = { { id = op.signal, mode = "get" } }, write = { id = op.signal, loop = true } }
		if op.cleanup then
			body.cleanup = {}
		end
		local rec = self:create({ id = op.id, body = body }, "effect")
		rec.loop = true
		self.loopRec = rec
	elseif kind == "scope" then
		local rec = self:newRec("scope", op.id, self.curOwner)
		self.recs[op.id] = rec
		rec.ctx = self.ctxVal
		local saved = self.curOwner
		rec.node = Flux.scope(function(node)
			rec.node = node
			self.curOwner = rec
			self:block(op.ops, depth + 1)
			if op.cleanup then
				local token = self:token(rec, "cleanup", false)
				Flux.cleanup(function(old, destroyed)
					self:fire(token, old, destroyed)
				end)
				table.insert(rec.tokens, token)
			end
		end)
		self.curOwner = saved
		self:reap(rec, `the end of {rec.name}'s body, after its death`)
	elseif kind == "withOwner" then
		local target = if op.target then self.recs[op.target] else nil
		local arg, ownerRec, root = nil, nil, nil
		if target and target.alive and not target.solid then
			arg, ownerRec = target.node, target
		elseif target and not target.solid then
			arg = target.node
			self.dynamic += 1
			root = self:newRec("root", `r{self.dynamic}`, nil)
			ownerRec = root
		end
		local savedOwner, savedCtx = self.curOwner, self.ctxVal
		self.curOwner = ownerRec
		if ownerRec == target and target and target.ctx ~= nil then
			self.ctxVal = target.ctx
		end
		Flux.withOwner(arg, function()
			self:block(op.ops, depth + 1)
			if op.cleanup and ownerRec then
				local token = self:token(ownerRec, "cleanup", ownerRec ~= root and ownerRec.kind ~= "scope")
				Flux.cleanup(function(old, destroyed)
					self:fire(token, old, destroyed)
				end)
				table.insert(ownerRec.tokens, token)
			end
		end)
		self.curOwner, self.ctxVal = savedOwner, savedCtx
		if root then
			self:kill(root, "the end of withOwner(destroyed owner)")
		elseif ownerRec then
			self:reap(ownerRec, `the end of withOwner({ownerRec.name}), after its death`)
		end
	elseif kind == "provide" then
		local saved = self.ctxVal
		self.ctxVal = op.value
		self.ctx:provide(op.value, function()
			self:block(op.ops, depth + 1)
		end)
		self.ctxVal = saved
	elseif kind == "set" or kind == "force" then
		self:write(self.recs[op.id], op.value, kind, op.setter)
		self.recs[op.id].writer = nil
	elseif kind == "update" then
		self:write(self.recs[op.id], nil, "update")
	elseif kind == "fault" then
		self:write(self.F, op.value, "set")
	elseif kind == "read" then
		self:checkRead(self.recs[op.id], op.mode)
	elseif kind == "destroy" then
		local rec = self.recs[op.id]
		rec.node:Destroy()
		self:kill(rec, `destroy {rec.name}`)
	elseif kind == "flush" then
		for _, rec in self.all do
			rec.flushRuns = 0
		end
		local wasFlushing = self.flushing
		self.flushing = true
		if op.arg ~= nil then
			Flux.flush(op.arg)
		else
			Flux.flush()
		end
		self.flushing = wasFlushing
		local loop = self.loopRec
		if loop and loop.alive and loop.flushRuns > 1 then
			local limit = GraphModel.RERUN_LIMIT + 2
			if loop.flushRuns > limit then
				self:fail(`{loop.name} ran {loop.flushRuns} times in one flush; the loop guard allows {limit}`)
			end
			self:kill(loop, "the loop guard")
		end
	else
		error(`unknown op {kind}`)
	end
end

function Model:snapshot(): string
	local memos = { [false] = {}, [true] = {} }
	local function tainted(rec: any, writer: boolean?): boolean
		local memo = memos[writer == true]
		local known = memo[rec]
		if known ~= nil then
			return known
		end
		memo[rec] = false
		local result = self:tainted(rec, writer) or (rec.writer ~= nil and tainted(rec.writer, true))
		if not result then
			for _, other in rec.closure do
				if other.writer ~= nil and tainted(other.writer, true) then
					result = true
					break
				end
			end
		end
		memo[rec] = result
		return result
	end
	local parts = {}
	for _, rec in self.all do
		if rec.dynamic or rec.kind == "root" then
			continue
		end
		local text = `{rec.name}:{if rec.alive then "live" else "dead"}`
		if rec.alive and not tainted(rec) then
			if rec.kind == "signal" then
				text ..= `={norm(rec.value)}`
			elseif isComputed(rec) then
				table.insert(self.stack, rec)
				local ok, value = pcall(rec.node.peek, rec.node)
				table.remove(self.stack)
				text ..= if ok then `={norm(value)}` else "=error"
			elseif rec.kind == "effect" and rec.cur then
				if rec.cur.ok then
					local seen = {}
					for _, read in rec.cur.reads do
						if read.tracked then
							table.insert(seen, `{if read.rec.dynamic then "child" else read.rec.name}={read.v}`)
						end
					end
					text ..= ` saw[{table.concat(seen, ",")}]`
				else
					text ..= " failed"
				end
			end
		end
		table.insert(parts, text)
	end
	return table.concat(parts, "; ")
end

function Model:teardown()
	for index = #self.all, 1, -1 do
		local rec = self.all[index]
		if not rec.dynamic and rec.kind ~= "root" and rec.alive and rec.node then
			rec.node:Destroy()
			self:kill(rec, `final destroy of {rec.name}`)
		end
	end
	self.flushing = true
	self.Flux.flush()
	self.flushing = false
	for _, token in self.tokens do
		if token.fired ~= 1 then
			self:fail(`{token.name} ran {token.fired} times by the end, expected once`)
		end
	end
end

function GraphModel.run(Flux: any, program: any, options: Options?): string
	local opts = options or {}
	local model = Model.new(Flux, opts)
	local ok, result = pcall(function()
		model:idle("start")
		for index, op in program.ops do
			for _, rec in model.all do
				rec.burst = 0
			end
			model:exec(op, 0)
			local where = `op {index} ({op.op})`
			model:idle(where)
			if op.op == "flush" then
				model:quiescent(where)
			end
		end
		for _, rec in model.all do
			rec.burst = 0
		end
		model:exec({ op = "flush" }, 0)
		model:quiescent("the final flush")
		local snapshot = model:snapshot()
		model:teardown()
		model:idle("teardown")
		return snapshot
	end)
	model.closed = true
	if not ok then
		for index = #model.all, 1, -1 do
			local rec = model.all[index]
			if rec.node then
				pcall(rec.node.Destroy, rec.node)
			end
		end
		pcall(Flux.flush)
		error(result, 0)
	end
	return result
end

return table.freeze(GraphModel)
