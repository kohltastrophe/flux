--!strict
--!native
--!optimize 2

local Graph = require("./Graph")

local isNode = Graph.isNode
local createNode = Graph.new

local function wrap(obj: { [any]: any }, scope: any?): { [any]: Graph.Node<any> }
	for k, v in obj do
		if isNode(v) then
			continue
		end
		if type(v) == "table" then
			if not isNode(v) then
				wrap(v, scope)
			end
		else
			if scope then
				local node = createNode(v)
				table.insert(scope.cleanup, node)
				obj[k] = node
			else
				obj[k] = createNode(v)
			end
		end
	end

	return obj
end

return wrap
