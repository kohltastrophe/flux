--!strict

local Compat = require("./Compat")
local Graph = require("./Graph")

local get = Graph.Node.get
local new = Graph.new
local raw = Graph.raw
local readDep = Graph.readDep
local untrack = Graph.untrack
local isNode = Graph.isNode
local strict = Graph.strict
local withOwner = Graph.withOwner

local task = Compat.task

-- Marker wrapping a node for two-way binding when used as a property/attribute value in `new`/`edit`
local MODEL_SYMBOL = table.freeze({ type = "Model" }) :: any

type BindData = {
	fn: { [(value: any) -> ()]: boolean },
	rbx: { [Instance]: { { [string]: any } } },
	children: {
		cleanupConnection: RBXScriptConnection?,
		list: { Instance },
		parent: Instance?,
		order: number?,
		token: number?,
	}?,
}

local bindData: { [Graph.Node<any>]: BindData } = setmetatable({}, { __mode = "k" }) :: any
local bindGeneration = 0

local function applyLayoutOrder(child: Instance, order: number): number
	if child:IsA("GuiObject") and (child :: GuiObject).LayoutOrder == 0 then
		(child :: GuiObject).LayoutOrder = order
		return order + 1
	end
	return order
end

local function applyChildren(bind: BindData, value: any)
	if bind.children == nil then
		return
	end

	local data = bind.children
	local list = data.list
	local parent = data.parent
	local layoutOrder = data.order or 1

	if type(value) == "table" then
		local children = value :: { any }
		local count = 0

		if list[1] ~= nil then
			local incoming: { [Instance]: true } = {}
			for _, child in children do
				if typeof(child) == "Instance" then
					incoming[child] = true
				end
			end

			for _, child in list do
				if typeof(child) == "Instance" and child.Parent == parent and incoming[child] == nil then
					child.Parent = nil
				end
			end
			table.clear(list)
		end

		for _, child in children do
			if typeof(child) == "Instance" then
				layoutOrder = applyLayoutOrder(child, layoutOrder)
				count += 1
				list[count] = child
				child.Parent = parent
			end
		end
	else
		for _, child in list do
			if typeof(child) == "Instance" and child.Parent == parent and child ~= value then
				child.Parent = nil
			end
		end
		table.clear(list)

		if typeof(value) == "Instance" then
			local child = value :: Instance
			applyLayoutOrder(child, layoutOrder)
			list[1] = child
			child.Parent = parent
		end
	end
end

local function processBinds(bind: BindData, value: any)
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

	applyChildren(bind, value)
end

local function setProperty(instance: Instance, prop: string, value: any)
	(instance :: any)[prop] = value
end

local function setAttribute(instance: Instance, attr: string, value: any)
	instance:SetAttribute(attr, value)
end

local function addFailure(failures: { string }?, context: string, err: any): { string }
	local list = failures or {}
	table.insert(list, `{context}: {err}`)
	return list
end

-- Strict-mode twin of processBinds: every engine write runs protected, so one failing
-- binding no longer starves the node's remaining bindings, and failures rethrow naming
-- the instance, key, and value that caused them.
local function processBindsStrict(bind: BindData, value: any)
	for fn in bind.fn do
		task.spawn(fn, value)
	end

	local failures: { string }? = nil
	for instance, syncTo in bind.rbx do
		for attr in syncTo[1] do
			local ok, err = pcall(setAttribute, instance, attr, value)
			if not ok then
				failures = addFailure(failures, `attribute "{attr}" of {instance:GetFullName()}`, err)
			end
		end
		for prop in syncTo[2] do
			local ok, err = pcall(setProperty, instance, prop, value)
			if not ok then
				failures = addFailure(failures, `{instance:GetFullName()}.{prop}`, err)
			end
		end
	end

	local ok, err = pcall(applyChildren, bind, value)
	if not ok then
		failures = addFailure(failures, "children binding", err)
	end

	if failures then
		error(`failed to write {tostring(value)} ({typeof(value)}) to:\n\t{table.concat(failures, "\n\t")}`, 0)
	end
end

local function cleanupChildrenBind<T>(node: Graph.Node<T>, parent: Instance?)
	local data = bindData[node]
	if data and data.children then
		local children = data.children

		if children.cleanupConnection then
			children.cleanupConnection:Disconnect()
		end

		if #children.list > 0 then
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
	local data: any = bindData[node]

	if data == nil then
		data = { fn = {}, rbx = {}, children = nil :: any }
		bindData[node] = data

		local effect = withOwner(nil :: any, function()
			return new(function()
				local process: (BindData, any) -> () = if strict() then processBindsStrict else processBinds
				process(data, get(node))
			end, true)
		end)

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

local Bind = {
	applyLayoutOrder = applyLayoutOrder,
	MODEL_SYMBOL = MODEL_SYMBOL,
}

--[[
Wraps a reactive [node](https://flux.kohl.gg/guide/concepts/signals) for <strong>two-way binding</strong>.
Assigning `Flux.model(node)` to a property (or attribute) drives the
[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) from the node AND writes the node
back whenever the user changes that property, the terse equivalent of assigning the node and repeating it under
`_EVENT`. Only sound for properties that fire a changed signal (e.g.
[`TextBox`](https://create.roblox.com/docs/reference/engine/classes/TextBox)`.Text`).

[Open Documentation](https://flux.kohl.gg/guide/roblox/creation#flux-model-two-way-binding-in-one-key)
]]
function Bind.model<T>(node: Graph.Node<T>): T
	if isNode(node) == false then
		error("Flux.model expects a reactive node", 2)
	end
	return (table.freeze({ MODEL_SYMBOL, node }) :: any) :: T
end

--[[
Reactively parents the [node](https://flux.kohl.gg/guide/concepts/signals)'s value (a child
[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) or an array of them) under `parent`,
swapping in the new set and unparenting the old whenever the node updates. `layoutOrder` is the starting
[`LayoutOrder`](https://create.roblox.com/docs/reference/engine/classes/GuiObject#LayoutOrder), auto-assigned to each
child that still has the default `0`. Returns a disconnect that severs the binding and clears the parented children.

[Open Documentation](https://flux.kohl.gg/guide/roblox/creation#creating-hierarchies-children)
]]
function Bind.children<T>(node: Graph.Node<T>, parent: Instance, layoutOrder: number?): () -> ()
	local data = getBindData(node)

	bindGeneration += 1
	local token = bindGeneration
	local function disconnectBind()
		local current = data.children
		if current ~= nil and current.token == token then
			cleanupChildrenBind(node, parent)
		end
	end

	local children = data.children
	if children == nil then
		children = { list = {} }
		data.children = children
	else
		if children.cleanupConnection then
			children.cleanupConnection:Disconnect()
		end
		local oldParent = children.parent
		if oldParent ~= nil and oldParent ~= parent then
			for _, child in children.list do
				if child and child.Parent == oldParent then
					child.Parent = nil
				end
			end
			table.clear(children.list)
		end
	end
	children.cleanupConnection = parent.Destroying:Once(disconnectBind)
	children.order = layoutOrder or 1
	children.parent = parent
	children.token = token

	applyChildren(data, raw(node))

	return disconnectBind
end

--[[
Registers `fn` to run on each update of the [node](https://flux.kohl.gg/guide/concepts/signals), with
[`RBXScriptSignal`](https://create.roblox.com/docs/reference/engine/datatypes/RBXScriptSignal)`:Connect`
semantics: each invocation runs on its own thread (via
[`task.spawn`](https://create.roblox.com/docs/reference/engine/libraries/task#spawn)), so callbacks may yield
freely. Returns an unsubscribe. For synchronous reactive observation, use an effect instead.

[Open Documentation](https://flux.kohl.gg/guide/concepts/effects#effects-vs-flux-listen)
]]
function Bind.listen<T>(node: Graph.Node<T>, fn: (value: T) -> ()): () -> ()
	local fnData = getBindData(node).fn
	fnData[fn] = true

	return function()
		fnData[fn] = nil
	end
end

--[[
Drives the node's value <strong>from</strong> a property or attribute on a Roblox
[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance): seeds the current value and keeps
it in sync via the instance's changed signal. Returns the node and a disconnect.
@param property - The property or attribute name; a leading `$` marks it an attribute when `isAttribute` is nil.
@param isAttribute - Forces attribute (`true`) or property (`false`) lookup, bypassing the `$` convention.

[Open Documentation](https://flux.kohl.gg/guide/concepts/signals#binding-from-an-instance-property)
]]
function Bind.from<T>(node: Graph.Node<T>, instance: Instance, property: string, isAttribute: boolean?)
	if isAttribute == nil and string.find(property, "$", 1, true) == 1 then
		isAttribute = true
		property = string.sub(property, 2)
	end
	local connection: RBXScriptConnection

	if isAttribute then
		local attribute = property
		node:set(instance:GetAttribute(attribute))
		connection = instance:GetAttributeChangedSignal(attribute):Connect(function()
			node:set(instance:GetAttribute(attribute))
		end)
	else
		node:set((instance :: any)[property])
		connection = instance:GetPropertyChangedSignal(property):Connect(function()
			node:set((instance :: any)[property])
		end)
	end

	local function disconnect()
		connection:Disconnect()
	end

	node:onDestroy(disconnect)

	return node, disconnect
end

--[[
The core constructor behind `Flux(...)`: wraps a static value or a computation in a new node, or
(when `obj` is a Roblox [`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance))
binds a new node from one of its properties or attributes. A function `obj` becomes a
[computed](https://flux.kohl.gg/guide/concepts/computeds), or an
[effect](https://flux.kohl.gg/guide/concepts/effects) when `effectOrProperty` is `true`.

[Open Documentation](https://flux.kohl.gg/guide/concepts/signals#creating-a-signal)
]]
function Bind.node<T>(obj: (() -> T) | T, effectOrProperty: boolean? | string?): Graph.Node<T>
	if typeof(obj) ~= "Instance" then
		return new(obj, effectOrProperty :: boolean)
	else
		return (Bind.from(new(obj), obj, effectOrProperty :: string))
	end
end

--[[
Builds an explicit-dependency reaction: it tracks only `deps` (a single
[node](https://flux.kohl.gg/guide/concepts/signals)/function/value or an array of them) and runs `fn` <em>untracked</em>
whenever one changes, so reads inside `fn` never become dependencies. Wrap it in a
[computed](https://flux.kohl.gg/guide/concepts/computeds) or [effect](https://flux.kohl.gg/guide/concepts/effects);
`fn` receives the current input, the previous input, and its own previous result. Set `defer` to skip the first
run and react only to subsequent changes.
@param deps - The dependency, or array of dependencies, to react to.
@param fn - The reaction, run untracked, receiving `(input, prevInput, prevResult)`.
@param defer - Skip the initial run, firing only on later changes.

[Open Documentation](https://flux.kohl.gg/guide/concepts/tracking#flux-on)
]]
function Bind.on<D, R>(
	deps: any,
	fn: (input: any, prevInput: any?, prevResult: R?) -> R,
	defer: boolean?
): (prevResult: R?) -> R?
	local isArray = type(deps) == "table" and not isNode(deps)
	local count = if isArray then #(deps :: { any }) else 0
	local prevInput: any = nil

	return function(prevResult: R?): R?
		local input
		if isArray then
			input = table.create(count)
			for i = 1, count do
				input[i] = readDep(deps[i])
			end
		else
			input = readDep(deps)
		end

		if defer then
			defer = false
			return prevResult
		end

		local result
		untrack(function()
			result = fn(input, prevInput, prevResult)
		end)
		prevInput = input
		return result
	end
end

--[[
Binds the node's value <strong>to</strong> a property or attribute on a Roblox
[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance): writes the current value now and
on every update. Returns an unbind that detaches this binding without affecting other bindings on the same
instance.
@param property - The property or attribute name to write.
@param isAttribute - When `true`, writes a Roblox attribute via `SetAttribute`; otherwise sets the property directly.

[Open Documentation](https://flux.kohl.gg/guide/concepts/signals#binding-to-the-ui)
]]
function Bind.to<T>(node: Graph.Node<T>, instance: Instance, property: string, isAttribute: boolean?)
	local data = getBindData(node)
	local index

	if isAttribute then
		index = 1
		instance:SetAttribute(property, raw(node))
	else
		index = 2
		(instance :: any)[property] = raw(node)
	end

	local binds = data.rbx[instance]
	if binds == nil then
		binds = { {}, {} }
		data.rbx[instance] = binds
	end

	bindGeneration += 1
	local token = bindGeneration
	binds[index][property] = token

	return function()
		if binds[index][property] ~= token then
			return -- stale unbind: a later rebind superseded this binding
		end
		binds[index][property] = nil
		-- Drop the empty per-instance entry so unbound instances aren't pinned
		if next(binds[1]) == nil and next(binds[2]) == nil then
			data.rbx[instance] = nil
		end
	end
end

return table.freeze(Bind)
