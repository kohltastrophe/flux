--!strict
--!native
--!optimize 2

local Clean = require("./Clean")
local Graph = require("./Graph")
local new = Graph.new
local read = Graph.read

export type Node<T> = Graph.Node<T>

local module = {}

local keyed: (...any) -> () = function(arr, cache, nodes, currentKeys, mapFn, result)
	for index, value in arr do
		currentKeys[value] = true
		if nodes[value] ~= nil then
			nodes[value]:set(index)
		else
			nodes[value] = new(index)
			cache[value] = mapFn(nodes[value], value)
		end
		result[index] = cache[value]
	end
end

local unkeyed: (...any) -> () = function(arr, cache, nodes, currentKeys, mapFn, result)
	for index, value in arr do
		currentKeys[index] = true
		if nodes[index] ~= nil then
			nodes[index]:set(value)
		else
			nodes[index] = new(value)
			cache[index] = mapFn(index, nodes[index])
		end
		result[index] = cache[index]
	end
end

local function createMapper<T>(list: Node<T> | T, mapFn: any, isKeyedByValue: boolean): Node<T>
	local cache: { [any]: any } = {}
	local nodes: { [any]: Node<any> } = {}
	local currentKeys: { [any]: boolean } = {}
	local iter: (...any) -> () = if isKeyedByValue then keyed else unkeyed

	local self = new(function()
		local arr = read(list)
		if type(arr) ~= "table" then
			return {}
		end

		local result = table.create(#arr)

		iter(arr, cache, nodes, currentKeys, mapFn, result)

		for key, cachedResult in cache do
			if currentKeys[key] == nil then
				if nodes[key] then
					nodes[key]:Destroy()
					nodes[key] = nil
				end
				Clean(cachedResult)
				cache[key] = nil
			end
		end
		table.clear(currentKeys)

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

--- Efficiently maps over a table by INDEX (Unkeyed).
--- Preserves mapped results at specific indices, updating the underlying item Node instead.
--- @param list Node<T> | T - The reactive array to map over.
--- @param mapFn (index: number, value: Node<T>) -> U - The mapping function.
--- @return Node<U> - A reactive Node containing the mapped results.
function module.index<T, U>(list: Node<{ T }> | { T }, mapFn: (index: any, item: Node<T>) -> U): Node<{ U }>
	return createMapper(list, mapFn, false)
end

--- Efficiently maps over a table by VALUE (Keyed).
--- Preserves mapped results when items change position in the array.
--- @param list Node<{T}> | {T} - The reactive array to map over.
--- @param mapFn (index: Node<number>, value: T) -> U - The mapping function.
--- @return Node<U> - A reactive Node containing the mapped results.
function module.value<T, U>(list: Node<{ T }> | { T }, mapFn: (index: Node<number>, value: T) -> U): Node<{ U }>
	return createMapper(list, mapFn, true)
end

return module
