--!strict

local Graph = require("./Graph")

local isNode = Graph.isNode
local createNode = Graph.new

--[[
Recursively replaces every plain leaf in `obj` with a reactive
[node](https://flux.kohl.gg/guide/concepts/signals), <strong>in place</strong>, and returns the same table.
Nested tables are descended into; existing [nodes](https://flux.kohl.gg/guide/concepts/signals) are left
untouched. Handy for boxing a config or props table whose fields you want individually reactive without
writing `Flux.signal` on each one. Created inside a [`Flux.scope`](https://flux.kohl.gg/guide/concepts/scopes),
the new nodes are owned by it.

[Open Documentation](https://flux.kohl.gg/guide/concepts/wrapping#basic-usage)
]]
local function wrap(obj: { [any]: any }): { [any]: Graph.Node<any> }
	for k, v in obj do
		if isNode(v) then
			continue
		end
		if type(v) == "table" then
			wrap(v)
		else
			obj[k] = createNode(v)
		end
	end

	return obj
end

return wrap
