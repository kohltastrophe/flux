--!strict

local Graph = require("./Graph")

local isNode = Graph.isNode

type Node = Graph.Node<any>
export type Tag = Node | string | (() -> string | { string })
export type tagValue = Tag | { Tag }

local Directive = {}

--[[
One-off form of the `_ATTR` directive: place `Flux.attr("Name", value)` or `Flux.attr { Name = value }`
anywhere in the array portion of a property table to set or bind Roblox attributes on the
[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance). Accepts the same values as
`_ATTR` (static values, reactive [node](https://flux.kohl.gg/guide/concepts/signals)s, functions, and
`Flux.model`).

[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#one-off-directives)
]]
function Directive.attr(attribute: { [string]: any } | string, value: any?): any
	if type(attribute) == "string" then
		if value == nil then
			error(`Flux.attr expects a value for attribute "{attribute}"`, 2)
		end
		return table.freeze({ _ATTR = { [attribute] = value } })
	elseif type(attribute) ~= "table" then
		error(`Flux.attr expects an attribute name or table of attributes, got {typeof(attribute)}`, 2)
	end
	return table.freeze({ _ATTR = attribute })
end

--[[
One-off form of the `_EVENT` directive: place `Flux.event("Name", handler)` or `Flux.event { Name = handler }`
anywhere in the array portion of a property table to connect listeners or bind values <em>from</em> the
[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) into
[node](https://flux.kohl.gg/guide/concepts/signals)s. Accepts the same values as `_EVENT`, including a nested
`_ATTR` map for attribute-changed listeners.

[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#one-off-directives)
]]
function Directive.event(event: { [string]: any } | string, handler: ((...any) -> ()) | Node | nil): any
	if type(event) == "string" then
		if type(handler) ~= "function" and isNode(handler) == false then
			error(`Flux.event expects a handler function or reactive node for "{event}", got {typeof(handler)}`, 2)
		end
		return table.freeze({ _EVENT = { [event] = handler } })
	elseif type(event) ~= "table" then
		error(`Flux.event expects an event name or table of events, got {typeof(event)}`, 2)
	end
	return table.freeze({ _EVENT = event })
end

--[[
One-off form of the `_CLEAN` directive: place `Flux.onDestroy(...)` anywhere in the array portion of a property
table to tie extra teardown (functions, connections, instances, scopes, or arrays of these) to the
[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance)'s
[`Destroying`](https://create.roblox.com/docs/reference/engine/classes/Instance#Destroying) lifetime. Distinct
from `Flux.cleanup`, which registers a callback on the current reactive owner instead.

[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#one-off-directives)
]]
function Directive.onDestroy(...: any): any
	if select("#", ...) == 0 then
		error("Flux.onDestroy expects at least one cleanup item", 2)
	end
	return table.freeze({ _CLEAN = { ... } })
end

--[[
One-off form of the `_REF` directive: place `Flux.ref(nodeOrCallback)` anywhere in the array portion of a
property table to receive the built [`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance).
A [node](https://flux.kohl.gg/guide/concepts/signals) is set to the instance; a callback receives it and may
return a cleanup value tied to the instance's lifetime.

[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#one-off-directives)
]]
function Directive.ref(ref: ((Instance) -> any) | Node): any
	if type(ref) ~= "function" and isNode(ref) == false then
		error(`Flux.ref expects a function or reactive node, got {typeof(ref)}`, 2)
	end
	return table.freeze({ _REF = ref })
end

--[[
One-off form of the `_TAG` directive: place `Flux.tag(...)` anywhere in the array portion of a property table
to manage [CollectionService](https://create.roblox.com/docs/reference/engine/classes/CollectionService) tags on
the [`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance). Each argument accepts the
same values as `_TAG`: a string, a reactive [node](https://flux.kohl.gg/guide/concepts/signals) or function
whose value is a tag or array of tags (diffed on change), or an array of any of these.

[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#one-off-directives)
]]
function Directive.tag(...: tagValue): any
	local tag: tagValue = if select("#", ...) > 1 then { ... } :: any else ...
	local valueType = type(tag)
	if valueType ~= "string" and valueType ~= "table" and valueType ~= "function" then
		error(`Flux.tag expects a string, table, function, or reactive node, got {typeof(tag)}`, 2)
	end
	return table.freeze({ _TAG = tag })
end

return table.freeze(Directive)
