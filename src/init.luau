local Color = require(script.Color)
local Interpolate = require(script.Interpolate)
local State = require(script.State)
local Spring = require(script.Spring)
local Tween = require(script.Tween)
local Type = require(script.Type)

--- A reactive state management library that makes it easy to create dynamic user interfaces and game logic
local Flux = {
	--- A symbol for defining cleanup in [Flux.edit] and [Flux.new]
	Clean = table.freeze({ type = "Symbol" }) :: Type.Symbol,
	--- A symbol for defining attributes in [Flux.edit] and [Flux.new]
	Attribute = table.freeze({ type = "Symbol" }) :: Type.Symbol,
	--- A symbol for defining events in [Flux.edit] and [Flux.new]
	Event = table.freeze({ type = "Symbol" }) :: Type.Symbol,

	Color = Color,
	Interpolate = Interpolate,
	State = State,
	Type = Type,

	isState = State.isState,
	raw = State.raw,
	rawVariadic = State.rawVariadic,

	--- Creates a computed state, automatically tracking dependencies
	compute = State.compute,
	--- Creates a new Flux state with an initial value
	state = State.new,
	--- Creates a new Flux spring state
	spring = Spring.new,
	--- Creates a new Flux tween state
	tween = Tween.new,

	--- Sets the update defer behaviour, defaults to false to improve performance
	deferUpdates = function(value: boolean?)
		State.deferUpdates = value
	end,
}
Flux.__index = Flux

function Flux.cleanup(obj: any)
	local objType = typeof(obj)
	if objType == "Instance" then
		pcall(game.Destroy, obj)
	elseif objType == "RBXScriptConnection" then
		if obj.Connected then
			obj:Disconnect()
		end
	elseif objType == "function" then
		obj()
	elseif objType == "thread" then
		pcall(task.cancel, obj)
	elseif objType == "table" then
		if typeof(obj.destroy) == "function" then
			obj:destroy()
		elseif typeof(obj.Destroy) == "function" then
			obj:Destroy()
		elseif obj[1] ~= nil then
			for _, subtask in obj do
				Flux.cleanup(subtask)
			end
		elseif typeof(obj[Flux.Clean]) == "table" then
			for _, subtask in obj[Flux.Clean] do
				Flux.cleanup(subtask)
			end
		end
	end
end

type Action = {
	callback: (Instance) -> (),
}

local Action = table.freeze {}

local function isAction(v: any)
	return getmetatable(v) == Action
end

--- Creates an action to run logic on an instance
function Flux.action(callback: (Instance) -> ()): Action
	local action = setmetatable({ callback = callback }, Action)
	return table.freeze(action)
end

local reserved = { Flux.Attribute, Flux.Clean, Flux.Event, "Parent" }

local function processProperties(instance: Instance, properties: Type.Dict<any>)
	local cache = {
		Parent = nil,
		actions = {},
		signals = {},
	}
	for _, key in reserved do
		cache[key] = properties[key]
		properties[key] = nil
	end

	for property, value in properties do
		-- numeric index child definition
		if type(property) == "number" and property == math.floor(property) then
			if typeof(value) == "Instance" then
				if value:IsA("GuiObject") and value.LayoutOrder == 0 then
					value.LayoutOrder = property
				end
				value.Parent = instance
			elseif type(value) == "table" and isAction(value) then
				table.insert(cache.actions, value)
			else
				if type(value) == "function" then
					value = Flux.compute(value)
				end
				if Flux.isState(value) then
					if not value._boundChildren then
						value._boundChildren = {}
					end
					value._boundChildrenLayoutOrder = property
					value._boundParent = instance
					value:_updateBoundChildren()
				end
			end
			continue
		end

		if type(value) == "function" then
			if typeof(instance[property]) == "RBXScriptSignal" then
				cache.signals[instance[property]] = value
				continue
			end
			value = Flux.compute(value)
		end

		State._bindProperty(value, instance, property)
		instance[property] = Flux.raw(value)
	end

	if cache[Flux.Attribute] then
		for attribute, value in cache[Flux.Attribute] do
			State._bindProperty(value, instance, "Attribute." .. attribute)
			instance:SetAttribute(attribute, Flux.raw(value))
		end
	end

	if cache[Flux.Event] then
		local events = cache[Flux.Event]
		local attributeEvents = events[Flux.Attribute]
		events[Flux.Attribute] = nil

		for event, callback in events do
			if typeof(instance[event]) == "RBXScriptSignal" then
				cache.signals[instance[event]] = callback
			else
				instance:GetPropertyChangedSignal(event):Connect(function()
					callback(instance[event])
				end)
			end
		end

		if attributeEvents then
			for attribute, callback in attributeEvents do
				instance:GetAttributeChangedSignal(attribute):Connect(function()
					callback(instance:GetAttribute(attribute))
				end)
			end
		end
	end

	for signal, callback in cache.signals do
		signal:Connect(callback)
	end

	local clean = cache[Flux.Clean] or {}

	for _, action in cache.actions do
		table.insert(clean, task.spawn(action.callback, instance))
	end

	if clean and next(clean) then
		if not clean[Flux.Clean] then
			instance.Destroying:Once(function()
				Flux.cleanup(clean)
			end)
		end
	end

	local parent = cache.Parent
	if parent then
		if type(parent) == "function" then
			parent = Flux.compute(parent)
		end
		State._bindProperty(parent, instance, "Parent")
		instance.Parent = Flux.raw(parent)
	end
end

--- Edits an existing Instance with Flux state bindings and other properties
function Flux.edit<T>(instance: T & Instance, properties: Type.Dict<any>): T
	processProperties(instance, properties)
	return instance
end

local constructors: { [string]: () -> Instance } = {}
setmetatable(constructors, {
	__index = function(self, class: string)
		local function new(properties: Type.Dict<any>): Instance
			return Flux.edit(Instance.new(class), properties)
		end
		self[class] = new
		return new
	end,
})

--- Creates a new Instance with Flux state bindings and other properties
Flux.new = (
	function(classOrInstance: string | Instance): (Type.Dict<any>) -> Instance
		if typeof(classOrInstance) == "Instance" then
			return function(properties: Type.Dict<any>): Instance
				local clone = classOrInstance:Clone()
				if not clone then
					error "Attempt to clone non-archivable instance"
				end
				return Flux.edit(clone, properties)
			end
		end
		return constructors[classOrInstance]
	end :: any
) :: Type.Constructor

return Flux
