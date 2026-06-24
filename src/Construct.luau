--!strict

local Defaults = require("./Defaults")
local Edit = require("./Edit")
local Flags = require("./Flags")
local Graph = require("./Graph")

local getOwner = Graph.getOwner
local onDestroy = Graph.onDestroy

-- Builds an instance through the standard pipeline: per-class defaults, owner-scoped cleanup
-- (so an instance created inside a scope is destroyed with it), then reactive Edit. The single
-- construction path shared by Flux.new (init.luau) and the Layout helpers.
return function(className: string, properties: any): Instance
	local instance = Instance.new(className)

	local classDefaults = if Flags.defaults then Defaults[className] else nil
	if classDefaults then
		for key, value in classDefaults do
			(instance :: any)[key] = value
		end
	end

	if getOwner() then
		onDestroy(function()
			instance:Destroy()
		end)
	end

	return Edit(instance, properties)
end
