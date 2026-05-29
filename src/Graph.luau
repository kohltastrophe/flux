--!strict
--!native
--!optimize 2

export type NodeState = number
export type NodeType = { type: "Node" }

local STATE_CLEAN: NodeState = 0 -- node value is valid, no need to evaluate
local STATE_CHECK: NodeState = 1 -- node value might be stale, check parents to decide whether to evaluate
local STATE_DIRTY: NodeState = 2 -- node value is invalid, parents have changed, needs to evaluate
local STATE_BUSY: NodeState = 3 -- node value is currently being evaluated

local NODE_SYMBOL = (table.freeze({ type = "Node" }) :: any) :: NodeType

local currentReaction: any
local currentGets: { [any]: any }?
local currentSeenCount: number = 0
local currentVersion: number = 0
local globalVersion: number = 0

local effectQueue: { [any]: any } = {}
local effectSwapQueue: { [any]: any } = {}
local flushHandler: (<T>(node: Node<T>) -> ())?

--- Helper to remove this node from the observer lists of its sources.
local function removeSourceLinks<T>(self: Node<T>)
	if self._sources ~= nil then
		for source in self._sources do
			if source._observers ~= nil then
				source._observers[self] = nil
			end
		end
	end
end

local function updateSourceLinks<T>(node: Node<T>, currentVersion: number)
	local sources = node._sources
	-- Remove sources not seen this run (stale version)
	if sources ~= nil then
		local size = node._sourcesN
		for source, version in sources do
			if version ~= currentVersion then
				if source._observers ~= nil then
					source._observers[node] = nil
				end
				sources[source] = nil
				size -= 1
			end
		end
		node._sourcesN = size
	end

	-- Add new sources
	if currentGets ~= nil then
		if sources == nil then
			sources = {}
			node._sources = sources
			node._sourcesN = 0
		end
		local size = node._sourcesN
		for newSource in currentGets do
			size += 1
			sources[newSource] = currentVersion
			if newSource._observers == nil then
				newSource._observers = { [node] = true }
			else
				newSource._observers[node] = true
			end
		end
		node._sourcesN = size
	end
end

--- Marks the node and its downstream observers as potentially needing an update.
local function stale<T>(node: Node<T>, state: NodeState)
	local nodeState = node.state
	if nodeState == STATE_BUSY then
		error("Cyclic write detected", 2)
	elseif nodeState < state then
		-- If we were previously clean, we may need to update to get the new value
		if nodeState == STATE_CLEAN and node.effect == true then
			effectQueue[node] = true
			if flushHandler then
				flushHandler(node)
			end
		end

		node.state = state
		if node._observers ~= nil then
			for observer in node._observers do
				stale(observer, STATE_CHECK)
			end
		end
	end
end

local function runFn<T>(node: Node<T>)
	local value = node.value
	local cleanup = node._cleanup
	if cleanup ~= nil and #cleanup > 0 then
		for _, fn in cleanup do
			fn(value)
		end
		table.clear(cleanup)
	end
	node.value = (node.fn :: any)()
end

--- Evaluates the reactive function body, dynamically capturing used reactives and marking observers.
local function update<T>(node: Node<T>)
	node.state = STATE_BUSY

	local oldValue = node.value
	local prevReaction = currentReaction
	local prevGets = currentGets
	local prevSeenCount = currentSeenCount
	local prevVersion = currentVersion

	globalVersion += 1
	currentReaction = node
	currentGets = nil
	currentSeenCount = 0
	currentVersion = globalVersion

	local ok, err = pcall(runFn, node)

	if ok then
		-- Only run link updates if sources have changed
		if currentGets ~= nil or node._sources == nil or currentSeenCount ~= node._sourcesN then
			updateSourceLinks(node, currentVersion)
		end
		node.state = STATE_CLEAN
	else
		node.state = STATE_DIRTY
		warn(debug.traceback(err :: string, 2))
	end

	currentVersion = prevVersion
	currentSeenCount = prevSeenCount
	currentGets = prevGets
	currentReaction = prevReaction

	-- Handle diamond dependencies: if we've changed, mark children dirty
	local equals = node.equals
	local changed = if equals ~= nil then not equals(oldValue, node.value) else oldValue ~= node.value
	if node._observers ~= nil and changed then
		for observer in node._observers do
			observer.state = STATE_DIRTY
		end
	end
end

--- Recursively checks upstream dependencies and updates the node if necessary.
local function updateIfNecessary<T>(node: Node<T>)
	if node.state == STATE_CLEAN then
		return
	elseif node.state == STATE_BUSY then
		error("Cyclic read detected", 2)
	-- If potentially dirty, check if any parent has actually changed value
	elseif node.state == STATE_CHECK and node._sources ~= nil then
		for source in node._sources do
			updateIfNecessary(source) -- can change node.state
			if node.state == STATE_DIRTY then
				-- Stop loop: prevent unnecessary updates on other parents
				break
			end
		end
	end

	if node.state == STATE_DIRTY then
		update(node)
	end

	-- update() sets state to STATE_DIRTY on failure; do not overwrite that
	if node.state ~= STATE_DIRTY then
		node.state = STATE_CLEAN
	end
end

--- Evaluates and returns the Node's current value.
--- Automatically tracks this Node as a dependency if called inside another reactive context.
--- @return any - The evaluated value.
local function get<T>(node: Node<T>): T
	if currentReaction then
		local sources = currentReaction._sources
		local version = sources and sources[node]

		if version == nil then
			-- New source not seen in previous runs
			if currentGets == nil then
				currentGets = { [node] = true }
			else
				currentGets[node] = true
			end
		elseif version ~= currentVersion then
			-- Was in previous run; mark as seen this run
			sources[node] = currentVersion
			currentSeenCount += 1
		end
		-- else: already seen this run, dedupe
	end

	-- State check is cheaper than `node.fn` nil-test and skips for value nodes (always CLEAN)
	if node.state ~= STATE_CLEAN then
		updateIfNecessary(node)
	end

	return node.value
end

--- Sets a new value or computation function for the Node.
--- Triggers updates for any downstream observers if the value changes.
--- @param fnOrValue: any - The new primitive value or computation function.
--- @param force: boolean? - If true, forces a reactive update even if the value hasn't strictly changed.
local function set<T, U>(node: Node<T>, fnOrValue: U | () -> U, force: boolean?)
	if type(fnOrValue) == "function" then
		if fnOrValue ~= node.fn and (currentReaction == nil or currentReaction == node) then
			stale(node, STATE_DIRTY)
		end
		node.fn = fnOrValue
	else
		if node.fn then
			removeSourceLinks(node)
			node._sources = nil
			node._sourcesN = nil
			node.fn = nil
			effectQueue[node] = nil
			effectSwapQueue[node] = nil
		end

		local equals = node.equals
		local changed = if equals ~= nil then not equals(node.value, fnOrValue :: any) else node.value ~= fnOrValue
		if changed or force then
			node.value = fnOrValue
			if node._observers ~= nil then
				for observer in node._observers do
					stale(observer, STATE_DIRTY)
				end
			end
		end
	end
end

--- Determines if the provided object is an instance of a reactive Node.
local function isNode(obj: any): boolean
	return type(obj) == "table" and obj.type == NODE_SYMBOL
end

--- Returns true when called from within a reactive computation or effect context.
local function isReactive(): boolean
	return currentReaction ~= nil
end

--- Evaluates the value of a Node without registering it as a reactive dependency. Returns primitive values as-is.
local function raw(obj: any): any
	if type(obj) == "table" and obj.type == NODE_SYMBOL then
		if obj.state ~= STATE_CLEAN then
			updateIfNecessary(obj)
		end
		return obj.value
	else
		return obj
	end
end

--- Evaluates the value of a Node, registering it in the current reactive context. Returns primitive values as-is.
local function read(obj: any): any
	return if type(obj) == "table" and obj.type == NODE_SYMBOL then get(obj) else obj
end

local Node = {
	get = get,
	set = set,
	isNode = isNode,
	raw = raw,
	read = read,

	--stylua: ignore start
	__call = function(self: any, value: any?): any? return if value == nil then get(self) else set(self, value) end,
	-- Operator overloads to allow Nodes to be used transparently in logic operations
	__concat = function(a: any, b: any): string return read(a) .. read(b) end,
	__tostring = function(a: any): string return tostring(get(a)) end,
	__unm = function(a: any): number return -get(a) end,
	__add = function(a: any, b: any): number return read(a) + read(b) end,
	__sub = function(a: any, b: any): number return read(a) - read(b) end,
	__mul = function(a: any, b: any): number return read(a) * read(b) end,
	__div = function(a: any, b: any): number return read(a) / read(b) end,
	__idiv = function(a: any, b: any): number return read(a) // read(b) end,
	__mod = function(a: any, b: any): number return read(a) % read(b) end,
	__pow = function(a: any, b: any): number return read(a) ^ read(b) end,
	-- comparisons only work directly against other reactive state
	__lt = function(a: any, b: any): boolean return get(a) < get(b) end,
	__le = function(a: any, b: any): boolean return get(a) <= get(b) end,
	--stylua: ignore end
}
Node.__index = Node

type NodeData<T> = {
	type: NodeType,
	value: T,
	fn: (() -> T)?,
	state: NodeState,
	effect: boolean?,
	equals: ((a: T, b: T) -> boolean)?,
	_sourcesN: number,
	_sources: { [Node<T>]: number },
	_observers: { [Node<T>]: boolean },
	_cleanup: { (oldValue: any) -> () },
	_destroy: { (Node<T>) -> () },
}

export type Node<T> = setmetatable<NodeData<T>, typeof(Node)>

--- Creates a new reactive Node.
--- @param obj: any - The initial value, a computation function, or a Roblox Instance.
--- @param effect: boolean? - If `obj` is a function, a boolean effect flag
--- @param equals: ((a: T, b: T) -> boolean)? - If `obj` is a function, an optional equals callback to short-circuit propagation when a new value is considered equal to the previous one.
--- @return Node - The newly created reactive Node.
local function createNode<T>(obj: (() -> T) | T, effect: boolean?, equals: ((a: T, b: T) -> boolean)?): Node<T>
	if isNode(obj) then
		return obj :: T
	end

	local isFn = type(obj) == "function"

	local data = {
		type = NODE_SYMBOL,
		value = if not isFn then obj else nil,
		fn = if isFn then obj :: () -> T else nil,
		state = if isFn then STATE_DIRTY else STATE_CLEAN,
		effect = effect,
		equals = equals,
		_sourcesN = nil :: any,
		_sources = nil :: any,
		_observers = nil :: any,
		_cleanup = nil :: any,
		_destroy = nil :: any,
	}

	local self = setmetatable(data, Node) :: Node<T>

	if isFn and self.effect == true then
		effectQueue[self] = true
		if flushHandler then
			flushHandler(self)
		end
	end

	return self
end

--- Destroys the Node, severing all reactive links and calling any registered `onDestroy` callbacks.
function Node.Destroy<T>(self: Node<T>)
	removeSourceLinks(self)
	if self._sources ~= nil then
		table.clear(self._sources)
	end

	-- Sever downstream observers' references to us so they don't recurse into a cleared node
	if self._observers ~= nil then
		for observer in self._observers do
			local observerSources = observer._sources
			if observerSources ~= nil and observerSources[self] ~= nil then
				observerSources[self] = nil
				observer._sourcesN -= 1
			end
		end
		table.clear(self._observers)
	end

	if self._cleanup ~= nil then
		for _, fn in self._cleanup do
			fn(self.value)
		end
		table.clear(self._cleanup)
	end

	if self._destroy ~= nil then
		for _, fn in self._destroy do
			fn(self)
		end
		table.clear(self._destroy)
	end

	effectQueue[self] = nil
	effectSwapQueue[self] = nil

	setmetatable(self, nil)
	table.clear(self :: any)
end

--- Registers a callback to be executed when the Node is destroyed.
--- @param fn: function - The cleanup function to run upon destruction.
function Node.onDestroy<T>(self: Node<T>, fn: (any) -> ())
	if self._destroy == nil then
		self._destroy = { fn }
	else
		self._destroy[#self._destroy + 1] = fn
	end
end

--- Registers a cleanup function to be run right before a reactive function re-evaluates.
--- Must be called inside a reactive computation context.
--- @param fn: function - The cleanup logic to execute.
local function onCleanup(fn: (oldValue: any) -> ())
	if currentReaction then
		if currentReaction._cleanup == nil then
			currentReaction._cleanup = { fn }
		else
			local cleanup: any = currentReaction._cleanup
			cleanup[#cleanup + 1] = fn
		end
	else
		error("onCleanup must be called from within a reactive function", 2)
	end
end

--- Manually flushes the effect queue, evaluating all pending nodes immediately.
local function flush()
	while next(effectQueue) ~= nil do
		local queue = effectQueue
		effectQueue, effectSwapQueue = effectSwapQueue, effectQueue
		for effectNode in queue do
			updateIfNecessary(effectNode)
		end
		table.clear(queue)
	end
end

local flushQueued: boolean = false

--- Queues a flush to happen on the next deferred task cycle.
local function deferredFlush()
	if flushQueued == false then
		flushQueued = true
		task.defer(function()
			flushQueued = false
			flush()
		end)
	end
end

--- Configures the automatic flush behavior.
--- @param fn: function? - A custom flush handler, defaults to `deferredFlush`.
local function autoFlush(fn: (<T>(node: Node<T>) -> ())?)
	flushHandler = fn or deferredFlush
end

return {
	NODE_SYMBOL = NODE_SYMBOL,

	autoFlush = autoFlush,
	flush = flush,
	onCleanup = onCleanup,

	Node = Node,
	isNode = isNode,
	isReactive = isReactive,
	raw = raw,
	read = read,

	new = createNode,
	get = get,
	set = set,
}
