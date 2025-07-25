local RunService = game:GetService("RunService")

local Type = require(script.Parent.Type)

local State = { deferUpdates = true }
State.__index = State

--- Checks if an object is a Flux state
function State.isState(object: any): boolean
	return type(object) == "table" and getmetatable(object) == State
end
local isState = State.isState

--- Gets the raw value of a Flux state or returns the input if it's not a state
function State.raw<T>(object: T): any
	return if type(object) == "table" and getmetatable(object) == State then object._value else object
end
local raw = State.raw

--- Gets the raw values of multiple Flux states or non-state inputs
function State.rawVariadic(...: any): ...any
	local result = {}
	for _, object in { ... } do
		table.insert(result, raw(object))
	end
	return unpack(result)
end

export type StateData<T> = {
	_binds: { [T]: any },
	_bindConnection: RBXScriptConnection?,
	_boundChildren: { Instance? },
	_boundChildrenLayoutOrder: number?,
	_boundParent: Instance?,
	_connections: Type.Dict<Type.Function>,
	_computation: Type.Function?,
	_dependencies: Type.Set<State<T>>,
	_dependents: Type.Set<State<T>>,
	_tweenInfo: (TweenInfo | any)?,
	_tweenInit: any?,
	_tweenGoal: any?,
	_tweenStart: any?,
	_tweenRepeat: number?,
	_value: T,
}
export type State<T> = typeof(setmetatable({} :: StateData<T>, State))
export type Stateful<T> = T | State<T>

--- Coroutine-based tracking context for automatic dependency detection
local computationContexts: { [thread]: State<any> } = {}

--- Track the state's dependence for the current computation context
function State:_updateDependence()
	if isState(self) then
		local currentComputation = computationContexts[coroutine.running()]
		if currentComputation then
			self._dependents[currentComputation] = true
			currentComputation._dependencies[self] = true
		end
	end
	return self
end
local updateDependence = State._updateDependence

--- Update the value of the state respecting tweens
function State:_updateValue(value: any, noTween: boolean?)
	if not noTween then
		local info = raw(self._tweenInfo)
		if info then
			self._tweenInit = os.clock() + info.DelayTime
			self._tweenGoal = value
			self._tweenStart = self._value
			self._tweenRepeat = info.RepeatCount
			return
		end
	end
	self._value = value
end

function State.__call(self, ...)
	if select("#", ...) == 0 then -- get
		self:_updateDependence()
		return self._value
	end

	local new, forceUpdate, noTween = ...
	local old = self._value

	if forceUpdate or new ~= old or type(old) == "table" then
		self:_updateValue(new, noTween)
		self:_update(forceUpdate, noTween)
	end

	return self
end
function State.__concat(a, b)
	return raw(updateDependence(a)) .. raw(updateDependence(b))
end
function State.__unm(self)
	return -updateDependence(self)._value
end
function State.__add(a, b)
	return raw(updateDependence(a)) + raw(updateDependence(b))
end
function State.__sub(a, b)
	return raw(updateDependence(a)) - raw(updateDependence(b))
end
function State.__mul(a, b)
	return raw(updateDependence(a)) * raw(updateDependence(b))
end
function State.__div(a, b)
	return raw(updateDependence(a)) / raw(updateDependence(b))
end
function State.__idiv(a, b)
	return raw(updateDependence(a)) // raw(updateDependence(b))
end
function State.__mod(a, b)
	return raw(updateDependence(a)) % raw(updateDependence(b))
end
function State.__pow(a, b)
	return raw(updateDependence(a)) ^ raw(updateDependence(b))
end
function State.__tostring(self)
	return tostring(updateDependence(self)._value)
end
function State.__len(self)
	return #updateDependence(self)._value
end

local deferredUpdates: { [State<any>]: { boolean? } } = {}

RunService.Heartbeat:Connect(function()
	for state: Stateful<any>, data: { boolean? } in deferredUpdates do
		task.spawn(state._update, state, nil, data[1], true, data[2])
	end
end)

--- Checks if the state has any dependencies that are deferred for an update
function State:_dependencyUpdating()
	for state: State<any> in self._dependencies do
		if deferredUpdates[state] or state:_dependencyUpdating() then
			return true
		end
	end
	return false
end

function State:_doComputation(noTween: boolean?)
	if type(self._computation) == "function" then
		local currentThread = coroutine.running()
		local previousComputation = computationContexts[currentThread]
		computationContexts[currentThread] = self

		for dependency in self._dependencies do
			dependency._dependents[self] = nil
			self._dependencies[dependency] = nil
		end

		self:_updateValue(raw(updateDependence(self._computation())), noTween)
		computationContexts[currentThread] = previousComputation
	end
end

--- Updates the state and propagates changes to dependents
function State:_update(forceUpdate: boolean?, noTween: boolean?, deferredUpdate: boolean?, tweenUpdate: boolean?)
	if State.deferUpdates and not forceUpdate then
		if not deferredUpdate then
			local cache = deferredUpdates[self]
			if cache then
				cache[1] = noTween
				cache[2] = tweenUpdate
			else
				deferredUpdates[self] = { noTween, tweenUpdate }
			end
			return
		elseif self:_dependencyUpdating() then
			return
		end
	end
	deferredUpdates[self] = nil

	if not tweenUpdate then
		State._doComputation(self, noTween)
	end

	local value = self._value
	if self._binds then -- State -> Instance binding
		for instance: Instance, binds in self._binds do
			for attribute, property in binds do
				if type(attribute) == "string" then -- attribute
					instance:SetAttribute(attribute, value)
				elseif type(property) == "string" then -- property
					instance[property] = value
				end
			end
		end
	end

	if self._boundParent then
		self:_updateBoundChildren()
	end

	for dependent in self._dependents do
		local dependentType = type(dependent)
		if dependentType == "table" then
			if type(dependent._update) == "function" then
				task.spawn(dependent._update, dependent, forceUpdate, noTween, deferredUpdate)
			end
		end
	end

	if self._connections then
		for hook in self._connections do
			if type(hook) == "function" then
				task.spawn(hook, value)
			end
		end
	end
end

--- Updates the children of the state's bound parent instance
function State:_updateBoundChildren()
	local parent = self._boundParent
	if typeof(parent) == "Instance" then
		for _, child in self._boundChildren do
			child.Parent = nil
		end
		table.clear(self._boundChildren)

		local layoutOrder = self._boundChildrenLayoutOrder
		local value = self._value

		if typeof(value) == "Instance" then
			table.insert(self._boundChildren, value)
			if value:IsA("GuiObject") and value.LayoutOrder == 0 then
				value.LayoutOrder = layoutOrder
			end
			value.Parent = parent
		elseif type(value) == "table" then
			for _, child in value do
				if typeof(child) == "Instance" then
					table.insert(self._boundChildren, child)
					if child:IsA("GuiObject") and child.LayoutOrder == 0 then
						child.LayoutOrder = layoutOrder
						layoutOrder += 1
					end
					child.Parent = parent
				end
			end
		end
	end
end

local instanceCache: { [Instance]: { [string]: State<any> } } = {}

--- Binds an instance's property to the state
function State:_bindProperty(instance: Instance, property: string)
	local cache = instanceCache[instance]

	local boundState = cache and cache[property]
	if boundState then
		local binds = boundState._binds[instance]
		if string.find(property, "Attribute.", 1, true) == 1 then
			binds[string.sub(property, #"Attribute." + 1)] = nil
		else -- property
			local foundIndex = table.find(binds, property)
			if foundIndex then
				table.remove(binds, foundIndex)
			end
		end
	end

	if not isState(self) then
		return
	end

	if not self._binds then
		self._binds = { [instance] = {} }
	elseif not self._binds[instance] then
		self._binds[instance] = {}
	end

	if string.find(property, "Attribute.", 1, true) == 1 then
		self._binds[instance][string.sub(property, #"Attribute." + 1)] = true
	else
		table.insert(self._binds[instance], property)
	end

	-- strong reference
	if not cache then
		instanceCache[instance] = { [property] = self }
		instance.Destroying:Once(function()
			for _, state in instanceCache[instance] do
				if state._binds then
					state._binds[instance] = nil
				end
			end
			table.clear(instanceCache[instance])
			instanceCache[instance] = nil
		end)
	else
		cache[property] = self
	end
end

--- Binds the state to an instance's property
function State:_bindToProperty(instance: Instance, property: string)
	if self._bindConnection then
		self._bindConnection:Disconnect()
	end

	if string.find(property, "Attribute.", 1, true) == 1 then
		local attribute = string.sub(property, #"Attribute." + 1)
		self._value = instance:GetAttribute(attribute)

		self._bindConnection = instance:GetAttributeChangedSignal(attribute):Connect(function()
			self(instance:GetAttribute(attribute))
		end)
	else
		self._value = instance[property]
		self._bindConnection = instance:GetPropertyChangedSignal(property):Connect(function()
			self(instance[property])
		end)
	end
end

--- Adds a hook callback function to be called when the state changes
function State:Connect(callback: Type.Function): Type.Function
	if not self._connections then
		self._connections = {}
	end

	self._connections[callback] = true

	return function()
		self._connections[callback] = nil
	end
end

--- Destroys the state, clearing all dependencies and bindings
function State:Destroy()
	setmetatable(self, nil)

	for _, dependency in self._dependencies do
		self._dependencies[dependency] = nil
		dependency._dependents[self] = nil
	end

	if self._bindConnection then
		self._bindConnection:Disconnect()
	end

	if self._binds then
		for instance, properties in self._binds do
			local cache = instanceCache[instance]
			for attribute, property in properties do
				if type(attribute) == "string" then
					cache[attribute] = nil
				elseif type(attribute) == "number" then
					cache[property] = nil
				end
			end
		end
		table.clear(self._binds)
	end

	table.clear(self._dependents)
	table.clear(self)
end

return State
