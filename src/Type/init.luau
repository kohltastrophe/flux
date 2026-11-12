--!strict
-- Type-level machinery for property tables and component props: `Properties`, `EditProperties`, `PropertyType`,
-- `Merge`, `NonNil`, and the child types.

local Graph = require("./Graph")
local Instances = require("@self/Instances")

type Consumer = (...any) -> ()
type GraphNode = Graph.Node<any>

--- @within Flux
--- @private
export type Map<T> = { [T]: any }

type _ATTR = "__ATTR"
type _CLEAN = "__CLEAN"
type _EVENT = "__EVENT"
type _REF = "__REF"
type _TAG = "__TAG"

-- Anything a property table accepts at a numeric index: a child Instance, a node yielding children, an init action
-- run with the instance, or a nested property table flattened into its parent.
export type Child = Instance | GraphNode | ((instance: Instance) -> ()) | { [any]: any }
export type Children = { Child }

--- @within Flux
--- @private
export type function Properties(instance: type?)
	local result = types.newtable(nil, { index = types.number, readresult = types.any, writeresult = types.any })
	-- `__EVENT`: a change listener per property, called with the new value. Signals connect at the top level.
	local events = types.newtable(nil, { index = types.number, readresult = types.never, writeresult = types.never })
	local connectKey = types.singleton("Connect")

	local classes = if instance and (instance:is("intersection") or instance:is("union"))
		then instance:components()
		else { instance }
	for _, component in classes do
		local class: type? = component
		while class and (class:is("extern") or class:is("table")) do
			for i, v in class:properties() do
				local connector = v.read and v.read:is("table") and v.read:readproperty(connectKey)
				if connector then
					local params = connector:parameters().head
					if not params then
						continue
					end
					local listener = params[2]
					if not listener then
						continue
					end
					result:setproperty(i, types.optional(listener))
				else
					if v.read then
						local changedListener = types.optional(types.newfunction({ head = { v.read } }))
						events:setproperty(i, changedListener)
						local propName = i:value()
						if type(propName) == "string" then
							result:setproperty(types.singleton("_" .. propName), changedListener)
						end
					end
					if v.write then
						local t = types.optional(
							types.unionof(v.write, types.newfunction({}, { head = { v.write } }), GraphNode)
						)
						result:setproperty(i, t)
					end
				end
			end

			class = if class:is("extern") then class:readparent() else nil
		end
	end

	local attrListener = types.newfunction({ head = { types.any } })
	local attrEventIndexer = { index = types.string, readresult = attrListener, writeresult = attrListener }
	events:setproperty(_ATTR, types.optional(types.newtable(nil, attrEventIndexer)))
	local tagListener = types.newfunction({ head = { types.boolean } })
	local tagEventIndexer = { index = types.string, readresult = tagListener, writeresult = tagListener }
	events:setproperty(_TAG, types.optional(types.newtable(nil, tagEventIndexer)))

	result:setproperty(types.singleton("_attr_"), types.optional(types.any))
	result:setproperty(
		types.singleton("_tag_"),
		types.optional(types.unionof(types.boolean, GraphNode, types.newfunction({}, { head = { types.any } })))
	)
	result:setproperty(types.singleton("__attr_"), types.optional(attrListener))
	result:setproperty(types.singleton("__tag_"), types.optional(tagListener))

	result:setproperty(
		_ATTR,
		types.optional(types.newtable(nil, { index = types.string, readresult = types.any, writeresult = types.any }))
	)
	local tag = types.unionof(types.string, GraphNode, types.newfunction({}, { head = { types.any } }))
	local tagList = types.newtable(nil, { index = types.number, readresult = tag, writeresult = tag })
	result:setproperty(_TAG, types.optional(types.unionof(tag, tagList)))
	result:setproperty(
		_CLEAN,
		types.optional(types.newtable(nil, { index = types.number, readresult = types.any, writeresult = types.any }))
	)
	result:setproperty(_EVENT, types.optional(events))
	result:setproperty(_REF, types.optional(types.unionof(Consumer, GraphNode)))

	return result
end

-- Merges table types into one, later properties winning. `Flux.Props` uses it to add a component's own props to an
-- instance's property table: a table literal checks against one merged table, but not against an intersection.
--- @within Flux
--- @private
export type function Merge(base: type, extra: type)
	local result = types.newtable()
	local function add(source: type)
		if source:is("intersection") then
			for _, part in source:components() do
				add(part)
			end
			return
		elseif not source:is("table") then
			return
		end
		for key, prop in source:properties() do
			local value = prop.read or prop.write
			if value then
				result:setproperty(key, value)
			end
		end
		local indexer = source:indexer()
		if indexer then
			result:setindexer(indexer.index, indexer.readresult)
		end
	end
	add(base)
	add(extra)
	return result
end

-- The property table `Flux.edit` accepts: the same as `Properties`. Selectors (`Flux.Find`) sit at numeric indices.
--- @within Flux
--- @private
export type EditProperties<T> = Properties<T>

-- The type of `instance[key]` for `Flux.property`: the property's read type, `boolean` for `"#Tag"` / `"_tag_Tag"`, or
-- `any` for `"$Attribute"` / `"_attr_Attribute"`, an event, or a key the class doesn't have (or a key that isn't a
-- string literal).
--- @within Flux
--- @private
export type function PropertyType(instance: type, key: type)
	if not key:is("singleton") then
		return types.any
	end
	local name = key:value()
	if type(name) ~= "string" then
		return types.any
	end
	local prefix = string.sub(name, 1, 1)
	if prefix == "$" then
		return types.any
	elseif prefix == "#" then
		return types.boolean
	elseif prefix == "_" then
		if string.sub(name, 1, 6) == "_attr_" then
			return types.any
		elseif string.sub(name, 1, 5) == "_tag_" then
			return types.boolean
		end
	end

	local classes = if instance:is("intersection") or instance:is("union") then instance:components() else { instance }
	for _, component in classes do
		local class: type? = component
		while class and class:is("extern") do
			for propKey, prop in class:properties() do
				if propKey:value() == name then
					local value = prop.read
					if value == nil or (value:is("table") and value:readproperty(types.singleton("Connect"))) then
						return types.any
					end
					return value
				end
			end
			class = class:readparent()
		end
	end
	return types.any
end

--- @within Flux
--- @private
export type Creatable = Instances.Creatable
--- @within Flux
--- @private
export type Editable = Instances.Editable

--- @within Flux
--- @private
export type Resolve<Name> = index<Creatable & { [string]: Instance }, Name>

--- @within Flux
--- @private
export type function NonNil(t: type): type
	if t:is("nil") then
		return types.never
	elseif not t:is("union") then
		return t
	end
	local parts = {}
	for _, part in t:components() do
		if not part:is("nil") then
			table.insert(parts, part)
		end
	end
	return if #parts == 0 then types.never elseif #parts == 1 then parts[1] else types.unionof(table.unpack(parts))
end

--- @within Flux
--- @private
export type function Truthy(t: type): type
	if t:is("nil") or (t:is("singleton") and t:value() == false) then
		return types.never
	elseif not t:is("union") then
		return t
	end
	local parts = {}
	for _, part in t:components() do
		if not part:is("nil") and not (part:is("singleton") and part:value() == false) then
			table.insert(parts, part)
		end
	end
	return if #parts == 0 then types.never elseif #parts == 1 then parts[1] else types.unionof(table.unpack(parts))
end

return nil
