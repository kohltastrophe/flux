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
local bindListen = Bind.listen
local bindTo = Bind.to
local isNode = Graph.isNode
local raw = Graph.raw
local raw = Graph.raw
local newNode = Graph.new
local getOwner = Graph.getOwner
local onDestroy = Graph.onDestroy

--[[
Two-way binds `node` to `instance[property]` (or attribute): drives the
instance from the node first so the authored value wins, then writes the node
back on every instance-side change. Registers both teardowns on `__CLEAN`.
]]
local function bindModel(node: any, instance: Instance, property: string, __CLEAN: { any }, isAttribute: boolean?)
	table.insert(__CLEAN, bindTo(node, instance, property, isAttribute))
	local _, disconnect = bindFrom(node, instance, property, isAttribute)
	table.insert(__CLEAN, disconnect)
end

local task = Compat.task

local function edit(instance: Instance, properties: Type.Map<any>): Instance
	local actions = {}
	local signals = {}

	local __ATTR = properties.__ATTR
	local __USER_CLEAN = properties.__CLEAN
	local __CLEAN = if __USER_CLEAN then table.clone(__USER_CLEAN) else {}
	local __EVENT = properties.__EVENT
	local __TAG = properties.__TAG
	local __TAG = properties.__TAG
	local __REF = properties.__REF
	local parent = properties.Parent

	for property, value in properties do
		if
			property == "Parent"
			or property == "__TAG"
			or property == "__TAG"
			or property == "__ATTR"
			or property == "__CLEAN"
			or property == "__EVENT"
			or property == "__REF"
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
						table.insert(__CLEAN, Bind.children(value, instance, property))
					elseif value[1] ~= MODEL_SYMBOL then -- assume plain array of children
						local order = property
						for _, child in value do
							if typeof(child) == "Instance" then
								order = Bind.applyLayoutOrder(child, order)
								child.Parent = instance
							elseif isNode(child) == true then
								table.insert(__CLEAN, Bind.children(child, instance, order))
								order += 1
							end
						end
					end
				end
			end
			continue
		end

		if type(value) == "table" and value[1] == MODEL_SYMBOL then -- two-way binding (Flux.model)
			bindModel(value[2], instance, property, __CLEAN)
			continue
		end

		if type(value) == "function" then
			local signal = (instance :: any)[property]
			if typeof(signal) == "RBXScriptSignal" then
				signals[signal] = value -- implicit instance.signal:Connect()
				continue
			end
			value = newNode(value) -- implicit memo
			table.insert(__CLEAN, value)
		end

		if isNode(value) == true then -- instance.property <== value
			table.insert(__CLEAN, bindTo(value, instance, property))
		else -- assign to property
			(instance :: any)[property] = value
		end
	end

	if __ATTR then
		for attrName, attrVal in __ATTR do
			if type(attrVal) == "table" and attrVal[1] == MODEL_SYMBOL then -- two-way binding (Flux.model)
				bindModel(attrVal[2], instance, attrName, __CLEAN, true)
			else
				if type(attrVal) == "function" then
					attrVal = newNode(attrVal) -- implicit memo
					table.insert(__CLEAN, attrVal)
				end
				if isNode(attrVal) then -- instance.attr <== value
					table.insert(__CLEAN, bindTo(attrVal, instance, attrName, true))
				else -- assign to attr
					instance:SetAttribute(attrName, attrVal)
				end
			end
		end
	end

	if __TAG then
		for _, tagVal in __TAG do
			if typeof(tagVal) == "function" then
				tagVal = newNode(tagVal)
				table.insert(__CLEAN, tagVal)
			end
			if isNode(tagVal) then
				local previousTag = {} :: { string }
				local function updateTags(newTag)
					if type(newTag) == "table" then
						local newSet = {} :: { [string]: boolean }
						for _, tag in newTag do
							newSet[tag] = true
						end
						for _, tag in previousTag do
							if newSet[tag] then
								newSet[tag] = nil
							else
								instance:RemoveTag(tag)
							end
						end
						for tag in newSet do
							instance:AddTag(tag)
						end
					else
						tagVal:RemoveTag(previousTag)
						tagVal:AddTag(newTag)
					end
					previousTag = newTag
				end

				local disconnect = bindListen(tagVal, updateTags)
				updateTags(raw(tagVal))

				table.insert(__CLEAN, disconnect)
			else
				instance:AddTag(tagVal)
			end
		end
	end

	if __EVENT then
		local __EVENT_ATTR = __EVENT.__ATTR
		__EVENT.__ATTR = nil

		for property, value in __EVENT do
			if isNode(value) == true then -- value <== instance.property
				local _, disconnect = bindFrom(value, instance, property)
				table.insert(__CLEAN, disconnect)
			elseif typeof((instance :: any)[property]) == "RBXScriptSignal" then -- instance.signal:Connect()
				signals[(instance :: any)[property]] = value
			else -- instance.property:Connect()
				local disconnect = instance:GetPropertyChangedSignal(property):Connect(function()
					value((instance :: any)[property])
				end)
				table.insert(__CLEAN, disconnect)
			end
		end

		if __EVENT_ATTR then
			__EVENT.__ATTR = __EVENT_ATTR
			for attribute, value in __EVENT_ATTR do
				if isNode(value) == true then -- value <== instance.attr
					local _, disconnect = bindFrom(value, instance, attribute, true)
					table.insert(__CLEAN, disconnect)
				else -- instance.attr:Connect()
					local disconnect = instance:GetAttributeChangedSignal(attribute):Connect(function()
						value(instance:GetAttribute(attribute))
					end)
					table.insert(__CLEAN, disconnect)
				end
			end
		end
	end

	if __REF then
		if type(__REF) == "function" then -- pass reference to callback
			table.insert(__CLEAN, (__REF :: any)(instance) :: any)
		elseif isNode(__REF) == true then -- pass reference to value node
			__REF:set(instance)
		end
	end

	for _, action in actions do
		task.defer(action, instance)
	end

	for signal, callback in signals do
		table.insert(__CLEAN, signal:Connect(callback) :: any)
	end

	local parentIsNode = isNode(parent) == true

	if parentIsNode or next(__CLEAN) ~= nil then
		local connection = instance.Destroying:Once(function()
			Clean(__CLEAN)
			table.clear(__CLEAN)
		end)

		if getOwner() then
			onDestroy(function()
				connection:Disconnect()
				Clean(__CLEAN)
				table.clear(__CLEAN)
			end)
		end
	end

	if parent then
		if parentIsNode == true then -- reactively drive instance.Parent from node value
			table.insert(__CLEAN, bindTo(parent, instance, "Parent"))
		else
			-- set Parent last so all children are configured before the instance enters the tree
			instance.Parent = parent
		end
	end

	return instance
end

return edit
