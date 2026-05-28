local Bind = require("./Bind")
local Clean = require("./Clean")
local Graph = require("./Graph")
local Find = require("./Find")
local Type = require("./Type")

local FIND_SYMBOL = Find.Symbol
local NODE_SYMBOL = Graph.Node.NODE_SYMBOL

local bindFrom = Bind.from
local bindTo = Bind.to
local isNode = Graph.isNode
local newNode = Graph.new

local function edit(instance: Instance, properties: Type.Map<any>, scope: any): Instance
	local actions = {}
	local signals = {}

	-- Read special keys non-destructively: the same `properties` table may be
	-- reused (e.g. a selector matching multiple instances re-enters edit on each).
	local __ATTR = properties.__ATTR
	local __CLEAN = properties.__CLEAN or {}
	local __EVENT = properties.__EVENT
	local __REF = properties.__REF
	local parent = properties.Parent

	properties.__ATTR = nil
	properties.__CLEAN = nil
	properties.__EVENT = nil
	properties.__REF = nil
	properties.Parent = nil

	for property, value in properties do
		if type(property) == "number" and property == math.floor(property) then -- numeric index
			if typeof(value) == "Instance" then -- child
				if value:IsA("GuiObject") and value.LayoutOrder == 0 then
					value.LayoutOrder = property
				end
				value.Parent = instance
			else
				if type(value) == "function" then -- init action
					table.insert(actions, value)
				elseif type(value) == "table" then
					if value[1] == FIND_SYMBOL then -- selectors
						local result: any = value[2](instance, value[4])
						if typeof(result) == "Instance" then
							edit(result :: Instance, value[3], scope)
						elseif typeof(result) == "table" then
							for _, item in result do
								if typeof(item) ~= "Instance" then
									warn(`Instance expected for query {value[3]}, got {typeof(item)}`)
									continue
								end
								edit(item :: Instance, value[3], scope)
							end
						else
							warn(`Instance expected for query {value[3]}, got {typeof(result)}`)
						end
					elseif value.type == NODE_SYMBOL and value.effect == true then
						table.insert(__CLEAN, Bind.children(value, instance, property))
					end
				end
			end
			continue
		end

		if type(value) == "function" then
			local signal = (instance :: any)[property]
			if typeof(signal) == "RBXScriptSignal" then
				signals[signal] = value -- implicit instance.signal:Connect()
				continue
			end
			value = newNode(value) -- implicit memo
		end

		if isNode(value) == true then -- instance.property <== value
			table.insert(__CLEAN, bindTo(value, instance, property))
		else -- assign to property
			(instance :: any)[property] = value
		end
	end

	if __ATTR ~= nil then
		properties.__ATTR = __ATTR
		for attrName, attrVal in __ATTR do
			if isNode(attrVal) == true then -- instance.attr <== value
				table.insert(__CLEAN, bindTo(attrVal, instance, attrName, true))
			else -- assign to attr
				instance:SetAttribute(attrName, attrVal)
			end
		end
	end

	if __EVENT ~= nil then
		properties.__EVENT = __EVENT
		local __EVENT_ATTR = __EVENT.__ATTR
		__EVENT.__ATTR = nil

		for property, value in __EVENT do
			if isNode(value) == true then -- value <== instance.property
				table.insert(__CLEAN, bindFrom(value, instance, property))
			elseif typeof((instance :: any)[property]) == "RBXScriptSignal" then -- instance.signal:Connect()
				signals[(instance :: any)[property]] = value
			else -- instance.property:Connect()
				table.insert(__CLEAN, instance:GetPropertyChangedSignal(property):Connect(value))
			end
		end

		if __EVENT_ATTR ~= nil then
			__EVENT.__ATTR = __EVENT_ATTR
			for attribute, value in __EVENT_ATTR do
				if isNode(value) == true then -- value <== instance.attr
					table.insert(__CLEAN, bindFrom(value, instance, "$" .. attribute))
				else -- instance.attr:Connect()
					table.insert(__CLEAN, instance:GetAttributeChangedSignal(attribute):Connect(value))
				end
			end
		end
	end

	if __REF ~= nil then
		properties.__REF = __REF
		if type(__REF) == "function" then -- pass reference to callback
			table.insert(__CLEAN, (__REF :: any)(instance))
		elseif isNode(__REF) == true then -- pass reference to value node
			__REF:set(instance)
		end
	end

	for _, action in actions do
		task.defer(action, instance)
	end

	for signal, callback in signals do
		table.insert(__CLEAN, signal:Connect(callback))
	end
	table.clear(signals)

	if next(__CLEAN) then
		local connection = instance.Destroying:Once(function()
			Clean(__CLEAN)
		end)

		if scope ~= nil then
			table.insert(scope.cleanup, connection)
			table.insert(scope.cleanup, __CLEAN)
		end
	end

	if parent ~= nil then
		properties.Parent = parent
		if isNode(properties.Parent) == true then -- reactively drive instance.Parent from node value
			table.insert(__CLEAN, bindTo(parent, instance, "Parent"))
		else -- set Parent last so all children are configured before the instance enters the tree
			instance.Parent = parent
		end
	end

	return instance
end

return edit
