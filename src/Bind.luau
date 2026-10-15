--!strict
local Compat = require("./Compat")
local Graph = require("./Graph")
local Type = require("./Type")

local IS_ROBLOX = Compat.isRoblox
local compatTypeof = Compat.typeof
local warn = Compat.warn

local effect = Graph.effect
local get = Graph.Node.get
local new = Graph.new
local signal = Graph.signal
local raw = Graph.raw
local read = Graph.read
local untrack = Graph.untrack
local isNode = Graph.isNode
local isReactive = Graph.isReactive
local withOwner = Graph.withOwner

local MODEL_SYMBOL = table.freeze({ type = "Model" }) :: any
local NOOP = function() end

--- @ignore
type BindData = {
	rbx: { [Instance]: { { [string]: any }? } },
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
local pinnedOrder: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function applyLayoutOrder(child: Instance, order: number): number
	if child:IsA("GuiObject") and (child :: GuiObject).LayoutOrder == 0 and not pinnedOrder[child] then
		(child :: GuiObject).LayoutOrder = order
		return order + 1
	end
	return order
end

local function kindOf(value: any): string
	local kind = typeof(value)
	if kind == "table" and not IS_ROBLOX then
		return compatTypeof(value)
	end
	return kind
end

local function isInstance(value: any): boolean
	return kindOf(value) == "Instance"
end

local function collectChildren(value: any, into: { Instance }): { Instance }
	if isInstance(value) then
		table.insert(into, value)
	elseif isNode(value) then
		collectChildren(get(value), into)
	elseif type(value) == "table" then
		for _, child in value do
			collectChildren(child, into)
		end
	end
	return into
end

local function applyChildren(bind: BindData, value: any)
	local data = bind.children
	if data == nil then
		return
	end
	local list = data.list
	local parent = data.parent
	local layoutOrder = data.order or 1

	while isNode(value) do
		value = get(value)
	end

	if type(value) == "table" and not isInstance(value) then
		local children = collectChildren(value, {})
		if list[1] ~= nil then
			if children[2] == nil then
				local first = children[1]
				for _, child in list do
					if child.Parent == parent and child ~= first then
						child.Parent = nil
					end
				end
			else
				local incoming: { [Instance]: true } = {}
				for _, child in children do
					incoming[child] = true
				end
				for _, child in list do
					if child.Parent == parent and incoming[child] == nil then
						child.Parent = nil
					end
				end
			end
			table.clear(list)
		end
		for count, child in children do
			layoutOrder = applyLayoutOrder(child, layoutOrder)
			list[count] = child
			child.Parent = parent
		end
	else
		for _, child in list do
			if child.Parent == parent and child ~= value then
				child.Parent = nil
			end
		end
		table.clear(list)
		if value ~= nil and isInstance(value) then
			local child = value :: Instance
			applyLayoutOrder(child, layoutOrder)
			list[1] = child
			child.Parent = parent
		end
	end
end

local function setAttribute(instance: Instance, attr: string, value: any)
	instance:SetAttribute(attr, value)
end

local function setProperty(instance: Instance, prop: string, value: any)
	(instance :: any)[prop] = value
end

local function resolveKey(name: string, isAttribute: boolean?): (string, boolean, boolean)
	if isAttribute == nil then
		local first = string.byte(name)
		if first == 36 then
			local attr = string.sub(name, 2)
			if attr == "" then
				error('attribute name after "$" cannot be empty', 4)
			end
			return attr, true, false
		elseif first == 35 then
			local tag = string.sub(name, 2)
			if tag == "" then
				error('tag name after "#" cannot be empty', 4)
			end
			return tag, false, true
		elseif first == 95 then
			if string.sub(name, 1, 6) == "_attr_" then
				local attr = string.sub(name, 7)
				if attr == "" then
					error('attribute name after "_attr_" cannot be empty', 4)
				end
				return attr, true, false
			elseif string.sub(name, 1, 5) == "_tag_" then
				local tag = string.sub(name, 6)
				if tag == "" then
					error('tag name after "_tag_" cannot be empty', 4)
				end
				return tag, false, true
			end
		end
		return name, false, false
	end
	return name, isAttribute, false
end

local function onTagChanged(instance: Instance, tag: string, fn: (hasTag: boolean) -> ()): () -> ()
	local collectionService = Compat.getService("CollectionService")
	if collectionService == nil then
		return NOOP
	end
	local last = instance:HasTag(tag)
	local function check(inst: Instance)
		if inst == instance then
			local current = instance:HasTag(tag)
			if current ~= last then
				last = current
				fn(current)
			end
		end
	end
	local added = collectionService:GetInstanceAddedSignal(tag):Connect(check)
	local removed = collectionService:GetInstanceRemovedSignal(tag):Connect(check)
	local ancestry = instance.AncestryChanged:Connect(function()
		check(instance)
	end)
	return function()
		added:Disconnect()
		removed:Disconnect()
		ancestry:Disconnect()
	end
end

local function onChanged(
	instance: Instance,
	name: string,
	isAttribute: boolean?,
	fn: (value: any) -> ()
): RBXScriptConnection
	if isAttribute then
		return instance:GetAttributeChangedSignal(name):Connect(function()
			fn(instance:GetAttribute(name))
		end)
	end
	return instance:GetPropertyChangedSignal(name):Connect(function()
		fn((instance :: any)[name])
	end)
end

local function writeInstance(bind: BindData, value: any)
	for instance, syncTo in bind.rbx do
		local attrs = syncTo[1]
		if attrs then
			for attr in attrs do
				setAttribute(instance, attr, value)
			end
		end
		local props = syncTo[2]
		if props then
			for prop in props do
				setProperty(instance, prop, value)
			end
		end
	end
end

local function processBinds(bind: BindData, value: any)
	if next(bind.rbx) ~= nil and not pcall(writeInstance, bind, value) then
		for instance, syncTo in bind.rbx do
			local attrs = syncTo[1]
			if attrs then
				for attr in attrs do
					local ok, result = pcall(setAttribute, instance, attr, value)
					if not ok then
						warn(`[Flux] failed to set attribute "{attr}" of {instance:GetFullName()}: {result}`)
					end
				end
			end
			local props = syncTo[2]
			if props then
				for prop in props do
					local ok, result = pcall(setProperty, instance, prop, value)
					if not ok then
						warn(`[Flux] failed to set property "{prop}" of {instance:GetFullName()}: {result}`)
					end
				end
			end
		end
	end
	applyChildren(bind, value)
end

local function cleanupChildrenBind<T>(node: Graph.Node<T>, parent: Instance?)
	local data = bindData[node]
	if data and data.children then
		local children = data.children
		if children.cleanupConnection then
			children.cleanupConnection:Disconnect()
		end
		for _, child in children.list do
			local current = child and child.Parent
			if current ~= nil and (parent == nil or current == parent) then
				child.Parent = nil
			end
		end
		table.clear(children.list)
		table.clear(children)
		data.children = nil
	end
end

local function getBindData<T>(node: Graph.Node<T>)
	local data: any = bindData[node]
	if data == nil then
		data = { rbx = {}, children = nil :: any }
		bindData[node] = data
		local eff = withOwner(nil :: any, function()
			return effect(function()
				processBinds(data, get(node))
			end)
		end)
		node:onDestroy(function()
			eff:Destroy()
			table.clear(data.rbx)
			cleanupChildrenBind(node)
			bindData[node] = nil
		end)
	end
	return data
end

local Bind = {
	--- @ignore
	pinOrder = function(instance: Instance)
		pinnedOrder[instance] = true
	end,
	--- @ignore
	applyLayoutOrder = applyLayoutOrder,
	--- @ignore
	MODEL_SYMBOL = MODEL_SYMBOL,
	--- @ignore
	kindOf = kindOf,
	--- @ignore
	isInstance = isInstance,
	--- @ignore
	setAttribute = setAttribute,
	--- @ignore
	setProperty = setProperty,
	--- @ignore
	onChanged = onChanged,
	--- @ignore
	onTagChanged = onTagChanged,
}

--[[
Wraps a reactive [node](https://flux.kohl.gg/guide/concepts/signals) for <strong>two-way binding</strong>.
Assigning `Flux.model(node)` to a property (or attribute) drives the
[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) from the node AND writes the node
back whenever the user changes that property. Only sound for properties that fire a changed signal (e.g.
[`TextBox`](https://create.roblox.com/docs/reference/engine/classes/TextBox)`.Text`).

[Open Documentation](https://flux.kohl.gg/guide/roblox/creation#flux-model-two-way-binding-in-one-key)
]]
function Bind.model<N>(node: N): Graph.Unwrap<N>
	if not isNode(node) then
		error("Flux.model expects a reactive node", 2)
	end
	return table.freeze({ MODEL_SYMBOL, node }) :: any
end

--[[
Whether `value` is a [`Flux.model`](https://flux.kohl.gg/guide/roblox/creation#flux-model-two-way-binding-in-one-key)
binding: lets a component tell a two-way value prop from a plain or one-way one.

[Open Documentation](https://flux.kohl.gg/guide/roblox/creation#flux-model-two-way-binding-in-one-key)
]]
function Bind.isModel(value: unknown): boolean
	return type(value) == "table" and (value :: any)[1] == MODEL_SYMBOL
end

--[[
The node inside a [`Flux.model`](https://flux.kohl.gg/guide/roblox/creation#flux-model-two-way-binding-in-one-key)
binding, or `nil` when `value` is not one. A component that takes a value prop writes user changes back through it.

```luau
local node = Flux.modelNode(props.value)
if node then
	node:set(text)
end
```

[Open Documentation](https://flux.kohl.gg/guide/roblox/creation#flux-model-two-way-binding-in-one-key)
]]
function Bind.modelNode(value: unknown): Graph.Node<any>?
	return if Bind.isModel(value) then (value :: any)[2] else nil
end

--- @ignore
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

	if isReactive() then
		untrack(function()
			applyChildren(data, raw(node))
		end)
	else
		applyChildren(data, raw(node))
	end
	return disconnectBind
end

--- @ignore
function Bind.from<T>(node: Graph.Node<T>, instance: Instance, property: string, isAttribute: boolean?)
	local name, attribute, isTag = resolveKey(property, isAttribute)
	local disconnect: any
	if isTag then
		node:set(instance:HasTag(name) :: any)
		disconnect = onTagChanged(instance, name, function(hasTag)
			node:set(hasTag :: any)
		end)
	else
		node:set(if attribute then instance:GetAttribute(name) else (instance :: any)[name])
		local connection = if attribute
			then instance:GetAttributeChangedSignal(name):Connect(function()
				node:set(instance:GetAttribute(name) :: any)
			end)
			else instance:GetPropertyChangedSignal(name):Connect(function()
				node:set((instance :: any)[name])
			end)
		disconnect = function()
			connection:Disconnect()
		end
	end
	node:onDestroy(disconnect)
	return node, disconnect
end

local function follow(instance: Instance, property: string): Graph.Node<any>
	return (Bind.from(signal(nil :: any), instance, property))
end

-- The `"Name"` singleton in `property`'s type keeps a literal argument from widening to `string`, so `K` stays the key.
--[[
A [node](https://flux.kohl.gg/guide/concepts/signals) following a property of a Roblox
[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance), an attribute when `property` starts
with `_attr_` or `$`, or a [CollectionService](https://create.roblox.com/docs/reference/engine/classes/CollectionService)
tag when `property` starts with `_tag_` or `#`. It is seeded with the current value and set again on every change, and
typed after the target: `Flux.property(textBox, "Text")` is a `Node<string>`, `Flux.property(npc, "#Enemy")` (or
`"_tag_Enemy"`) is a `Node<boolean>`, and an attribute (or a name the type can't resolve) gives a `Node<any>`. The node
stops following when it is destroyed.

```luau
local text = Flux.property(textBox, "Text")
local health = Flux.property(character, "$Health")
local isEnemy = Flux.property(character, "#Enemy")
```

[Open Documentation](https://flux.kohl.gg/guide/concepts/signals#binding-from-an-instance-property)
]]
function Bind.property<I, K>(instance: I & Instance, property: K | "Name"): Graph.Node<Type.PropertyType<I, K>>
	if not isInstance(instance) then
		error(`Flux.property expects an Instance, got {compatTypeof(instance)}`, 2)
	elseif type(property) ~= "string" then
		error(`Flux.property expects a property, "$Attribute", or "#Tag" name, got {compatTypeof(property)}`, 2)
	end
	return follow(instance, property)
end

-- The core constructor behind `Flux(...)`: a value becomes a signal, a function a computed, and an Instance with a
-- property, `"$Attribute"` / `"_attr_Attribute"`, or `"#Tag"` / `"_tag_Tag"` name a `Bind.property` node.
--- @ignore
function Bind.node(obj: any, second: string?): Graph.Node<any>
	if isInstance(obj) then
		if type(second) ~= "string" then
			error(
				`Flux(instance, property) expects a property, "$Attribute", or "#Tag" name, got {compatTypeof(second)}`,
				3
			)
		end
		return follow(obj, second)
	elseif second ~= nil then
		error(`Flux(value) takes a single argument; only an Instance takes a property name`, 3)
	end
	return new(obj)
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
				input[i] = read(deps[i])
			end
		else
			input = read(deps)
		end

		if defer then
			defer = false
			prevInput = input
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

--- @ignore
function Bind.to<T>(node: Graph.Node<T>, instance: Instance, property: string, isAttribute: boolean?)
	local data = getBindData(node)
	local attribute = isAttribute == true
	local index = if attribute then 1 else 2

	if attribute then
		setAttribute(instance, property, raw(node))
	else
		setProperty(instance, property, raw(node))
	end

	local binds = data.rbx[instance]
	if binds == nil then
		binds = {}
		data.rbx[instance] = binds
	end
	local bucket = binds[index]
	if bucket == nil then
		bucket = {}
		binds[index] = bucket
	end

	bindGeneration += 1
	local token = bindGeneration
	bucket[property] = token

	return function()
		if bucket[property] ~= token then
			return
		end
		bucket[property] = nil
		if (binds[1] == nil or next(binds[1]) == nil) and (binds[2] == nil or next(binds[2]) == nil) then
			data.rbx[instance] = nil
		end
	end
end

return table.freeze(Bind)
