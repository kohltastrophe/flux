--!strict

local Graph = require("./Graph")

local isNode = Graph.isNode
local createNode = Graph.new

type function wrappedType(obj: type, node: type)
	local nodeMT = node:metatable()
	local nodeIndexer = node:indexer()

	local function makeNode(value: type): type
		local mt, indexer = nodeMT, nodeIndexer
		if not mt or not indexer then
			return node -- unexpected shape: fall back to Node<any>
		end
		local payload = types.newtable(nil, { index = types.number, readresult = value, writeresult = value })
		return types.newtable(nil, { index = indexer.index, readresult = payload, writeresult = payload }, mt)
	end

	local function map(t: type): type
		if not t:is("table") then
			return makeNode(t)
		end
		if t:metatable() ~= nil then
			return t
		end

		local result = types.newtable()
		for key, prop in t:properties() do
			local valueType = prop.read or prop.write
			if valueType then
				result:setproperty(key, map(valueType))
			end
		end

		local indexer = t:indexer()
		if indexer then
			result:setindexer(indexer.index, map(indexer.readresult))
		end

		return result
	end

	if obj:is("table") then
		return map(obj)
	elseif obj:is("any") or obj:is("unknown") or obj:is("never") then
		return obj
	end
	return makeNode(obj)
end

export type Wrapped<T> = wrappedType<T, Graph.Node<any>>

--[[
Makes a table reactive <strong>in place</strong>: every plain leaf becomes a
[node](https://flux.kohl.gg/guide/concepts/signals), recursing into nested plain tables and leaving
existing nodes and metatabled tables (a class instance, a proxy) untouched. The table is returned
with its type preserved, so `wrap({ hp = 100 }).hp()` is a `number`. A non-table value returns a
single node holding it.

[Open Documentation](https://flux.kohl.gg/guide/concepts/wrapping#basic-usage)
]]
local function wrap<T>(obj: T): Wrapped<T>
	if type(obj) ~= "table" then
		return createNode(obj) :: any
	end

	for k, v in obj :: { [any]: any } do
		if isNode(v) then
			continue
		end
		if type(v) == "table" then
			if getmetatable(v) == nil then -- a metatabled table is opaque, as in `Wrapped<T>`
				wrap(v)
			end
		else
			(obj :: any)[k] = createNode(v)
		end
	end

	return obj :: any
end

-- Deep-copies plain data tables so wrapping never mutates a table the caller still holds (the
-- defaults schema, a reused override); nodes and other metatabled values are shared by reference.
local function clonePlain(value: any): any
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return value
	end
	local copy = table.clone(value)
	for key, child in copy do
		copy[key] = clonePlain(child)
	end
	return copy
end

--[[
Builds a component props table from a `defaults` schema and the caller's `overrides`, keeping only
keys declared in `defaults` (unknown override keys are left for instance hydration) and passing the
merged result through [`wrap`](https://flux.kohl.gg/guide/concepts/wrapping#basic-usage). Neither
input is mutated: nested plain tables are deep-copied per call, so instances never share state
through the schema or a reused override table.

[Open Documentation](https://flux.kohl.gg/guide/concepts/wrapping#props)
]]
local function props<T, O>(defaults: T, overrides: O?): Wrapped<T>
	local result: { [any]: any } = table.clone(defaults :: any)
	for key, value in result do
		local override = if overrides ~= nil then (overrides :: any)[key] else nil
		result[key] = clonePlain(if override ~= nil then override else value)
	end
	return wrap(result) :: any
end

return table.freeze({
	wrap = wrap,
	props = props,
})
