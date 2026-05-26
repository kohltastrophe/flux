--!strict
--!optimize 2

local Defaults = require("@self/Defaults")
local Edit = require("@self/Edit")
local Find = require("@self/Find")
local Flags = require("@self/Flags")
local Graph = require("@self/Graph")
local Motion = require("@self/Motion")
local Scope = require("@self/Scope")
local Type = require("@self/Type")

local Async = require("@self/Async")
local Bind = require("@self/Bind")
local Clean = require("@self/Clean")
local For = require("@self/For")
local Store = require("@self/Store")
local Wrap = require("@self/Wrap")

local Constructors = setmetatable({}, Scope.ConstructorsMetatable)

local isNode = Graph.isNode
local new = Graph.new

local Flux = {
	Bind = Bind,
	Color = Motion.Color,
	Defaults = Defaults,
	Find = Find,
	Flags = Flags,
	Graph = Graph,
	Motion = Motion,

	isNode = isNode,
	listen = Bind.listen,
	raw = Graph.raw,
	read = Graph.read,
	onCleanup = Graph.onCleanup,

	scope = Scope.scope,

	spring = Motion.spring,
	tween = Motion.tween,

	async = Async,
	clean = Clean,
	forValue = For.value,
	forIndex = For.index,
	store = Store.new,
	wrap = Wrap,
}
Flux.__index = Flux

local FluxMT = {}

--- Creates a new reactive Node.
--- @param obj: any - The initial value, a computation function, or a Roblox Instance.
--- @param effectOrProperty: boolean? | string? - If `obj` is a function, a boolean indicating if it's an effect. If `obj` is an Instance, the property or attribute to bind to.
--- @return Node - The newly created reactive Node.
function FluxMT.__call<T>(self: Graph.Node<T>, obj: (() -> T) | T, effectOrProperty: boolean? | string?): Graph.Node<T>
	if typeof(obj) ~= "Instance" then
		return new(obj, effectOrProperty :: boolean)
	else
		return Bind.from(new(obj), obj, effectOrProperty :: string)
	end
end

--- Edits an Instance with reactive Flux bindings and other properties.
Flux.edit = function(instance: Instance, scope: Scope.Scope?)
	return function(properties: Type.Map<any>)
		return Edit(instance, properties, scope)
	end
end :: Type.Edit

--- Creates a new Instance with reactive Flux bindings and other properties.
Flux.new = function(className: string, scope: Scope.Scope?)
	return Constructors[className] :: any
end :: Type.New

if game then
	local flush = Graph.flush
	local flushQueued = false

	game:GetService("RunService").Heartbeat:Connect(function()
		Motion.step()
		if flushQueued then
			flushQueued = false
			flush()
		end
	end)

	Graph.autoFlush(function()
		if flushQueued == false then
			flushQueued = true
		end
	end)
end

return table.freeze(setmetatable(Flux, FluxMT))
