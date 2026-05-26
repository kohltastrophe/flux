local Defaults = require("./Defaults")
local Flags = require("./Flags")
local Graph = require("./Graph")
local Edit = require("./Edit")
local Type = require("./Type")

local Async = require("./Async")
local Bind = require("./Bind")
local Clean = require("./Clean")
local For = require("./For")
local Store = require("./Store")
local Wrap = require("./Wrap")

local new = Graph.new

export type Node<T> = Graph.Node<T>
export type Scope = { cleanup: { any }, constructors: any, [any]: any }

local Scope = {
	__call = function<T>(self: Scope, obj: (() -> T) | T, effectOrProperty: boolean? | string?): Node<T>
		if typeof(obj) ~= "Instance" then
			local node = new(obj, effectOrProperty :: boolean)
			table.insert(self.cleanup, node)
			return node
		else
			local node = Bind.from(new(obj), obj, effectOrProperty :: string)
			table.insert(self.cleanup, node)
			return node
		end
	end,
}
Scope.__index = Scope

function Scope.Destroy(self)
	setmetatable(self, nil)
	setmetatable(self.constructors, nil)
	Clean(self.cleanup)
	table.clear(self.constructors)
	table.clear(self.cleanup)
	table.clear(self)
end

-- TODO: create good scope type that works like edit/new

function Scope.edit(self: Scope, instance: Instance)
	return function(properties: Type.Map<any>)
		return Edit(instance, properties, self)
	end
end

function Scope.new(self: Scope, className: string)
	return self.constructors[className] :: any
end

function Scope.async<T, U>(self: Scope, fn: () -> T, initialValue: T?): Async.Async<T>
	local data = Async(fn, initialValue)
	table.insert(self.cleanup, data)
	return data
end

function Scope.forIndex<T, U>(self: Scope, list: Node<T> | T, mapFn: (index: number, item: Node<T>) -> U): Node<U>
	local node = For.index(list, mapFn)
	table.insert(self.cleanup, node)
	return node
end

function Scope.forValue<T, U>(self: Scope, list: Node<T> | T, mapFn: (index: Node<number>, value: T) -> U): Node<U>
	local node = For.value(list, mapFn)
	table.insert(self.cleanup, node)
	return node
end

function Scope.store<T>(self: Scope, initialState: T): T
	local store = Store.new(initialState, self)
	table.insert(self.cleanup, function()
		Store.destroy(store)
	end)
	return store
end

function Scope.wrap(self: Scope, obj: { [any]: any }): { [any]: Node<any> }
	return Wrap(obj, self)
end

local ConstructorsMetatable = {
	__index = function(self, class: string)
		if type(class) ~= "string" then
			error(`String expected, got {typeof(class)}`)
		end

		local scope: Scope? = rawget(self, Scope)

		self[class] = function(properties: Type.Map<any>): Instance
			local instance = Instance.new(class)

			if Flags.defaults and Defaults[class] then
				for k, v in Defaults[class] do
					(instance :: any)[k] = v
				end
			end

			if scope ~= nil then
				table.insert(scope.cleanup, instance)
			end

			return Edit(instance, properties, scope)
		end

		return self[class]
	end :: { [string]: (properties: Type.Map<any>) -> Instance },
}

Scope.ConstructorsMetatable = ConstructorsMetatable

--- Creates a new Scope for easy memory and state management
function Scope.scope(): Scope
	local self = { cleanup = {} }
	self.constructors = setmetatable({ [Scope] = self }, ConstructorsMetatable)

	return setmetatable(self, Scope) :: any
end

return Scope
