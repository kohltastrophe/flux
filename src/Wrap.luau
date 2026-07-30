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
Makes a table reactive <strong>in place</strong>: every plain leaf of `obj` is replaced with a
[node](https://flux.kohl.gg/guide/concepts/signals) holding its value, recursing through nested tables and
leaving existing [nodes](https://flux.kohl.gg/guide/concepts/signals) untouched. Returns the same table with
its type preserved; each leaf reads back as its original value type, so `wrap({ hp = 100 }).hp()` is a
`number`. Passing a non-table value returns a single node holding it. When created inside a
[`Flux.scope`](https://flux.kohl.gg/guide/concepts/scopes), the new nodes are owned by that scope.

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
			wrap(v)
		else
			(obj :: any)[k] = createNode(v)
		end
	end

	return obj :: any
end

-- Deep-copies plain data tables so wrapping never mutates a shared defaults schema; nodes and
-- other metatabled values pass through by reference (a shared theme node is meant to be shared).
local function cloneDefault(value: any): any
	if type(value) ~= "table" or isNode(value) or getmetatable(value) ~= nil then
		return value
	end
	local copy = table.clone(value)
	for key, child in copy do
		copy[key] = cloneDefault(child)
	end
	return copy
end

--[[
Builds a component props table from a `defaults` schema and the caller's `overrides`. Only keys
declared in `defaults` are taken (unknown override keys are ignored, leaving them for instance
hydration), and the merged result is a <strong>new</strong> table passed through
[`wrap`](https://flux.kohl.gg/guide/concepts/wrapping#basic-usage): plain values become
[node](https://flux.kohl.gg/guide/concepts/signals)s, functions become computeds, and existing
nodes pass through by reference. `defaults` is never mutated; plain nested table defaults are
deep-copied per call, so instances never share state through the schema.

[Open Documentation](https://flux.kohl.gg/guide/concepts/wrapping#props)
]]
local function props<T>(defaults: T, overrides: { [any]: any }?): Wrapped<T>
	local result: { [any]: any } = table.clone(defaults :: any)
	for key, value in result do
		local override = if overrides ~= nil then overrides[key] else nil
		result[key] = if override ~= nil then override else cloneDefault(value)
	end
	return wrap(result) :: any
end

return table.freeze({
	wrap = wrap,
	props = props,
})
