local Graph = require("./Graph")

local get = Graph.get
local new = Graph.new

type BindData = {
	fn: { [(value: any) -> ()]: boolean },
	rbx: { [Instance]: { { [string]: true } } },
	children: { cleanupConnection: RBXScriptConnection?, list: { Instance }, parent: Instance?, order: number? }?,
}

local bindData: { [Graph.Node<any>]: BindData } = {}

local function processBinds<T>(node: Graph.Node<T>)
	local bind = bindData[node]
	local value = node.value

	for fn in bind.fn do
		task.spawn(fn, value)
	end

	for instance, syncTo in bind.rbx do
		for attr in syncTo[1] do
			instance:SetAttribute(attr, value)
		end
		for prop in syncTo[2] do
			(instance :: any)[prop] = value
		end
	end

	if bind.children == nil then
		return
	end

	local data = bind.children
	local list = data.list
	local parent = data.parent
	local layoutOrder = data.order or 1
	local children = if type(value) == "table" then value else { value }
	local count = 0

	for _, child in list do
		if child and child.Parent == parent and table.find(children, child) == nil then
			child.Parent = nil
		end
	end
	table.clear(list)

	for _, child in children do
		if typeof(child) == "Instance" then
			if child:IsA("GuiObject") and child.LayoutOrder == 0 then
				child.LayoutOrder = layoutOrder
				layoutOrder += 1
			end
			count += 1
			list[count] = child
			child.Parent = parent
		end
	end
end

local function cleanupChildrenBind<T>(node: Graph.Node<T>, parent: Instance?)
	local data = bindData[node]
	if data and data.children then
		local children = data.children

		if children.cleanupConnection then
			children.cleanupConnection:Disconnect()
		end

		if children.list and #children.list > 0 then
			for _, child in children.list do
				if child and (parent == nil or child.Parent == parent) then
					child.Parent = nil
				end
			end
			table.clear(children.list)
		end

		table.clear(children)
		data.children = nil
	end
end

local function getBindData<T>(node: Graph.Node<T>)
	local data = bindData[node]

	if not data then
		data = { fn = {}, rbx = {}, children = nil :: any }
		bindData[node] = data

		local effect = new(function()
			get(node)
			processBinds(node)
		end, true)

		node:onDestroy(function()
			effect:Destroy()
			table.clear(data.fn)
			table.clear(data.rbx)
			cleanupChildrenBind(node)
			bindData[node] = nil
		end)
	end

	return data
end

local Bind = {}

-- Sync computed children to Instance, where property is the initial LayoutOrder
function Bind.children<T>(node: Graph.Node<T>, parent: Instance, layoutOrder: number?): () -> ()
	local data = getBindData(node)
	local function disconnectBind()
		cleanupChildrenBind(node, parent)
	end

	if data.children == nil then
		data.children = {
			list = {},
			cleanupConnection = parent.Destroying:Once(disconnectBind),
			order = tonumber(layoutOrder) or 1,
			parent = parent,
		}
	else
		local children = data.children
		if children.cleanupConnection then
			children.cleanupConnection:Disconnect()
		end
		children.cleanupConnection = parent.Destroying:Once(disconnectBind)
		children.order = tonumber(layoutOrder) or 1
		children.parent = parent
	end

	return disconnectBind
end

function Bind.listen<T>(node: Graph.Node<T>, fn: (value: T) -> ()): () -> ()
	local fnData = getBindData(node).fn
	fnData[fn] = true

	return function()
		fnData[fn] = nil
	end
end

--- Binds a Node's value from a specific attribute or property on a Roblox Instance.
function Bind.from<T>(node: Graph.Node<T>, instance: Instance, property: string)
	local isAttribute = string.find(property, "$", 1, true) == 1
	local connection: RBXScriptConnection

	if isAttribute then
		local attribute = string.sub(property, 2)
		node.value = instance:GetAttribute(attribute)
		connection = instance:GetAttributeChangedSignal(attribute):Connect(function()
			node:set(instance:GetAttribute(attribute))
		end)
	else
		node.value = (instance :: any)[property]
		connection = instance:GetPropertyChangedSignal(property):Connect(function()
			node:set((instance :: any)[property])
		end)
	end

	node:onDestroy(function()
		connection:Disconnect()
	end)

	return node
end

--- Binds a Node's value to a specific attribute or property on a Roblox Instance.
function Bind.to<T>(node: Graph.Node<T>, instance: Instance, property: string, isAttribute: boolean?)
	local data = getBindData(node)
	local index = if isAttribute then 1 else 2

	local binds = data.rbx[instance]
	if binds == nil then
		binds = { {}, {} }
		data.rbx[instance] = binds
	end

	binds[index][property] = true

	return function()
		binds[index][property] = nil
	end
end

return Bind
