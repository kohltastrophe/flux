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

return wrap
