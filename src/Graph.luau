--!strict

--[[
	Lazy reactivity for Luau (push-pull / fine-grained reactivity).
	Observable primitives auto-track dependencies and recompute only what's read.

	Primitives:
		Graph.signal(value, equals?)       -- writable source
		Graph.computed(fn, equals?)        -- derived value, recomputed on demand
		Graph.effect(fn)                   -- side-effecting reaction, run on flush
		Graph.new / Graph(obj, isEffect?, equals?) -- factory dispatching to the above

	Node API (callable, with arithmetic/comparison metamethods):
		node:get() / node()              -- read, tracked
		node:peek()                      -- read, untracked
		node:set(v, force?) / node(v)    -- write
		node:onDestroy(fn) / node:Destroy()

	Model:
		Nodes are CLEAN / CHECK / DIRTY. Writes push staleness to observers; reads
		pull values current, walking sources to skip redundant recomputation.
		Effects queue and run via flush(). Equality (default ~=) gates propagation.

	Ownership:
		Reactions (computeds/effects) and scopes form an owner tree; plain signals do NOT join it: a
		signal is never owned and is reclaimed by the GC once unreferenced. Disposing a reaction/scope
		tears down its children, running cleanup()/onDestroy() callbacks. scope()/withOwner()/getOwner()
		manage owners; untrack()/retrack() control tracking. Disposal strips a node's inner table but keeps
		its wrapper + metatable (isNode stays true); the emptied wrapper is left for the GC. onDestroy fires
		only on explicit/owner disposal, never from GC.

	Strict mode:
		When enabled, every reactive scope (computeds AND effects) runs a full second time
		to surface non-idempotent bodies in development. strict(on) swaps the `update` pointer
		between the lean single-run path and the double-run path; the latter also errors on reactive
		cycles (re-entering an active scope) and on destroying the scope that is currently running.

--]]

export type node = { any }

local CLEAN = 0
local CHECK = 1
local DIRTY = 2

local VALUE = 1
local OBSERVERS = 2
local EQUALS = 3
local SEEN = 4
local STATE = 5
local FN = 6
local SOURCES = 7
local OWNER = 8
local EFFECT = 9
local CHILDREN = 10
local CLEANUPS = 11
local DESTROYS = 12

local evalId = 0
local currentEvalId = 0
local currentOwner: node? = nil
local currentReaction: node? = nil
local currentSourcesIndex = 0
local currentSources: { node }? = nil
local effectQueue: { node } = {}
local effectQueueN = 0
local drainIndex = 0
local scopes: { node } = {}

local warn = warn or print

local function inline_test(): string
	return debug.info(1, "n")
end

local is_O2 = inline_test() ~= "inline_test"

local strict_mode = not is_O2

local Node
local update: (node) -> ()

local NODE_KEY = table.freeze({ type = "node" })

local function isNode(object: unknown): boolean
	return type(object) == "table" and object[NODE_KEY] ~= nil
end

local function isReactive(): boolean
	return currentReaction ~= nil
end

local function doCleanup(node: node, destroyed: boolean)
	local cleanups = node[CLEANUPS]
	if cleanups then
		node[CLEANUPS] = nil
		local oldValue, prevReaction = node[VALUE], currentReaction
		currentReaction = nil
		for _, cleanup in cleanups do
			cleanup(oldValue, destroyed)
		end
		currentReaction = prevReaction
	end
end

local function removeSourceObservers(node: node, index: number)
	local sources: { node }? = node[SOURCES]
	if not sources then
		return
	end
	for i = index + 1, #sources do
		local observers: { node } = sources[i][OBSERVERS]
		if observers then
			for j, observer in observers do
				if observer == node then
					observers[j], observers[#observers] = observers[#observers], nil
					break
				end
			end
		end
	end
end

local dispose: (node: node) -> ()

local function disposeChildren(node: node)
	local children = node[CHILDREN]
	if children then
		node[CHILDREN] = nil
		for _, child in children do
			dispose(child)
		end
	end
end

local function normalDispose(node: node)
	disposeChildren(node)

	if node[EFFECT] then
		node[EFFECT] = nil
	end

	doCleanup(node, true)

	local owner = node[OWNER]
	if owner then
		local owned = owner[CHILDREN]
		if owned then
			for i, child in owned do
				if child == node then
					owned[i], owned[#owned] = owned[#owned], nil
					break
				end
			end
		end
	end

	local observers = node[OBSERVERS]
	if observers then
		for _, observer in observers do
			local sources = observer[SOURCES]
			if sources then
				for i, source in sources do
					if source == node then
						sources[i], sources[#sources] = sources[#sources], nil
						break
					end
				end
			end
		end
	end

	removeSourceObservers(node, 0)

	local destroys = node[DESTROYS]
	if destroys then
		local oldValue = node[VALUE]
		for _, onDestroy in destroys do
			onDestroy(oldValue)
		end
	end

	table.clear(node)
end

local function strictDispose(node: node)
	if strict_mode and table.find(scopes, node) then
		error("attempt to destroy an active scope", 0)
	end
	normalDispose(node)
end

dispose = if strict_mode then strictDispose else normalDispose

local function enqueueEffect(node: node)
	if node[EFFECT] then
		effectQueueN += 1
		effectQueue[effectQueueN] = node
	end
end

local function forObservers(node: node, fn: (any) -> ())
	local observers: node? = node[OBSERVERS]
	if observers then
		for _, observer in observers do
			fn(observer)
		end
	end
end

local function staleCheck(node: node)
	if node[STATE] == CLEAN then
		enqueueEffect(node)
		node[STATE] = CHECK
		forObservers(node, staleCheck)
	end
end

local function stale(node: node)
	local state = node[STATE]
	if state < DIRTY then
		if state == CLEAN then
			enqueueEffect(node)
		end
		node[STATE] = DIRTY
		forObservers(node, staleCheck)
	end
end

local function track(node: node): node
	local reaction = currentReaction
	if reaction and node[SEEN] ~= currentEvalId then
		node[SEEN] = currentEvalId
		local gets = currentSources
		if gets then
			table.insert(gets, node)
		else
			local index = currentSourcesIndex + 1
			local sources = reaction[SOURCES]
			if sources and sources[index] == node then
				currentSourcesIndex = index
			else
				currentSources = { node }
			end
		end
	end
	return node
end

local function updateSources(node: node, gets: node)
	removeSourceObservers(node, currentSourcesIndex)
	local sources = node[SOURCES]
	if sources and currentSourcesIndex > 0 then
		local index = currentSourcesIndex
		local newLen = index + #gets
		for i, src in gets do
			sources[index + i] = src
		end
		for i = #sources, newLen + 1, -1 do
			sources[i] = nil
		end
	else
		node[SOURCES], sources = gets, gets
	end
	for i = currentSourcesIndex + 1, #sources do
		local source = sources[i]
		local observer = source[OBSERVERS]
		if observer then
			table.insert(observer, node)
		else
			source[OBSERVERS] = { node }
		end
	end
end

local function reconcileSources(node: node)
	local gets = currentSources
	if gets then
		updateSources(node, gets)
	else
		local sources = node[SOURCES]
		if sources then
			local index, len = currentSourcesIndex, #sources
			if index < len then
				removeSourceObservers(node, index)
				for i = len, index + 1, -1 do
					sources[i] = nil
				end
			end
		end
	end
end

local function propagate(node: node, oldValue: any, newValue: any)
	local observers: node? = node[OBSERVERS]
	if observers then
		local eq: ((any, any) -> boolean)? = node[EQUALS]
		if if eq then not eq(oldValue, newValue) else oldValue ~= newValue then
			for _, observer in observers do
				observer[STATE] = DIRTY
			end
		end
	end
end

local function normalUpdate(node: node)
	local fn, oldValue = node[FN], node[VALUE]

	doCleanup(node, false)
	disposeChildren(node)

	local prevOwner, prevReaction = currentOwner, currentReaction
	local prevEvalId, prevSources, prevIndex = currentEvalId, currentSources, currentSourcesIndex
	evalId += 1
	currentEvalId, currentOwner, currentReaction = evalId, node, node
	currentSources, currentSourcesIndex = nil, 0

	local result = fn(oldValue)

	currentReaction, currentOwner = prevReaction, prevOwner
	reconcileSources(node)
	currentEvalId, currentSources, currentSourcesIndex = prevEvalId, prevSources, prevIndex

	node[STATE], node[VALUE] = CLEAN, result
	propagate(node, oldValue, result)
end

local function efn(err: string)
	local trace = debug.traceback(err, 2)

	if string.find(err, "^effect error stacktrace") then -- if effect error is nested
		trace = string.gsub("    " .. trace, "\n", function() -- indent entire error
			return "\n    "
		end)
	end

	trace ..= "\nsource update stacktrace:"
	return trace
end

local function ycall<T, U>(fn: (T) -> U, arg: T): (boolean, string | U)
	local thread = coroutine.create(xpcall)
	--local function efn(err: string) return debug.traceback(err, 3) end
	local resume_ok, run_ok, result = coroutine.resume(thread, fn, efn, arg)

	assert(resume_ok)

	if coroutine.status(thread) ~= "dead" then
		return false, debug.traceback(thread, "attempt to yield in reactive scope")
	end

	return run_ok, result
end

local function strictUpdate(node: node)
	if table.find(scopes, node) then
		error("a scope, that should rerun due to the update of a source, is already active", 0)
	end

	local fn = node[FN]
	local initialValue = node[VALUE]

	local prevOwner, prevReaction = currentOwner, currentReaction
	local prevEvalId, prevSources, prevIndex = currentEvalId, currentSources, currentSourcesIndex

	for _ = 1, 2 do
		local inValue = node[VALUE]

		doCleanup(node, false)
		disposeChildren(node)

		evalId += 1
		currentEvalId, currentOwner, currentReaction = evalId, node, node
		currentSources, currentSourcesIndex = nil, 0

		local depth = #scopes + 1
		scopes[depth] = node
		local ok, result = ycall(fn, inValue)
		scopes[depth] = nil

		currentReaction, currentOwner = prevReaction, prevOwner

		if not ok then
			currentEvalId, currentSources, currentSourcesIndex = prevEvalId, prevSources, prevIndex
			error(`effect error:\n{result}`, 0)
		end

		reconcileSources(node)
		node[VALUE] = result
	end

	currentEvalId, currentSources, currentSourcesIndex = prevEvalId, prevSources, prevIndex
	node[STATE] = CLEAN
	propagate(node, initialValue, node[VALUE])
end

local function strict(on: boolean?): boolean
	if on == nil then
		return strict_mode
	end
	strict_mode = on
	dispose = if on then strictDispose else normalDispose
	update = if on then strictUpdate else normalUpdate
	return on
end

update = if strict_mode then strictUpdate else normalUpdate

local function updateIfNecessary(node: node)
	if node[STATE] == CHECK then
		local sources: node = node[SOURCES]
		for _, source in sources do
			updateIfNecessary(source)
			if node[STATE] == DIRTY then
				break
			end
		end
	end
	if node[STATE] == DIRTY then
		update(node)
	end
	node[STATE] = CLEAN
end

local function bringCurrent(node: node)
	if node[STATE] == DIRTY then
		update(node)
	elseif node[STATE] == CHECK then
		updateIfNecessary(node)
	end
end

local function peekData(node: node): any
	if node[FN] then
		bringCurrent(node)
		return node[VALUE]
	else
		return node[VALUE]
	end
end

local function getData(node: node): any
	return peekData(track(node))
end

local function setData(node: node, value: any, force: boolean?)
	if force or if node[EQUALS] then not node[EQUALS](node[VALUE], value) else node[VALUE] ~= value then
		node[VALUE] = value
		forObservers(node, stale)
	end
	return value
end

local function raw(object: any): any
	if isNode(object) then
		return peekData(object[NODE_KEY])
	end
	return object
end

local function read(object: any): any
	if isNode(object) then
		return getData(object[NODE_KEY])
	end
	return object
end

local function readDep(object: any): any
	return if type(object) == "function" then (object :: any)() else read(object)
end

local function rawDep(object: any): any
	return if type(object) == "function" then (object :: any)() else raw(object)
end

local function drain(index: number)
	while index <= effectQueueN do
		drainIndex = index
		local node = effectQueue[index]
		effectQueue[index] = nil
		if node[EFFECT] then
			bringCurrent(node)
		end
		index += 1
	end
	effectQueueN = 0
end

local flushing = false
local function flush(index: number?)
	if flushing or effectQueueN == 0 then
		return
	end
	flushing = true
	local start = index or 1
	while true do
		local ok, result = (xpcall :: any)(drain, debug.traceback, start)
		if ok then
			break
		end
		currentOwner, currentReaction, currentSources, currentSourcesIndex = nil, nil, nil, 0
		effectQueue[drainIndex] = nil
		warn(`suppressed effect error:\n{result}`)
		start = drainIndex + 1
	end
	flushing = false
end

local function cleanupFactory(obj: any)
	--stylua: ignore start
	return if type(obj) == "function" then obj :: () -> ()
		elseif typeof(obj) == "RBXScriptConnection" then function() obj:Disconnect() end
		elseif type(obj) == "thread" then function() task.cancel(obj) end
		elseif typeof(obj) == "Instance" then function() obj:Destroy() end
		elseif type(obj.destroy) == "function" then function() (obj :: any):destroy() end
		elseif type(obj.disconnect) == "function" then function() (obj :: any):disconnect() end
		elseif type(obj.Destroy) == "function" then function() (obj :: any):Destroy() end
		elseif type(obj.Disconnect) == "function" then function() (obj :: any):Disconnect() end
		else error "cannot cleanup given object"
	--stylua: ignore end
end

type Destroyable = { destroy: (any) -> () } | { Destroy: (any) -> () }
type Disconnectable = { disconnect: (any) -> () } | { Disconnect: (any) -> () }

local cleanup = function(obj: any)
	local owner = currentOwner
	if not owner then
		error "cannot cleanup outside a reactive owner"
	end

	if type(obj) ~= "function" then
		obj = cleanupFactory(obj)
	end

	local cleanups = owner[CLEANUPS]
	if cleanups then
		table.insert(cleanups, obj)
	else
		owner[CLEANUPS] = { obj }
	end
end :: ((callback: (oldValue: any, destroyed: boolean) -> ()) -> ()) & ((thread: thread) -> ()) & ((instance: Destroyable) -> ()) & ((connection: Disconnectable) -> ()) & ((instance: Instance) -> ()) & ((connection: RBXScriptConnection) -> ())

local function getOwner(): node?
	return currentOwner
end

local function withOwner<T>(node: Node<any>, fn: () -> ...T): T
	local prevOwner = currentOwner
	currentOwner = if node then node[NODE_KEY] else nil
	local ok, result = xpcall(fn, debug.traceback :: any)
	currentOwner = prevOwner
	if not ok then
		error(`error while running withOwner():\n{result}`, 0)
	end
	return result
end

local function untrack<T>(fn: (() -> ...T)?): ...T
	if not fn then
		currentReaction = nil
		return nil
	end
	local prevReaction = currentReaction
	currentReaction = nil
	local results = table.pack(xpcall(fn, debug.traceback :: any))
	currentReaction = prevReaction
	if not results[1] then
		error(`error while running untrack():\n{results[2]}`, 0)
	end
	return table.unpack(results, 2, results.n)
end

local function retrack()
	currentReaction = currentOwner
end

local function onDestroy(node: node, fn: (oldValue: any) -> ())
	local destroys = node[DESTROYS]
	if destroys then
		table.insert(destroys, fn)
	else
		node[DESTROYS] = { fn }
	end
end

local function adopt(node: node): node
	local owner = currentOwner
	if owner then
		node[OWNER] = owner
		local children = owner[CHILDREN]
		if children then
			table.insert(children, node)
		else
			owner[CHILDREN] = { node }
		end
	end
	return node
end

local function wrap<T>(node: { T }): Node<T>
	return setmetatable({ [NODE_KEY] = node }, Node) :: any
end

local function scope<T>(fn: (scope: Node<any>) -> T): (Node<any>, T)
	local node = wrap(adopt({ false, false, false, false, false, false, false, false, false, {} }))

	local prevOwner, prevReaction = currentOwner, currentReaction
	local prevSources, prevSourcesIndex = currentSources, currentSourcesIndex
	currentOwner, currentReaction = node[NODE_KEY], nil
	currentSources, currentSourcesIndex = nil, 0
	local ok, result = xpcall(fn, debug.traceback :: any, node)
	currentOwner, currentReaction = prevOwner, prevReaction
	currentSources, currentSourcesIndex = prevSources, prevSourcesIndex

	if not ok then
		node:Destroy()
		error(`error while running scope():\n{result}`, 0)
	end

	return node, result
end

local function signal<T>(initial: T, equals: ((T, T) -> boolean)?): Node<T>
	return wrap({ initial, false, equals })
end

local function computed<T>(fn: () -> T, equals: ((T, T) -> boolean)?): Node<T>
	return wrap(adopt({ nil :: T, false, equals, false, DIRTY, fn }))
end

local function effect<T>(fn: (T) -> ()): Node<T>
	local node: { T } = adopt({ nil :: T, false, false, false, DIRTY, fn, false, false, true, false })
	enqueueEffect(node)
	return wrap(node)
end

local function new<T>(obj: T, isEffect: boolean?, equals: ((T, T) -> boolean)?): Node<T>
	if type(obj) == "table" and getmetatable(obj) == Node then
		return obj
	end
	if type(obj) == "function" then
		if isEffect then
			return effect(obj)
		end
		return computed(obj, equals)
	end
	return signal(obj, equals)
end

local function destroyPublic<T>(node: NodeData<T>)
	dispose(if isNode(node) then node[NODE_KEY] else node :: node)
end

type NodeData<T> = { _: { T } }
type DataOrNumber = NodeData<number> | number
type DataOrString = NodeData<string> | string

Node = {
	--stylua: ignore start
	-- callable getter/setter shorthand: node() reads, node(v, force?) writes. node(nil) is a
	-- READ (can't tell nil-arg from no-arg cheaply); write nil with node(nil, true) or node:set(nil).
	__call = function<T>(self: NodeData<T>, value: T?, force: any?): T return if force or value ~= nil then setData(self[NODE_KEY], value, force) else getData(self[NODE_KEY]) end,
	--operator overloads to allow Nodes to be used transparently in logic operations
	__concat = function(a: DataOrString, b: DataOrString): string return read(a) .. read(b) end,
	__tostring = function<T>(a: NodeData<T>): string return tostring(getData(a[NODE_KEY])) end,
	__unm = function(a: NodeData<number>): number return -getData(a[NODE_KEY]) end,
	__add = function(a: DataOrNumber, b: DataOrNumber): number return read(a) + read(b) end,
	__sub = function(a: DataOrNumber, b: DataOrNumber): number return read(a) - read(b) end,
	__mul = function(a: DataOrNumber, b: DataOrNumber): number return read(a) * read(b) end,
	__div = function(a: DataOrNumber, b: DataOrNumber): number return read(a) / read(b) end,
	__idiv = function(a: DataOrNumber, b: DataOrNumber): number return read(a) // read(b) end,
	__mod = function(a: DataOrNumber, b: DataOrNumber): number return read(a) % read(b) end,
	__pow = function(a: DataOrNumber, b: DataOrNumber): number return read(a) ^ read(b) end,
	-- comparisons only work directly against other reactive state
	__lt = function<T>(a: NodeData<T>, b: NodeData<T>): boolean return getData(a[NODE_KEY]) < getData(b[NODE_KEY]) end,
	__le = function<T>(a: NodeData<T>, b: NodeData<T>): boolean return getData(a[NODE_KEY]) <= getData(b[NODE_KEY]) end,
	--stylua: ignore end
	__type = NODE_KEY,
}
Node.__index = Node

export type Node<T> = setmetatable<NodeData<T>, typeof(Node)>

--[[
Reads a node's up-to-date value WITHOUT subscribing the caller.

[Open Documentation](https://flux.kohl.gg/guide/concepts/signals#reading-a-signal)
]]
function Node.peek<T>(self: Node<T>): T
	return peekData(self[NODE_KEY])
end

--[[
Reads the node's current value. This is a <strong>tracked</strong> read: when called
inside a [computed](https://flux.kohl.gg/guide/concepts/computeds) or [effect](https://flux.kohl.gg/guide/concepts/effects)
it auto-subscribes the calling computation, so the caller re-runs whenever this node changes.
To read without subscribing, use [`node:peek()`](https://flux.kohl.gg/guide/concepts/tracking#flux-raw).

[Open Documentation](https://flux.kohl.gg/guide/concepts/signals#reading-a-signal)
]]
function Node.get<T>(self: Node<T>): T
	return getData(self[NODE_KEY])
end

--[[
Writes a value, skipping propagation when it is identical (`~=`) to the current one. Pass `force`
as `true` to notify dependents anyway, the idiomatic way to push an in-place table mutation
(same reference) back through the graph.

[Open Documentation](https://flux.kohl.gg/guide/concepts/signals#updating-a-signal)
]]
function Node.set<T>(self: Node<T>, value: T, force: boolean?): T
	return setData(self[NODE_KEY], value, force)
end

--[[
Destroys a node, severing every reactive link to its sources and observers, running any pending
[`Flux.cleanup`](https://flux.kohl.gg/guide/concepts/effects#cleanup-with-flux-cleanup) and
[`node:onDestroy`](https://flux.kohl.gg/guide/concepts/signals#destroying-a-signal) callbacks.
- The node's internal table is stripped, so a later read returns `nil`. Its wrapper and metatable are
  left intact (so [`Flux.isNode`](https://flux.kohl.gg/guide/concepts/components#_3-reading-node-or-value-props-with-flux-read)
  still returns `true`); the emptied wrapper is reclaimed by the garbage collector once unreferenced.

[Open Documentation](https://flux.kohl.gg/guide/concepts/signals#destroying-a-signal)
]]
function Node.Destroy<T>(self: Node<T>)
	dispose(self[NODE_KEY] :: node)
end

--[[
Registers `fn` to run when the node is destroyed: via `node:Destroy()`, or, for a computed/effect, when its
owning [scope](https://flux.kohl.gg/guide/concepts/scopes) is. A plain signal has no owner, so its `fn` fires only on an
explicit `node:Destroy()` (otherwise the signal is just GC'd, silently). Stacks across calls and, unlike
[`Flux.cleanup`](https://flux.kohl.gg/guide/concepts/effects#cleanup-with-flux-cleanup), persists across re-runs.

[Open Documentation](https://flux.kohl.gg/guide/concepts/signals#destroying-a-signal)
]]
function Node.onDestroy<T>(self: Node<T>, fn: (oldValue: T) -> ())
	onDestroy(self[NODE_KEY], fn)
end

local Graph = {
	--[[
Setter/getter for dev-mode strict checks. When on, `update` is swapped for a double-run path:
every reactive scope ([computeds](https://flux.kohl.gg/guide/concepts/computeds) and
[effects](https://flux.kohl.gg/guide/concepts/effects) alike) runs a full second time so
non-idempotent bodies surface in dev, and the graph errors on reactive cycles (re-entering a scope
mid-run) and on destroying the scope that is currently running.
- Pass `true`/`false` to set the flag; call with no argument to read the current state.
- Defaults on in development, off under production.

[Open Documentation](https://flux.kohl.gg/guide/tips/strict#enabling-strict-mode)
]]
	strict = strict,
	--[[
Creates a new reactive Node, the unified constructor: a [signal](https://flux.kohl.gg/guide/concepts/signals) when
`obj` is a plain value, a [computed](https://flux.kohl.gg/guide/concepts/computeds)/[effect](https://flux.kohl.gg/guide/concepts/effects)
when it's a function. (Roblox [`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) dispatch lives in `Bind.node`.)
@param obj - The initial value, or a computation function.
@param isEffect - When `obj` is a function, `true` makes it an effect.
@param equals - An optional equals to short-circuit propagation.
@return Node - The newly created reactive Node.
]]
	new = new,
	--[[
Creates a writable [signal](https://flux.kohl.gg/guide/concepts/signals) holding `initial`.
- Reading it inside a reaction subscribes; writing a new value re-runs dependents.
- An optional `equals` short-circuits propagation when the new value compares equal to the old.
- A signal is NOT owned by the enclosing [scope](https://flux.kohl.gg/guide/concepts/scopes) (unlike a computed/effect); it is reclaimed by the GC when you drop it, not torn down on scope destroy.

[Open Documentation](https://flux.kohl.gg/guide/concepts/signals)
]]
	signal = signal,
	--[[
Creates a lazily-cached derived node from `fn`.
- it re-evaluates only when read after a tracked dependency changed
- an optional `equals` short-circuits propagation on an equal result

[Open Documentation](https://flux.kohl.gg/guide/concepts/computeds)
]]
	computed = computed,
	--[[
Creates an effect node derived from `fn`.
- deferred: queues `fn` to run on the next flush, then re-runs it whenever a tracked dependency changes
- returns the effect node; call `node:Destroy()` to stop it

[Open Documentation](https://flux.kohl.gg/guide/concepts/effects)
]]
	effect = effect,
	--[[
Drains the pending-[effect](https://flux.kohl.gg/guide/concepts/effects) queue immediately, instead of
waiting for the deferred flush. Mainly useful in tests to make effects fire synchronously after a write.

[Open Documentation](https://flux.kohl.gg/guide/tips/testing#deterministic-effects-with-flux-flush)
]]
	flush = flush,
	--[[
Runs `fn` in a fresh owner [scope](https://flux.kohl.gg/guide/concepts/scopes), returning `(scope, result)`: the scope
[node](https://flux.kohl.gg/guide/concepts/signals) and whatever `fn` returned. Computeds, effects, instances, and `cleanup`
callbacks created inside are owned by that scope and torn down together when you call `scope:Destroy()`; plain signals are
not owned and are simply left for the GC.

[Open Documentation](https://flux.kohl.gg/guide/concepts/scopes#creating-a-scope)
]]
	scope = scope,
	--[[
Registers `fn` to run right before the enclosing reactive [scope](https://flux.kohl.gg/guide/concepts/scopes) re-evaluates
(and once more when it is destroyed), letting an effect tear down whatever it set up on the previous run: disconnect events, cancel work, release instances.
- Must be called from inside a [computed](https://flux.kohl.gg/guide/concepts/computeds) or effect body; `fn` receives the node's prior value.

[Open Documentation](https://flux.kohl.gg/guide/concepts/effects#cleanup-with-flux-cleanup)
]]
	cleanup = cleanup,
	--[[
Returns the current owner [scope](https://flux.kohl.gg/guide/concepts/scopes) (a node), or `nil` at the root.
- Capture it to re-establish ownership in deferred or async work via [`Flux.withOwner`](https://flux.kohl.gg/guide/concepts/scopes#capturing-the-active-scope).

[Open Documentation](https://flux.kohl.gg/guide/concepts/scopes#capturing-the-active-scope)
]]
	getOwner = getOwner,
	--[[
Runs `fn` with `node` installed as the current owner [scope](https://flux.kohl.gg/guide/concepts/scopes), so the computeds,
effects, and `cleanup` callbacks created inside attach to it and tear down on its lifetime; dependency [tracking](https://flux.kohl.gg/guide/concepts/tracking) is
left untouched (tracking-transparent).

[Open Documentation](https://flux.kohl.gg/guide/concepts/scopes#capturing-the-active-scope)
]]
	withOwner = withOwner,
	--[[
Suspends dependency [tracking](https://flux.kohl.gg/guide/concepts/tracking) for the duration of `fn` (reads inside don't subscribe the enclosing computed/effect).
- Called bare as `untrack()` it suspends imperatively until a matching `track()` or the next `update()`.

[Open Documentation](https://flux.kohl.gg/guide/concepts/tracking#flux-untrack)
]]
	untrack = untrack,
	--[[
Re-enables dependency [tracking](https://flux.kohl.gg/guide/concepts/tracking) after a bare `Flux.untrack()` call suspended it.
- Use the imperative `untrack()` / `track()` pair to fence a run of un-tracked reads inside a
[computed](https://flux.kohl.gg/guide/concepts/computeds) or [effect](https://flux.kohl.gg/guide/concepts/effects).

[Open Documentation](https://flux.kohl.gg/guide/concepts/tracking#imperative-pairing-flux-untrack-flux-retrack)
]]
	retrack = retrack,
	--[[
Reads a [node](https://flux.kohl.gg/guide/concepts/signals)'s current value <strong>without</strong> tracking it; a
non-node `object` passes straight through, so it is safe to call on a prop that may or may not be reactive.

[Open Documentation](https://flux.kohl.gg/guide/concepts/tracking#flux-raw)
]]
	raw = raw :: <T>(object: Node<T> | T) -> T,
	--[[
Reads a [node](https://flux.kohl.gg/guide/concepts/signals)'s current value <strong>with</strong> tracking, just like
`node:get()`; a non-node `object` passes straight through, making it the idiomatic way to read a prop that may be a
plain value or a node.

[Open Documentation](https://flux.kohl.gg/guide/concepts/tracking#flux-read)
]]
	read = read :: <T>(object: Node<T> | T) -> T,
	readDep = readDep,
	rawDep = rawDep,
	--[[
Returns `true` when `obj` is a reactive [node](https://flux.kohl.gg/guide/concepts/signals). Use it to branch on node-or-value
props inside a component before deciding whether to [read](https://flux.kohl.gg/guide/concepts/tracking) reactively.

[Open Documentation](https://flux.kohl.gg/guide/concepts/components#_3-reading-node-or-value-props-with-flux-read)
]]
	isNode = isNode,
	--[[
Returns `true` when called from within a tracking [computed](https://flux.kohl.gg/guide/concepts/computeds) or
[effect](https://flux.kohl.gg/guide/concepts/effects) body, where reads subscribe the running computation.
]]
	isReactive = isReactive,
	--[[
Destroys a node, severing every reactive link to its sources and observers, running any pending
[`Flux.cleanup`](https://flux.kohl.gg/guide/concepts/effects#cleanup-with-flux-cleanup) and
[`node:onDestroy`](https://flux.kohl.gg/guide/concepts/signals#destroying-a-signal) callbacks.
- The node's internal table is stripped, so a later read returns `nil`. Its wrapper and metatable are
 left intact (so [`Flux.isNode`](https://flux.kohl.gg/guide/concepts/components#_3-reading-node-or-value-props-with-flux-read)
 still returns `true`); the emptied wrapper is reclaimed by the garbage collector once unreferenced.

[Open Documentation](https://flux.kohl.gg/guide/concepts/signals#destroying-a-signal)
]]
	destroy = destroyPublic,
	onDestroy = function(fn: () -> (), scope: Node<any>?)
		if scope then
			onDestroy(if isNode(scope) then (scope :: Node<any>)[NODE_KEY] else scope, fn)
		elseif currentOwner then
			onDestroy(currentOwner, fn)
		end
	end,
	Node = table.freeze(Node),
}

return table.freeze(setmetatable(Graph, table.freeze({ __call = new })))
