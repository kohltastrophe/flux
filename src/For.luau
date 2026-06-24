--!strict

local Clean = require("./Clean")
local Compat = require("./Compat")
local Graph = require("./Graph")
local new = Graph.new
local newValue = Graph.signal
local read = Graph.read
local setValue = Graph.Node.set
local untrack = Graph.untrack
local withOwner = Graph.withOwner

local warn = Compat.warn

export type Node<T> = Graph.Node<T>

local module = {}

local keyed: (...any) -> (number, number) = function(arr, cache, nodes, currentKeys, mapFn, result)
	local seen = 0
	local added = 0
	for index, value in arr do
		if currentKeys[value] ~= nil then
			warn("For.value: duplicate values share one mapped instance (the value is the cache key); use For.index")
		else
			currentKeys[value] = true
			seen += 1
		end
		local node = nodes[value]
		local mapped
		if node ~= nil then
			setValue(node, index)
			mapped = cache[value]
		else
			node = new(index)
			mapped = withOwner(node, function()
				return mapFn(node, value)
			end)
			cache[value] = mapped
			nodes[value] = node
			added += 1
		end
		result[index] = mapped
	end
	return seen, added
end

local unkeyed: (...any) -> (number, number) = function(arr, cache, nodes, currentKeys, mapFn, result)
	local seen = 0
	local added = 0
	for index, value in arr do
		seen += 1
		currentKeys[index] = true
		local node = nodes[index]
		local mapped
		if node ~= nil then
			setValue(node, value)
			mapped = cache[index]
		else
			node = newValue(value)
			mapped = withOwner(node, function()
				return mapFn(index, node)
			end)
			cache[index] = mapped
			nodes[index] = node
			added += 1
		end
		result[index] = mapped
	end
	return seen, added
end

local function createMapper<T>(list: Node<T> | T, mapFn: any, isKeyedByValue: boolean): Node<T>
	local cache: { [any]: any } = {}
	local nodes: { [any]: Node<any> } = {}
	local currentKeys: { [any]: boolean } = {}
	local cacheN = 0
	local rebuildAborted = false
	local iter: (...any) -> (number, number) = if isKeyedByValue then keyed else unkeyed

	local self = new(function()
		local arr = read(list) :: { any }
		if type(arr) ~= "table" then
			return {}
		end

		table.clear(currentKeys)

		local result = table.create(#arr)

		local mustScan = rebuildAborted
		rebuildAborted = true
		untrack()
		-- For owns its per-item index/item nodes itself (the `nodes`/`cache` tables plus the
		-- onDestroy below), so build them with no owner, otherwise they'd adopt this mapper
		-- computed and be disposed on its very next re-run, dropping the cache every frame.
		local seen, added = 0, 0
		withOwner(nil :: any, function()
			seen, added = iter(arr, cache, nodes, currentKeys, mapFn, result)
		end)
		rebuildAborted = false

		if mustScan or seen ~= cacheN + added then
			local liveN = 0
			for key, node in nodes do
				if currentKeys[key] == nil then
					node:Destroy()
					nodes[key] = nil
					Clean(cache[key])
					cache[key] = nil
				else
					liveN += 1
				end
			end
			cacheN = liveN
		else
			cacheN += added
		end

		return result
	end)

	self:onDestroy(function()
		for _, node in nodes do
			node:Destroy()
		end
		for _, cachedResult in cache do
			Clean(cachedResult)
		end
		table.clear(nodes)
		table.clear(cache)
	end)

	return self
end

--[[
Maps an array by <strong>index</strong> (<em>unkeyed</em>): the result at each position is built once and
reused, with the item passed as a reactive [node](https://flux.kohl.gg/guide/concepts/signals) that updates in
place as the value at that index changes. Reach for this over `Flux.forValue` when the array holds
primitives, has duplicates, or churns by position rather than identity.
@param list - The reactive array (a [node](https://flux.kohl.gg/guide/concepts/signals) or plain array) to map over.
@param mapFn - Called once per index; receives the index and a reactive item [node](https://flux.kohl.gg/guide/concepts/signals).

[Open Documentation](https://flux.kohl.gg/guide/concepts/mapping#flux-forindex-keyed-by-index)
]]
function module.index<T, U>(list: Node<{ T }> | { T }, mapFn: (index: any, item: Node<T>) -> U): Node<{ U }>
	return createMapper(list, mapFn, false)
end

--[[
Maps an array by <strong>value</strong> (<em>keyed</em>): each item's mapped result is cached against the value
itself, so results stay stable across reorders and only the item's reactive index
[node](https://flux.kohl.gg/guide/concepts/signals) updates when it moves. Values must be <strong>unique</strong>:
the value is the cache key, so duplicates collapse onto one mapped instance; for primitives, duplicates, or
position-based churn use `Flux.forIndex` instead.
@param list - The reactive array (a [node](https://flux.kohl.gg/guide/concepts/signals) or plain array) to map over.
@param mapFn - Called once per unique value; receives a reactive index [node](https://flux.kohl.gg/guide/concepts/signals) and the value.

[Open Documentation](https://flux.kohl.gg/guide/concepts/mapping#flux-forvalue-keyed-by-value)
]]
function module.value<T, U>(list: Node<{ T }> | { T }, mapFn: (index: Node<number>, value: T) -> U): Node<{ U }>
	return createMapper(list, mapFn, true)
end

return table.freeze(module)
