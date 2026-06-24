--!strict

local Graph = require("./Graph")

local new = Graph.new
local newValue = Graph.signal
local get = Graph.Node.get
local readDep = Graph.readDep
local rawDep = Graph.rawDep
local untrack = Graph.untrack
local retrack = Graph.retrack
local withOwner = Graph.withOwner
local setValue = Graph.Node.set
local isReactive = Graph.isReactive

export type Selector<K> = {
	get: (self: Selector<K>, key: K) -> boolean,
	destroy: (self: Selector<K>) -> (),
	_nodes: { [any]: Graph.Node<boolean> },
	_watcher: Graph.Node<any>,
	_equals: ((sourceValue: any, key: K) -> boolean)?,
	_active: any,
}

local SelectorMT = {}
SelectorMT.__index = SelectorMT

--[[
Reactively reads whether `key` is currently selected, returning a `boolean`.
Call inside a [computed](https://flux.kohl.gg/guide/concepts/computeds) or
[effect](https://flux.kohl.gg/guide/concepts/effects) so it re-runs when this key
gains or loses selection. The shorthand `selector(key)` is equivalent to
`selector:get(key)`. Each key tracks its own
[node](https://flux.kohl.gg/guide/concepts/signals), so only the two keys whose
selection actually flipped re-run.

[Open Documentation](https://flux.kohl.gg/guide/concepts/selectors#reading-a-selection)
]]
function SelectorMT.get<K>(self: Selector<K>, key: K): boolean
	local nodes = self._nodes
	local node = nodes[key]
	if node ~= nil then
		return get(node :: Graph.Node<boolean>)
	end

	local equals = self._equals
	local selected = if equals ~= nil then equals(self._active, key) else self._active == key

	if not isReactive() then
		return selected
	end

	-- Per-key nodes are owned by the selector (the `nodes` table + the watcher's onDestroy),
	-- not by the caller reading them, otherwise that reader would adopt and dispose them on
	-- its next re-run. Create them with no owner.
	node = withOwner(nil :: any, function()
		return newValue(selected)
	end)
	nodes[key] = node
	return get(node)
end

-- Calling the selector reads reactively: selector(key) == selector:get(key)
SelectorMT.__call = SelectorMT.get

--[[
Tears down the selector: disposes the internal watcher and every per-key
[node](https://flux.kohl.gg/guide/concepts/signals), then empties the object.
Call when the source [node](https://flux.kohl.gg/guide/concepts/signals) outlives
the selector; a selector created inside a
[scope](https://flux.kohl.gg/guide/concepts/scopes) is cleaned up automatically.

[Open Documentation](https://flux.kohl.gg/guide/concepts/selectors#cleaning-up)
]]
function SelectorMT.destroy<K>(self: Selector<K>)
	if self._watcher == nil then
		return
	end
	self._watcher:Destroy()
	for _, node in self._nodes do
		node:Destroy()
	end
	table.clear(self :: any)
end

--[[
Creates an <strong>O(1)</strong> keyed selector for efficiently tracking which of
many keys matches a single selected value: selecting a row, a tab, or a focused
item. The returned object is callable: `selector(key)` reactively reads whether
`key` is selected, so flipping the selection re-runs only the two affected keys
instead of every observer.
@param source - The tracked selection: a [node](https://flux.kohl.gg/guide/concepts/signals), a `() -> S` [computed](https://flux.kohl.gg/guide/concepts/computeds), or a plain value.
@param equals - Tests the source value against a key (default `==`). The default path flips at most two per-key [node](https://flux.kohl.gg/guide/concepts/signals)s per change (<strong>O(1)</strong>); a custom comparator re-tests every live key per change (<strong>O(live keys)</strong>).

[Open Documentation](https://flux.kohl.gg/guide/concepts/selectors#creating-a-selector)
]]
local function selector<S, K>(
	source: Graph.Node<S> | (() -> S) | S,
	equals: ((sourceValue: S, key: K) -> boolean)?
): Selector<K>
	local self: any = setmetatable({
		_nodes = {},
		_equals = equals,
		_active = rawDep(source),
		_watcher = nil :: any,
	}, SelectorMT)

	local nodes = self._nodes

	self._watcher = new(function()
		local value = readDep(source)
		local prev = self._active
		if prev == value then
			return
		end
		self._active = value

		untrack()
		if equals == nil then
			local prevNode = if prev ~= nil then nodes[prev] else nil
			if prevNode ~= nil then
				setValue(prevNode, false)
			end
			local nextNode = if value ~= nil then nodes[value] else nil
			if nextNode ~= nil then
				setValue(nextNode, true)
			end
		else
			for key, node in nodes do
				setValue(node, equals(value, key))
			end
		end
		retrack()
	end, true)

	self._watcher:onDestroy(function()
		for _, node in nodes do
			node:Destroy()
		end
		table.clear(nodes)
	end)

	return self
end

return table.freeze({
	new = selector,
})
