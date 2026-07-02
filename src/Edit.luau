--!strict

local Bind = require("./Bind")
local Clean = require("./Clean")
local Compat = require("./Compat")
local Graph = require("./Graph")
local Find = require("./Find")
local Type = require("./Type")

local FIND_SYMBOL = Find.Symbol
local MODEL_SYMBOL = Bind.MODEL_SYMBOL

local bindFrom = Bind.from
local bindListen = Bind.listen
local bindTo = Bind.to
local isNode = Graph.isNode
local newNode = Graph.new
local getOwner = Graph.getOwner
local onDestroy = Graph.onDestroy

--[[
Two-way binds `node` to `instance[property]` (or attribute): drives the
instance from the node first so the authored value wins, then writes the node
back on every instance-side change. Registers both teardowns on `_CLEAN`.
]]
local function bindModel(node: any, instance: Instance, property: string, _CLEAN: { any }, isAttribute: boolean?)
	table.insert(_CLEAN, bindTo(node, instance, property, isAttribute))
	local _, disconnect = bindFrom(node, instance, property, isAttribute)
	table.insert(_CLEAN, disconnect)
end

type tagValue = Directive.tagValue

local tagCounts: { [Instance]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any

local function addTagRef(instance: Instance, tag: string)
	local counts = tagCounts[instance]
	if not counts then
		counts = {}
		tagCounts[instance] = counts
	end
	local count = counts[tag]
	counts[tag] = (count or 0) + 1
	if not count then
		instance:AddTag(tag)
	end
end

local function removeTagRef(instance: Instance, tag: string)
	local counts = tagCounts[instance]
	local count = if counts then counts[tag] else nil
	if count and count > 1 then
		counts[tag] = count - 1
	else
		if counts then
			counts[tag] = nil
		end
		instance:RemoveTag(tag)
	end
end

local function bindTag(instance: Instance, tagValue: tagValue, _CLEAN: { any })
	if type(tagValue) == "string" then
		addTagRef(instance, tagValue)
		return
	elseif type(tagValue) == "function" then
		tagValue = newNode(tagValue :: any)
		table.insert(_CLEAN, tagValue)
	end

	if isNode(tagValue) then
		local node = tagValue :: Graph.Node<string>
		local currentSet: { [string]: boolean } = {}

		local function updateTags(newTag: string | { string })
			local newSet: { [string]: boolean } = {}
			if type(newTag) == "table" then
				for _, tag in newTag do
					newSet[tag] = true
				end
			elseif type(newTag) == "string" then
				newSet[newTag] = true
			end

			for tag in newSet do
				if not currentSet[tag] then
					addTagRef(instance, tag)
				end
			end
			for tag in currentSet do
				if not newSet[tag] then
					removeTagRef(instance, tag)
				end
			end

			currentSet = newSet
		end

		table.insert(_CLEAN, bindListen(node, updateTags))
		updateTags(node:peek())
	elseif type(tagValue) == "table" then
		for _, value in tagValue do
			bindTag(instance, value, _CLEAN)
		end
	end
end

local task = Compat.task

local function edit(
	instance: Instance,
	properties: Type.Map<any>,
	seenAttrs: { [any]: boolean }?,
	seenProps: { [any]: boolean }?,
	inheritedClean: { any }?
): Instance
	local actions = {}
	local signals = {}
	local toFlatten: { any }? = nil

	local _ATTR = properties._ATTR
	local _USER_CLEAN = properties._CLEAN
	local _CLEAN = inheritedClean or (if _USER_CLEAN then table.clone(_USER_CLEAN) else {})
	if inheritedClean and _USER_CLEAN then
		for _, item in _USER_CLEAN do
			table.insert(_CLEAN, item)
		end
	end
	local _EVENT = properties._EVENT
	local _TAG = properties._TAG
	local _REF = properties._REF
	local parent = properties.Parent

	-- prevents two nodes fighting over the parent (possible in flattened tables)
	if parent and seenProps then
		if seenProps.Parent then
			parent = nil
		else
			seenProps.Parent = true
		end
	end

	for property, value in properties do
		if
			property == "Parent"
			or property == "_TAG"
			or property == "_ATTR"
			or property == "_CLEAN"
			or property == "_EVENT"
			or property == "_REF"
		then
			continue
		end

		if type(property) == "number" and property == math.floor(property) then -- numeric index
			if typeof(value) == "Instance" then -- child
				Bind.applyLayoutOrder(value, property)
				value.Parent = instance
			else
				if type(value) == "function" then -- init action
					table.insert(actions, value)
				elseif type(value) == "table" then
					if value[1] == FIND_SYMBOL then -- selectors
						Find.resolve(value, instance, function(found: Instance, props: Type.Map<any>)
							edit(found, props)
						end)
					elseif isNode(value) == true then -- children binder (e.g. forValue/forIndex)
						table.insert(_CLEAN, Bind.children(value, instance, property))
					elseif value[1] ~= MODEL_SYMBOL then -- flatten tables into root recursively
						if toFlatten then
							table.insert(toFlatten, value)
						else
							toFlatten = { value }
						end
					end
				end
			end
			continue
		end

		if type(value) == "function" then
			local signal = (instance :: any)[property]
			if typeof(signal) == "RBXScriptSignal" then -- signal shorthand
				signals[signal] = value -- implicit instance.signal:Connect()
				continue
			end

			if seenProps then
				if seenProps[property] then
					continue
				end
				seenProps[property] = true
			end

			value = newNode(value) -- implicit memo
			table.insert(_CLEAN, value)
			table.insert(_CLEAN, bindTo(value, instance, property))
			continue
		end

		if seenProps then
			if seenProps[property] then
				continue
			end
			seenProps[property] = true
		end

		if type(value) == "table" and value[1] == MODEL_SYMBOL then -- two-way binding (Flux.model)
			bindModel(value[2], instance, property, _CLEAN)
			continue
		end

		if isNode(value) then -- instance.property <== value
			table.insert(_CLEAN, bindTo(value, instance, property))
		else -- assign to property
			(instance :: any)[property] = value
		end
	end

	if _ATTR then
		for attrName, attrVal in _ATTR do
			if seenAttrs then
				if seenAttrs[attrName] then
					continue
				end
				seenAttrs[attrName] = true
			end

			if type(attrVal) == "table" and attrVal[1] == MODEL_SYMBOL then -- two-way binding (Flux.model)
				bindModel(attrVal[2], instance, attrName, _CLEAN, true)
			else
				if type(attrVal) == "function" then
					attrVal = newNode(attrVal) -- implicit memo
					table.insert(_CLEAN, attrVal)
				end
				if isNode(attrVal) then -- instance.attr <== value
					table.insert(_CLEAN, bindTo(attrVal, instance, attrName, true))
				else -- assign to attr
					instance:SetAttribute(attrName, attrVal)
				end
			end
		end
	end

	if _TAG then
		bindTag(instance, _TAG, _CLEAN)
	end

	if _EVENT then
		local _EVENT_ATTR = _EVENT._ATTR

		for property, value in _EVENT do
			if property == "_ATTR" then
				continue
			end

			if isNode(value) then -- value <== instance.property
				local _, disconnect = bindFrom(value, instance, property)
				table.insert(_CLEAN, disconnect)
			elseif typeof((instance :: any)[property]) == "RBXScriptSignal" then -- instance.signal:Connect()
				signals[(instance :: any)[property]] = value
			else -- instance.property:Connect()
				local disconnect = instance:GetPropertyChangedSignal(property):Connect(function()
					value((instance :: any)[property])
				end)
				table.insert(_CLEAN, disconnect)
			end
		end

		if _EVENT_ATTR then
			for attribute, value in _EVENT_ATTR do
				if isNode(value) then -- value <== instance.attr
					local _, disconnect = bindFrom(value, instance, attribute, true)
					table.insert(_CLEAN, disconnect)
				else -- instance.attr:Connect()
					local disconnect = instance:GetAttributeChangedSignal(attribute):Connect(function()
						value(instance:GetAttribute(attribute))
					end)
					table.insert(_CLEAN, disconnect)
				end
			end
		end
	end

	if _REF then
		if type(_REF) == "function" then -- pass reference to callback
			table.insert(_CLEAN, (_REF :: any)(instance) :: any)
		elseif isNode(_REF) then -- pass reference to value node
			_REF:set(instance)
		end
	end

	if toFlatten then
		if not seenAttrs then
			seenAttrs = {}
			if _ATTR then
				for attrName in _ATTR do
					seenAttrs[attrName] = true
				end
			end

			seenProps = {}
			for key in properties do
				if type(key) ~= "number" then -- numeric entries never reach the seenProps checks
					seenProps[key] = true
				end
			end
		end

		for _, value in toFlatten do
			edit(instance, value, seenAttrs, seenProps, _CLEAN)
		end
	end

	for _, action in actions do
		task.defer(action, instance)
	end

	for signal, callback in signals do
		table.insert(_CLEAN, signal:Connect(callback) :: any)
	end

	local parentIsNode = isNode(parent)

	-- an inherited _CLEAN belongs to the root pass, which installs the single lifecycle hook
	if not inheritedClean and (parentIsNode or next(_CLEAN) ~= nil) then
		local connection = instance.Destroying:Once(function()
			Clean(_CLEAN)
			table.clear(_CLEAN)
		end)

		if getOwner() then
			onDestroy(function()
				connection:Disconnect()
				Clean(_CLEAN)
				table.clear(_CLEAN)
			end)
		end
	end

	if parent then
		if parentIsNode == true then -- reactively drive instance.Parent from node value
			table.insert(_CLEAN, bindTo(parent, instance, "Parent"))
		else
			-- set Parent last so all children are configured before the instance enters the tree
			instance.Parent = parent
		end
	end

	return instance
end

return edit
