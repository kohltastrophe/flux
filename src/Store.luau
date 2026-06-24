--!strict

local Graph = require("./Graph")
local Compat = require("./Compat")

local new = Graph.new
local newValue = Graph.signal
local get = Graph.Node.get
local setValue = Graph.Node.set
local scope = Graph.scope
local withOwner = Graph.withOwner
local onDestroy = Graph.onDestroy
local isReactive = Graph.isReactive
local warn = Compat.warn

local proxyCache = {} :: { [{ [any]: any }]: any }
local proxyToRaw = {} :: { [any]: { [any]: any } }
local proxyToNodes = {} :: { [any]: { Graph.Node<any> } }
local proxyToOwner = {} :: { [any]: Graph.Node<any> }

local STORE_SYMBOL: any = table.freeze({})

local StoreMetatable
local destroyProxy: (proxy: any) -> ()

-- A store is itself a reactive owner: the per-key/tracker nodes it creates and the
-- proxies nested beneath it are its children, so destroying the store (or the scope it
-- was created in) tears the whole subtree down. `makeOwner` mints a bare owner node
-- adopted by whatever owner is current: the enclosing scope for a top-level store, the
-- parent proxy's owner for a nested one.
local EMPTY = function(): any
	return nil
end
local function makeOwner(): Graph.Node<any>
	local node = scope(EMPTY)
	return node
end

local function createProxy<T>(target: T, parentOwner: Graph.Node<any>?): T
	if proxyCache[target] then
		return proxyCache[target] :: any
	end

	local proxy = setmetatable({}, StoreMetatable)

	proxyCache[target] = proxy
	proxyToRaw[proxy] = target
	proxyToNodes[proxy] = {}

	-- Adopt the parent proxy's owner when nested, else the current scope (if any) so a
	-- store built inside `Flux.scope` dies with it. Created with no current owner the
	-- store is rootless and lives until `Store.destroy`.
	local owner = if parentOwner then withOwner(parentOwner, makeOwner) else makeOwner()
	proxyToOwner[proxy] = owner

	-- Drop the registry entries when the owner is torn down and make the proxy inert. The
	-- owner's children (the per-key nodes and nested-proxy owners) are disposed by the
	-- cascade before this runs, so a nested proxy is stripped here too, not just the root.
	onDestroy(function()
		proxyCache[target] = nil
		proxyToRaw[proxy] = nil
		proxyToNodes[proxy] = nil
		proxyToOwner[proxy] = nil
		setmetatable(proxy, nil)
	end, owner)

	return proxy :: any
end

local function wrapIfPlain(value: any, parentOwner: Graph.Node<any>?): any
	if type(value) == "table" and getmetatable(value) == nil then
		return createProxy(value, parentOwner)
	end
	return value
end

local function teardownDisplaced(target: { [any]: any }, displaced: any)
	if type(displaced) ~= "table" then
		return
	end
	local displacedProxy = proxyCache[displaced]
	if displacedProxy == nil then
		return
	end
	for _, value in target do
		if value == displaced then
			return
		end
	end
	destroyProxy(displacedProxy)
end

local function fireTracker(nodes: { [any]: any }, target: { [any]: any })
	local tracker = nodes[STORE_SYMBOL]
	if tracker then
		setValue(tracker, target, true)
	end
end

local function resyncIndices(nodes: { [any]: any }, target: { [any]: any }, from: number, to: number)
	for i = from, to do
		local node = nodes[i]
		if node then
			setValue(node, target[i])
		end
	end
end

local function readTracker(proxy: any): { [any]: any }
	local target = proxyToRaw[proxy]
	local nodes = proxyToNodes[proxy]

	local tracker = nodes[STORE_SYMBOL]
	if not tracker then
		tracker = withOwner(proxyToOwner[proxy], function()
			return new(target)
		end)
		nodes[STORE_SYMBOL] = tracker
	end
	get(tracker :: any)

	return target
end

local function validatePos(pos: any, max: number): number
	if type(pos) ~= "number" then
		error(`Position must be a number, got {typeof(pos)}`, 3)
	end
	if pos ~= math.floor(pos) or pos < 1 or pos > max then
		error(`Position {pos} out of range [1, {max}]`, 3)
	end
	return pos
end

StoreMetatable = {
	__index = function(proxy, key: any)
		local target = proxyToRaw[proxy]
		local value = rawget(target, key)

		if isReactive() then
			local nodes = proxyToNodes[proxy]
			local node = nodes[key]
			if node == nil then
				node = withOwner(proxyToOwner[proxy], function()
					return newValue(value)
				end)
				nodes[key] = node
			end
			get(node)
		end

		return wrapIfPlain(value, proxyToOwner[proxy])
	end,

	__newindex = function(proxy, key: any, newValue: any)
		local target = proxyToRaw[proxy]
		local rawValue = if type(newValue) == "table" then proxyToRaw[newValue] or newValue else newValue
		local oldValue = rawget(target, key)

		if oldValue ~= rawValue or type(rawValue) == "table" then
			rawset(target, key, rawValue)

			if type(oldValue) == "table" and oldValue ~= rawValue then
				teardownDisplaced(target, oldValue)
			end

			local nodes = proxyToNodes[proxy]
			local node = nodes[key]
			if node ~= nil then
				setValue(node, rawValue)
			end

			fireTracker(nodes, target)
		end
	end,

	__iter = function(proxy)
		local target = readTracker(proxy)
		local owner = proxyToOwner[proxy]
		return function(t: { [any]: any }, k: any): (any, any)
			local key, value = next(t, k)
			return key, wrapIfPlain(value, owner)
		end,
			target
	end,

	__len = function(proxy)
		return #readTracker(proxy)
	end,
}

local Store = {}

--[[
Wraps a plain table in a deep reactive proxy: reading a field inside a
[computed](https://flux.kohl.gg/guide/concepts/computeds) or
[effect](https://flux.kohl.gg/guide/concepts/effects) subscribes to that field, and assigning a new value
re-runs only the dependents of the leaves that changed. Nested plain tables are proxied recursively on
access; metatable'd values (Flux [node](https://flux.kohl.gg/guide/concepts/signals)s, class instances) stay
atomic. Available as `Flux.store`.

[Open Documentation](https://flux.kohl.gg/guide/concepts/stores#creating-a-store)
]]
function Store.new<T>(initialState: T): T
	assert(type(initialState) == "table", "Store initialState must be a table")
	if proxyToRaw[initialState] ~= nil then
		return initialState
	end
	return createProxy(initialState)
end

function destroyProxy(proxy: any)
	-- Disposing the owner cascades to the per-key nodes and every nested-proxy owner, and
	-- each owner's onDestroy clears its registry entries and strips its proxy.
	local owner = proxyToOwner[proxy]
	if owner then
		owner:Destroy()
	end
end

--[[
Tears down a store and every nested proxy beneath it, destroying their backing
[node](https://flux.kohl.gg/guide/concepts/signals)s so dependents stop tracking. Call this when a store
created outside a [scope](https://flux.kohl.gg/guide/concepts/scopes) is no longer needed; the raw table is
left intact and can still be read directly.

[Open Documentation](https://flux.kohl.gg/guide/concepts/stores#destroying-a-store)
]]
function Store.destroy<T>(proxy: T)
	destroyProxy(proxy)
end

--[[
Returns the raw, un-proxied table underlying a store: the live backing object,
not a copy. Reads through it bypass tracking entirely (no
[node](https://flux.kohl.gg/guide/concepts/signals) is subscribed), so use it for cheap snapshots or to hand a
plain table to non-reactive code. Passing a value that is not a store returns it unchanged.

[Open Documentation](https://flux.kohl.gg/guide/concepts/stores#unwrapping-a-store)
]]
function Store.unwrap<T>(proxy: T): T
	return (proxyToRaw[proxy] or proxy) :: T
end

--[[
Reactive counterpart of [`table.insert`](https://create.roblox.com/docs/reference/engine/libraries/table#insert):
inserts `value` at `pos` (default: appended to the end), shifting subsequent elements up. Use this instead of
assigning past the array's length so iteration and `#` watchers fire and the shifted indices re-sync. An
out-of-range `pos` errors.
@param posOrValue - With no third argument, the value to append; otherwise the 1-based position to insert at.
@param value - The value to insert when a position was given.

[Open Documentation](https://flux.kohl.gg/guide/concepts/stores#arrays-and-iteration)
]]
function Store.insert(proxy: any, posOrValue: any, value: any?)
	local target = proxyToRaw[proxy]

	-- Fallback if the user accidentally passes a non-proxy standard table
	if not target then
		if value == nil then
			table.insert(proxy, posOrValue)
		else
			table.insert(proxy, posOrValue, value)
		end
		return
	end

	local pos: number
	local val: any
	if value == nil then
		pos = #target + 1
		val = posOrValue
	else
		pos = validatePos(posOrValue, #target + 1)
		val = value
	end

	-- Prevent proxy-in-proxy nesting
	local rawValue = proxyToRaw[val] or val

	table.insert(target, pos, rawValue)

	local nodes = proxyToNodes[proxy]

	-- If inserted in the middle, we must update the specific nodes for all shifted elements.
	-- If appended to the end, we only check the newly created index.
	if pos <= #target - 1 then
		resyncIndices(nodes, target, pos, #target)
	else
		local node = nodes[pos]
		if node then
			setValue(node, rawValue)
		end
	end

	fireTracker(nodes, target)
end

--[[
Reactive counterpart of [`table.remove`](https://create.roblox.com/docs/reference/engine/libraries/table#remove):
removes and returns the element at `pos` (default: the last), shifting subsequent elements down. Use this
instead of `proxy[i] = nil`, which leaves a hole that corrupts the array part. An out-of-range `pos` errors.

[Open Documentation](https://flux.kohl.gg/guide/concepts/stores#arrays-and-iteration)
]]
function Store.remove(proxy: any, pos: number?): any
	local target = proxyToRaw[proxy]

	-- Fallback if the user accidentally passes a non-proxy standard table
	if not target then
		return table.remove(proxy, pos)
	end

	local length = #target
	if pos ~= nil then
		validatePos(pos, length)
	end
	if length == 0 then
		return nil
	end

	local index = pos or length
	local removed = table.remove(target, index)

	teardownDisplaced(target, removed)

	local nodes = proxyToNodes[proxy]

	resyncIndices(nodes, target, index, length - 1)
	local tailNode = nodes[length]
	if tailNode then
		setValue(tailNode, nil)
	end

	fireTracker(nodes, target)

	return removed
end

--[[
Reactively reorders the array, moving the element at `from` to `to` and shifting the elements between them so
positional readers and `#`/iteration watchers follow. Equivalent to a
[`table.remove`](https://create.roblox.com/docs/reference/engine/libraries/table#remove) +
[`table.insert`](https://create.roblox.com/docs/reference/engine/libraries/table#insert) but as a single tracked
step: the length is unchanged, so nothing is removed and no nested proxy is torn down, ideal for drag-and-drop
list reordering. Both indices must be in `[1, #proxy]`; an out-of-range index errors.
@param from - The 1-based index of the element to move.
@param to - The 1-based index it should occupy afterward.

[Open Documentation](https://flux.kohl.gg/guide/concepts/stores#arrays-and-iteration)
]]
function Store.move(proxy: any, from: number, to: number)
	local target = proxyToRaw[proxy]

	-- Fallback if the user accidentally passes a non-proxy standard table
	if not target then
		table.insert(proxy, to, table.remove(proxy, from))
		return
	end

	local length = #target
	validatePos(from, length)
	validatePos(to, length)
	if from == to then
		return
	end

	-- A reposition, not a resize: shuffle the raw reference, no teardown.
	table.insert(target, to, table.remove(target, from))

	-- Only the indices between the two endpoints changed occupant; re-sync those.
	local nodes = proxyToNodes[proxy]
	resyncIndices(nodes, target, if from < to then from else to, if from < to then to else from)
	fireTracker(nodes, target)
end

local function isArrayLike(t: { [any]: any }): boolean
	return rawget(t, 1) ~= nil
end

local function isArrayIndex(key: any, arrayLen: number): boolean
	return type(key) == "number" and key >= 1 and key <= arrayLen and key == math.floor(key)
end

local reconcileTable: (proxy: any, target: { [any]: any }, newData: { [any]: any }, reconcileKey: string?) -> ()

local function reconcileLeaf(
	target: { [any]: any },
	nodes: { [any]: any },
	key: any,
	rawNew: any,
	reconcileKey: string?
)
	local oldValue = rawget(target, key)
	if oldValue == rawNew then
		return
	end
	if type(oldValue) == "table" and type(rawNew) == "table" and proxyCache[oldValue] ~= nil then
		reconcileTable(proxyCache[oldValue], oldValue, rawNew, reconcileKey)
		return
	end
	rawset(target, key, rawNew)
	if type(oldValue) == "table" then
		teardownDisplaced(target, oldValue)
	end
	local node = nodes[key]
	if node ~= nil then
		setValue(node, rawNew)
	end
end

local function reconcileArray(
	proxy: any,
	target: { [any]: any },
	newData: { [any]: any },
	nodes: { [any]: any },
	reconcileKey: string?
): (number, boolean)
	local oldLen = #target
	local newLen = #newData
	local structural = oldLen ~= newLen

	for i = 1, newLen do
		local newValue = rawget(newData, i)
		local rawNew = if type(newValue) == "table" then proxyToRaw[newValue] or newValue else newValue
		reconcileLeaf(target, nodes, i, rawNew, reconcileKey)
	end

	for i = newLen + 1, oldLen do
		reconcileLeaf(target, nodes, i, nil, reconcileKey)
	end

	return (if oldLen > newLen then oldLen else newLen), structural
end

local function reconcileArrayKeyed(
	proxy: any,
	target: { [any]: any },
	newData: { [any]: any },
	nodes: { [any]: any },
	reconcileKey: string
): (number, boolean)
	local oldLen = #target
	local newLen = #newData
	local structural = oldLen ~= newLen

	local oldElems = table.create(oldLen)
	local oldByKey: { [any]: any } = {}
	for i = 1, oldLen do
		local el = rawget(target, i)
		oldElems[i] = el
		if type(el) == "table" then
			local k = rawget(el, reconcileKey)
			if k ~= nil then
				oldByKey[k] = el
			end
		end
	end

	local matched: { [any]: boolean } = {}
	local seenKeys: { [any]: boolean } = {}
	for i = 1, newLen do
		local newValue = rawget(newData, i)
		local rawNew = if type(newValue) == "table" then proxyToRaw[newValue] or newValue else newValue

		local placed = rawNew
		if type(rawNew) == "table" then
			local k = rawget(rawNew, reconcileKey)
			if k ~= nil then
				if seenKeys[k] then
					warn(
						`Store.reconcile: duplicate key "{tostring(k)}" on field "{reconcileKey}"; keys must be unique or the duplicate aliases one element`
					)
				else
					seenKeys[k] = true
				end
			end
			local reuse = if k ~= nil then oldByKey[k] else nil
			if reuse ~= nil then
				matched[k] = true
				local childProxy = proxyCache[reuse]
				if childProxy ~= nil then
					reconcileTable(childProxy, reuse, rawNew, reconcileKey)
				end
				placed = reuse
			end
		end

		if rawget(target, i) ~= placed then
			structural = true
			rawset(target, i, placed)
			local node = nodes[i]
			if node ~= nil then
				setValue(node, placed)
			end
		end
	end

	for i = newLen + 1, oldLen do
		structural = true
		rawset(target, i, nil)
		local node = nodes[i]
		if node ~= nil then
			setValue(node, nil)
		end
	end

	for i = 1, oldLen do
		local el = oldElems[i]
		if type(el) == "table" then
			local k = rawget(el :: { [any]: any }, reconcileKey)
			if k == nil or matched[k] == nil then
				teardownDisplaced(target, el)
			end
		end
	end

	return (if oldLen > newLen then oldLen else newLen), structural
end

function reconcileTable(proxy: any, target: { [any]: any }, newData: { [any]: any }, reconcileKey: string?)
	local nodes = proxyToNodes[proxy]
	local structural = false

	local arrayLen = 0
	if isArrayLike(target) or isArrayLike(newData) then
		if reconcileKey ~= nil then
			arrayLen, structural = reconcileArrayKeyed(proxy, target, newData, nodes, reconcileKey)
		else
			arrayLen, structural = reconcileArray(proxy, target, newData, nodes, reconcileKey)
		end
	end

	for key, newValue in newData do
		if isArrayIndex(key, arrayLen) then
			continue
		end

		local oldValue = rawget(target, key)
		local rawNew = if type(newValue) == "table" then proxyToRaw[newValue] or newValue else newValue

		if oldValue == nil and rawNew ~= nil then
			structural = true
		end

		reconcileLeaf(target, nodes, key, rawNew, reconcileKey)
	end

	for key, oldValue in target do
		if isArrayIndex(key, arrayLen) then
			continue
		end
		if rawget(newData, key) == nil then
			structural = true
			reconcileLeaf(target, nodes, key, nil, reconcileKey)
		end
	end

	if structural then
		fireTracker(nodes, target)
	end
end

--[[
Diffs the snapshot `newData` into the live store `proxy`, firing only the
[node](https://flux.kohl.gg/guide/concepts/signals)s whose leaves actually changed and reusing unchanged nested
proxies instead of tearing them down, ideal for folding a fresh server payload into existing reactive state
without churning every dependent. Arrays diff positionally (index `i` against index `i`) by default; pass a `key`
field name to match array elements by identity instead, so reordered or inserted rows keep their proxy (and their
[`For.value`](https://flux.kohl.gg/guide/concepts/mapping#flux-forvalue-keyed-by-value) result) and only changed
rows fire, the behaviour of Solid's `reconcile({ key })`. The key applies recursively to every nested array.
`newData` should be a plain, acyclic snapshot. Returns `proxy`.
@param key - Optional field name; when given, array elements are matched by `element[key]` rather than by position.

[Open Documentation](https://flux.kohl.gg/guide/concepts/stores#reconciling-snapshots)
]]
function Store.reconcile<T>(proxy: T, newData: T, key: string?): T
	local target = proxyToRaw[proxy]
	assert(target ~= nil, "Store.reconcile expects a store proxy")
	assert(type(newData) == "table", "Store.reconcile newData must be a table")

	local rawNew = proxyToRaw[newData] or newData
	reconcileTable(proxy, target, rawNew :: any, key)
	return proxy
end

return table.freeze(Store)
