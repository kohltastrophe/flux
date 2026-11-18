--!strict
local Compat = require("./Compat")
local Graph = require("./Graph")
local Type = require("./Type")

local compatTask = Compat.task
local compatTypeof = Compat.typeof
local warn = Compat.warn

local cleanup = Graph.cleanup
local dispose = Graph.dispose
local effect = Graph.effect
local get = Graph.Node.get
local getOwner = Graph.getOwner
local kindOf = Graph.kindOf
local new = Graph.new
local signal = Graph.signal
local raw = Graph.raw
local read = Graph.read
local untrack = Graph.untrack
local isNode = Graph.isNode
local isReactive = Graph.isReactive
local withOwner: any = Graph.withOwner

local MODEL_SYMBOL: any = table.freeze({ type = "Model" })
local PORTAL_SYMBOL: any = table.freeze({ type = "Portal" })
local NO_VALUE: any = nil
local NOOP = function() end

--- @ignore
type MountedPortal = {
	spec: any,
	stop: () -> (),
}

--- @ignore
type BindData = {
	fn: { [(value: any) -> ()]: boolean },
	rbx: { [Instance]: { { [string]: any }? } },
	eff: Graph.Node<any>,
	flushed: boolean,
	destroyCleanup: (() -> ())?,
	pin: number?,
	scratchChildren: { Instance }?,
	scratchPortals: { any }?,
	scratchIncoming: { [Instance]: true }?,
	children: {
		cleanupConnection: RBXScriptConnection?,
		list: { Instance },
		portals: { MountedPortal }?,
		nextPortals: { MountedPortal }?,
		parent: Instance?,
		order: number?,
		token: number?,
	}?,
}

local bindData: { [Graph.Node<any>]: BindData } = setmetatable({}, { __mode = "k" })
local bindGeneration = 0

--- @ignore
export type Portal = Type.Portal

-- The source that currently drives each instance property or attribute (attributes keyed with a `$` prefix). An edit
-- that sets the key again, bound or static, releases the previous claim first, so the newest value wins and stays
-- instead of racing the original source whenever it changes. A claim is a list of releasers: its unbind, then anything
-- edit attached to it (the node it made from a function, a model's read-back connection).
type Claim = { (() -> ()) | Graph.Node<any> }
local claims: { [Instance]: { [string]: Claim } } = setmetatable({}, { __mode = "k" })

local function claimKey(property: string, isAttribute: boolean?): string
	return if isAttribute then "$" .. property else property
end

local function release(instance: Instance, property: string, isAttribute: boolean?)
	local owned = claims[instance]
	if owned == nil then
		return
	end
	local key = claimKey(property, isAttribute)
	local claim = owned[key]
	if claim == nil then
		return
	end
	owned[key] = nil
	if next(owned) == nil then
		claims[instance] = nil
	end
	for _, releaser in claim do
		if type(releaser) == "function" then
			releaser()
		else
			Graph.dispose(releaser)
		end
	end
end
local pinnedOrder: { [Instance]: boolean } = setmetatable({}, { __mode = "k" })
local autoOrder: { [Instance]: boolean } = setmetatable({}, { __mode = "k" })

local function applyLayoutOrder(child: Instance, order: number): number
	if
		child:IsA("GuiObject")
		and not pinnedOrder[child]
		and ((child :: GuiObject).LayoutOrder == 0 or autoOrder[child] == true)
	then
		(child :: GuiObject).LayoutOrder = order
		autoOrder[child] = true
		return order + 1
	end
	return order
end

local function isInstance(value: any): boolean
	return kindOf(value) == "Instance"
end

local function isPortal(value: unknown): boolean
	local rawValue: any = value
	return type(value) == "table" and rawget(rawValue, 1) == PORTAL_SYMBOL
end

local mountPortal: (portal: any) -> () -> ()

local function stopPortals(portals: { () -> () }?)
	if portals == nil then
		return
	end
	for _, stop in portals do
		stop()
	end
	table.clear(portals)
end

local function stopMountedPortals(portals: { MountedPortal }?)
	if portals == nil then
		return
	end
	for _, entry in portals do
		entry.stop()
	end
	table.clear(portals)
end

local function collectChildren(value: any, into: { Instance }, portals: { any }): { Instance }
	if isInstance(value) then
		table.insert(into, value)
	elseif isNode(value) then
		collectChildren(get(value), into, portals)
	elseif isPortal(value) then
		table.insert(portals, value)
	elseif type(value) == "table" then
		for _, child in value do
			collectChildren(child, into, portals)
		end
	end
	return into
end

local function syncPortals(data: any, portals: { any }, count: number)
	local oldPortals = data.portals
	if count == 0 then
		stopMountedPortals(oldPortals)
		return
	end
	local mounted = data.nextPortals
	if mounted == nil then
		mounted = {}
	else
		data.nextPortals = nil
		table.clear(mounted)
	end
	if oldPortals ~= nil and oldPortals[1] ~= nil then
		local nOld = #oldPortals
		for i = 1, count do
			local spec = portals[i]
			local matched: MountedPortal? = nil
			for j = 1, nOld do
				local oldEntry = oldPortals[j]
				if oldEntry and oldEntry.spec == spec then
					matched = oldEntry
					oldPortals[j] = false :: any
					break
				end
			end
			mounted[i] = matched or { spec = spec, stop = NOOP }
		end
		for j = 1, nOld do
			local oldEntry = oldPortals[j]
			if oldEntry then
				oldEntry.stop()
			end
		end
		table.clear(oldPortals)
	else
		for i = 1, count do
			mounted[i] = { spec = portals[i], stop = NOOP }
		end
	end
	data.portals = mounted
	if oldPortals ~= nil then
		data.nextPortals = oldPortals
	end
	for i = 1, count do
		local entry = mounted[i]
		if entry.stop == NOOP then
			local spec = entry.spec
			entry.stop = withOwner(NO_VALUE, function()
				return mountPortal(spec)
			end)
		end
	end
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

	if isPortal(value) then
		for _, child in list do
			if child.Parent == parent then
				child.Parent = nil
			end
		end
		table.clear(list)
		local portals: { any } = bind.scratchPortals or {}
		bind.scratchPortals = nil
		portals[1] = value
		syncPortals(data, portals, 1)
		table.clear(portals)
		bind.scratchPortals = portals
	elseif type(value) == "table" and not isInstance(value) then
		local children: { Instance } = bind.scratchChildren or {}
		bind.scratchChildren = nil
		local portals: { any } = bind.scratchPortals or {}
		bind.scratchPortals = nil
		collectChildren(value, children, portals)
		if list[1] ~= nil then
			if children[2] == nil then
				local first = children[1]
				for _, child in list do
					if child.Parent == parent and child ~= first then
						child.Parent = nil
					end
				end
			else
				local incoming: { [Instance]: true } = bind.scratchIncoming or {}
				bind.scratchIncoming = nil
				for _, child in children do
					incoming[child] = true
				end
				for _, child in list do
					if child.Parent == parent and incoming[child] == nil then
						child.Parent = nil
					end
				end
				table.clear(incoming)
				bind.scratchIncoming = incoming
			end
			table.clear(list)
		end
		for count, child in children do
			layoutOrder = applyLayoutOrder(child, layoutOrder)
			list[count] = child
			if child.Parent ~= parent then
				child.Parent = parent
			end
		end
		syncPortals(data, portals, #portals)
		table.clear(children)
		table.clear(portals)
		bind.scratchChildren = children
		bind.scratchPortals = portals
	else
		for _, child in list do
			if child.Parent == parent and child ~= value then
				child.Parent = nil
			end
		end
		table.clear(list)
		syncPortals(data, list, 0)
		if value ~= nil and isInstance(value) then
			local child = value :: Instance
			applyLayoutOrder(child, layoutOrder)
			list[1] = child
			if child.Parent ~= parent then
				child.Parent = parent
			end
		end
	end
end

local function setAttribute(instance: Instance, attr: string, value: any)
	instance:SetAttribute(attr, value)
end

local function setProperty(instance: Instance, prop: string, value: any)
	local rawInstance: any = instance
	rawInstance[prop] = value
end

local function resolveKey(name: string, isAttribute: boolean?): (string, boolean, boolean)
	if isAttribute ~= nil then
		return name, isAttribute, false
	end
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
	local destroying: RBXScriptConnection
	local function disconnect()
		added:Disconnect()
		removed:Disconnect()
		ancestry:Disconnect()
		destroying:Disconnect()
	end
	destroying = instance.Destroying:Connect(disconnect)
	return disconnect
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
	local rawInstance: any = instance
	return instance:GetPropertyChangedSignal(name):Connect(function()
		fn(rawInstance[name])
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

local function writeBinds(bind: BindData, value: any)
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
end

local bindDestroy: (node: Graph.Node<any>, disconnect: () -> ()) -> () -> ()

local function releaseBindDataIfIdle<T>(node: Graph.Node<T>)
	local data = bindData[node]
	if data == nil or data.pin ~= nil or next(data.fn) ~= nil or next(data.rbx) ~= nil or data.children ~= nil then
		return
	end
	bindData[node] = nil
	local stopDestroy = data.destroyCleanup
	data.destroyCleanup = nil
	if stopDestroy ~= nil then
		stopDestroy()
	end
	data.eff:Destroy()
end

local function cleanupChildrenBind<T>(node: Graph.Node<T>, parent: Instance?)
	local data = bindData[node]
	local children = data and data.children
	if not children then
		return
	end
	if children.cleanupConnection then
		children.cleanupConnection:Disconnect()
	end
	stopMountedPortals(children.portals)
	for _, child in children.list do
		local current = child and child.Parent
		if current ~= nil and (parent == nil or current == parent) then
			child.Parent = nil
		end
	end
	table.clear(children.list)
	table.clear(children)
	data.children = nil
	releaseBindDataIfIdle(node)
end

local function startBindEffect(node: Graph.Node<any>, data: any): Graph.Node<any>
	data.flushed = false
	-- Writing instance properties fires engine listeners (`Changed`, `GetPropertyChangedSignal`, `AncestryChanged`)
	-- synchronously. Run the writes untracked and ownerless so those listeners neither subscribe this effect to
	-- what they read nor hand it the instances they create (which it would destroy on its next run). Children
	-- stay tracked: nested child nodes are read while mounting them.
	local pending: any = nil
	local notifyListeners = false
	local function write()
		local value = pending
		local shouldNotify = notifyListeners
		pending = nil
		notifyListeners = false
		if shouldNotify then
			local fns = data.fn
			local first = next(fns)
			if first ~= nil then
				if next(fns, first) == nil then
					compatTask.spawn(first, value)
				else
					local list = table.create(4)
					for fn in fns do
						table.insert(list, fn)
					end
					for _, fn in list do
						if fns[fn] then
							compatTask.spawn(fn, value)
						end
					end
				end
			end
		end
		writeBinds(data, value)
	end
	local function isolated()
		untrack(write)
	end
	local eff = withOwner(NO_VALUE, function()
		return effect(function()
			local notify = data.flushed
			data.flushed = true
			local value = get(node)
			local hasFn = notify and next(data.fn) ~= nil
			if hasFn or next(data.rbx) ~= nil then
				pending = value
				notifyListeners = hasFn
				withOwner(NO_VALUE, isolated)
			end
			applyChildren(data, value)
		end)
	end)
	return eff
end

function bindDestroy(node: Graph.Node<any>, disconnect: () -> ()): () -> ()
	local rawNode: any = node
	local done = false
	local destroyingNode = false
	local disconnectOnce: () -> ()
	local function onNodeDestroy()
		destroyingNode = true
		disconnectOnce()
	end
	function disconnectOnce()
		if done then
			return
		end
		done = true
		if not destroyingNode then
			local inner = rawget(rawNode, 1)
			local destroys = inner and inner.destroys
			if destroys then
				local idx = table.find(destroys, onNodeDestroy)
				if idx then
					table.remove(destroys, idx)
				end
			end
		end
		disconnect()
	end
	node:onDestroy(onNodeDestroy)
	return disconnectOnce
end

local function ensureBindData<T>(node: Graph.Node<T>)
	local data: any = bindData[node]
	if data == nil then
		data = { fn = {}, rbx = {}, children = nil, eff = nil, flushed = false }
		bindData[node] = data
		data.eff = startBindEffect(node, data)
		data.destroyCleanup = bindDestroy(node, function()
			if bindData[node] ~= data then
				return
			end
			data.eff:Destroy()
			table.clear(data.fn)
			table.clear(data.rbx)
			if data.children ~= nil then
				cleanupChildrenBind(node)
			end
			bindData[node] = nil
		end)
	end
	return data
end

local Bind = {
	--- @ignore
	pinOrder = function(instance: Instance)
		pinnedOrder[instance] = true
		autoOrder[instance] = nil
	end,
	--- @ignore
	applyLayoutOrder = applyLayoutOrder,
	--- @ignore
	setAttribute = setAttribute,
	--- @ignore
	setProperty = setProperty,
	--- @ignore
	onChanged = onChanged,
	--- @ignore
	onTagChanged = onTagChanged,
	--- @ignore
	bindDestroy = bindDestroy,
}

--[[
Wraps a reactive [node](https://flux.kohl.gg/guide/concepts/signals) for two-way binding on an [`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) property, attribute, or tag.
Updates the instance from `node` and writes changes back to `node` when the instance fires its changed signal.

[Open Documentation](https://flux.kohl.gg/guide/roblox/creation#flux-model-two-way-binding-in-one-key)
]]
function Bind.model<T>(node: { read get: (any) -> T, read peek: (any) -> T, read set: (any, ...any) -> any }): T
	if not isNode(node) then
		error("Flux.model expects a reactive node", 2)
	end
	local wrapped: any = table.freeze({ MODEL_SYMBOL, node })
	return wrapped
end

--[[
Returns `true` when `value` is a [`Flux.model`](https://flux.kohl.gg/guide/roblox/creation#flux-model-two-way-binding-in-one-key) wrapper.

[Open Documentation](https://flux.kohl.gg/guide/roblox/creation#flux-model-two-way-binding-in-one-key)
]]
function Bind.isModel(value: unknown): boolean
	local rawValue: any = value
	return type(value) == "table" and rawget(rawValue, 1) == MODEL_SYMBOL
end

--[[
Returns the underlying node from a [`Flux.model`](https://flux.kohl.gg/guide/roblox/creation#flux-model-two-way-binding-in-one-key) wrapper, or `nil` if `value` is not a model.

```luau
local node = Flux.modelNode(props.value)
if node then
	node:set(text)
end
```

[Open Documentation](https://flux.kohl.gg/guide/roblox/creation#flux-model-two-way-binding-in-one-key)
]]
function Bind.modelNode(value: unknown): Graph.Node<any>?
	local rawValue: any = value
	return if Bind.isModel(value) then rawValue[2] else nil
end

local pendingChildData: BindData?
local pendingChildValue: any

local function applyPendingChildren()
	local data, value = pendingChildData :: BindData, pendingChildValue
	pendingChildData, pendingChildValue = nil, nil
	applyChildren(data, value)
end

--- @ignore
function Bind.children<T>(node: Graph.Node<T>, parent: Instance, layoutOrder: number?): () -> ()
	local data = ensureBindData(node)
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

	local restart = data.flushed
	if restart then
		data.eff:Destroy()
		data.eff = startBindEffect(node, data)
	end
	if isReactive() then
		pendingChildData, pendingChildValue = data, raw(node)
		untrack(applyPendingChildren)
	else
		applyChildren(data, raw(node))
	end
	if restart and next(data.fn) ~= nil then
		data.eff:peek()
	end
	return disconnectBind
end

--[[
Subscribes `fn` to updates of `node` with [`RBXScriptSignal:Connect`](https://create.roblox.com/docs/reference/engine/datatypes/RBXScriptSignal#Connect) semantics and returns an unsubscribe function.
Fires on each flush after `node` changes, spawning `fn(value)` on its own thread via [`task.spawn`](https://create.roblox.com/docs/reference/engine/libraries/task#spawn) so callbacks may yield freely.

[Open Documentation](https://flux.kohl.gg/guide/concepts/effects#bridging-to-external-systems)
]]
function Bind.listen<T>(node: Graph.Node<T>, fn: (value: T) -> ()): () -> ()
	if not isNode(node) then
		error(`Flux.listen expects a reactive node, got {compatTypeof(node)}`, 2)
	elseif type(fn) ~= "function" then
		error(`Flux.listen expects a function, got {compatTypeof(fn)}`, 2)
	end
	local data = ensureBindData(node)
	if not data.flushed then
		data.eff:peek()
	end
	local fnData = data.fn
	fnData[fn] = true
	return function()
		fnData[fn] = nil
		releaseBindDataIfIdle(node)
	end
end

--- @ignore
function Bind.from<T>(node: Graph.Node<T>, instance: Instance, property: string, isAttribute: boolean?)
	local name, attribute, isTag = resolveKey(property, isAttribute)
	local rawNode: any = node
	local rawInstance: any = instance
	local disconnect: any
	if isTag then
		rawNode:set(instance:HasTag(name))
		disconnect = onTagChanged(instance, name, function(hasTag)
			rawNode:set(hasTag)
		end)
	else
		rawNode:set(if attribute then instance:GetAttribute(name) else rawInstance[name])
		local connection = onChanged(instance, name, attribute, function(value)
			rawNode:set(value)
		end)
		disconnect = function()
			connection:Disconnect()
		end
	end
	local destroyConn: RBXScriptConnection? = nil
	local stop = bindDestroy(node, function()
		local conn = destroyConn
		destroyConn = nil
		if conn ~= nil then
			conn:Disconnect()
		end
		disconnect()
	end)
	destroyConn = instance.Destroying:Once(stop)
	if getOwner() ~= nil then
		cleanup(stop)
	end
	return node, stop
end

local function follow(instance: Instance, property: string): Graph.Node<any>
	return (Bind.from(signal(NO_VALUE), instance, property))
end

local function getSignalConnector(obj: any): ((any, (any) -> ()) -> any)?
	if isNode(obj) or isInstance(obj) then
		return nil
	end
	if kindOf(obj) == "RBXScriptSignal" then
		return (obj :: any).Connect
	end
	if type(obj) ~= "table" then
		return nil
	end
	local mt = getmetatable(obj :: any)
	if mt == nil then
		local connect = rawget(obj :: any, "Connect")
		if type(connect) == "function" then
			return connect
		end
		local lower = rawget(obj :: any, "connect")
		return if type(lower) == "function" then lower else nil
	end
	local ok, connect = pcall(function()
		return (obj :: any).Connect
	end)
	if ok and type(connect) == "function" then
		return connect
	end
	local okLower, lower = pcall(function()
		return (obj :: any).connect
	end)
	return if okLower and type(lower) == "function" then lower else nil
end

local function fromSignal(sig: any, initial: any): Graph.Node<any>
	local connect = getSignalConnector(sig)
	if connect == nil then
		error(`Flux.fromSignal expects an RBXScriptSignal or signal with :Connect(), got {compatTypeof(sig)}`, 2)
	end
	local node = signal(initial)
	local conn = connect(sig, function(value: any)
		node:set(value)
	end)
	local stop = bindDestroy(node, function()
		dispose(conn)
	end)
	if getOwner() ~= nil then
		cleanup(stop)
	end
	return node
end

--[[
Creates a [node](https://flux.kohl.gg/guide/concepts/signals#bridging-signals) updated from an
[`RBXScriptSignal`](https://create.roblox.com/docs/reference/engine/datatypes/RBXScriptSignal) or signal table with
`:Connect()` / `:connect()`, seeding from `initial`. Disconnects automatically when the node or its owning scope is
destroyed.
]]
Bind.fromSignal =
	fromSignal :: (<S>(signal: S) -> Graph.Node<Type.SignalPayload<S>?>) & (<S, I>(signal: S, initial: I) -> Graph.Node<Type.SignalPayload<S> | I>)

-- The `"Name"` singleton in `property`'s type keeps a literal argument from widening to `string`, so `K` stays the key.
--[[
Creates a [node](https://flux.kohl.gg/guide/concepts/signals) mirroring an [`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) property, an attribute (`$Name` or `_attr_Name`), or a [`CollectionService`](https://create.roblox.com/docs/reference/engine/classes/CollectionService) tag (`#Tag` or `_tag_Tag`).
Disconnects automatically when `instance`, the node, or its owning scope is destroyed.

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

-- The core constructor behind `Flux(...)`: a value becomes a signal, a function a computed, an Instance with a
-- property, `"$Attribute"` / `"_attr_Attribute"`, or `"#Tag"` / `"_tag_Tag"` name a `Bind.property` node, and a signal
-- object with `:Connect()` / `:connect()` a `Bind.fromSignal` node.
--- @ignore
function Bind.node(obj: any, second: any?): Graph.Node<any>
	if isInstance(obj) then
		if type(second) ~= "string" then
			error(
				`Flux(instance, property) expects a property, "$Attribute", or "#Tag" name, got {compatTypeof(second)}`,
				3
			)
		end
		return follow(obj, second)
	elseif getSignalConnector(obj) ~= nil then
		return (Bind.fromSignal :: any)(obj, second)
	elseif second ~= nil then
		error(
			`Flux(value) takes a single argument; only an Instance takes a property name (or a signal an initial value)`,
			3
		)
	end
	return new(obj)
end

--[[
Wraps `fn` so a [computed](https://flux.kohl.gg/guide/concepts/computeds) or [effect](https://flux.kohl.gg/guide/concepts/effects) tracks only `deps` and runs `fn(input, prevInput, prevResult)` untracked.
Pass `defer = true` to skip the initial run and fire only when `deps` change.

[Open Documentation](https://flux.kohl.gg/guide/concepts/tracking#flux-on)
]]
function Bind.on<D, R>(
	deps: D,
	fn: (input: Type.OnInput<D>, prevInput: Type.OnInput<D>?, prevResult: R?) -> R,
	defer: boolean?
): (prevResult: R?) -> R?
	local rawDeps: any = deps
	local rawFn: (any, any, any) -> any = fn
	local isArray = type(rawDeps) == "table" and not isNode(rawDeps)
	local count = if isArray then #(rawDeps :: { any }) else 0
	local prevInput: any = nil
	local curInput: any = nil
	local curPrevResult: any = nil
	local function runOnFn(): R
		local input, prevRes = curInput, curPrevResult
		curInput, curPrevResult = nil, nil
		return rawFn(input, prevInput, prevRes)
	end

	return function(prevResult: R?): R?
		local input
		if isArray then
			input = table.create(count)
			for i = 1, count do
				input[i] = read(rawDeps[i])
			end
		else
			input = read(rawDeps)
		end

		if defer then
			defer = false
			prevInput = input
			return prevResult
		end

		curInput, curPrevResult = input, prevResult
		local result = untrack(runOnFn)
		prevInput = input
		return result
	end
end

--- @ignore
function Bind.to<T>(node: Graph.Node<T>, instance: Instance, property: string, isAttribute: boolean?)
	local data = ensureBindData(node)
	data.pin = (data.pin or 0) + 1
	local attribute = isAttribute == true
	local index = if attribute then 1 else 2
	local ok, err: any = pcall(function()
		release(instance, property, attribute)

		local value = raw(node)
		local function applyInitial()
			if attribute then
				setAttribute(instance, property, value)
			else
				setProperty(instance, property, value)
			end
		end
		if isReactive() or Graph.getOwner() ~= nil then
			withOwner(NO_VALUE, function()
				untrack(applyInitial)
			end)
		else
			applyInitial()
		end
	end)
	local pin = (data.pin or 1) - 1
	data.pin = if pin > 0 then pin else nil
	if not ok then
		releaseBindDataIfIdle(node)
		error(err, 0)
	end
	if bindData[node] ~= data then
		return NOOP
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

	local function unbind()
		if bucket[property] ~= token then
			return
		end
		bucket[property] = nil
		if (binds[1] == nil or next(binds[1]) == nil) and (binds[2] == nil or next(binds[2]) == nil) then
			data.rbx[instance] = nil
		end
		releaseBindDataIfIdle(node)
	end

	local key = claimKey(property, attribute)
	local claim: Claim = { unbind }
	local owned = claims[instance]
	if owned == nil then
		owned = {}
		claims[instance] = owned
	end
	owned[key] = claim

	return function()
		local current = claims[instance]
		if current and current[key] == claim then
			current[key] = nil
			if next(current) == nil then
				claims[instance] = nil
			end
		end
		unbind()
	end
end

--- @ignore
--- Releases the source currently bound to an instance property or attribute, so a static write replaces it.
Bind.release = release

--- @ignore
--- Ties `releaser` (a cleanup function or cleanable) to the current binding of a key, run when a later edit replaces it.
function Bind.attach(instance: Instance, property: string, isAttribute: boolean?, releaser: any)
	local owned = claims[instance]
	local claim = owned and owned[claimKey(property, isAttribute)]
	if claim then
		table.insert(claim, releaser)
	end
end

--- @ignore
function Bind.isPortal(value: unknown): boolean
	return isPortal(value)
end

--[[
Creates a portal mounting `children` into `target` (static [`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance)
or reactive target node) without transferring ownership of `target`.
Mounted children are unparented when the owning scope tears down, the target changes, or the portal host is destroyed.

[Open Documentation](https://flux.kohl.gg/guide/roblox/creation#portals-flux-portal)
]]
function Bind.portal(target: Graph.Reactive<Instance?>, children: any): Portal
	if target ~= nil and not isInstance(target) and not Graph.isDynamic(target) then
		error(`Flux.portal expects an Instance, reactive target, or nil, got {compatTypeof(target)}`, 2)
	end
	local wrapped: any = table.freeze({ PORTAL_SYMBOL, target, children })
	return wrapped
end

--- @ignore
function mountPortal(portal: any): () -> ()
	local targetSpec = portal[2]
	local content = portal[3]
	local mountedInstances: { Instance } = {}
	local subCleanups: { () -> () } = {}
	local targetConn: RBXScriptConnection? = nil
	local currentTarget: Instance? = nil
	local eff: any = nil
	local stopped = false

	local function clearMounted()
		if targetConn ~= nil then
			targetConn:Disconnect()
			targetConn = nil
		end
		stopPortals(subCleanups)
		local target = currentTarget
		currentTarget = nil
		if target ~= nil then
			for _, inst in mountedInstances do
				if inst.Parent == target then
					inst.Parent = nil
				end
			end
		end
		table.clear(mountedInstances)
	end

	local function mountItem(target: Instance, item: any, order: number): number
		if isInstance(item) then
			order = applyLayoutOrder(item, order)
			table.insert(mountedInstances, item)
			item.Parent = target
			return order
		elseif isNode(item) then
			table.insert(subCleanups, Bind.children(item, target, order))
			return order + 1
		elseif isPortal(item) then
			table.insert(subCleanups, mountPortal(item))
			return order
		elseif type(item) == "table" then
			for _, sub in item do
				order = mountItem(target, sub, order)
			end
		end
		return order
	end

	local function mountTo(target: any)
		clearMounted()
		if stopped or target == nil then
			return
		end
		if not isInstance(target) then
			error(`Flux.portal target must resolve to an Instance or nil, got {compatTypeof(target)}`, 2)
		end
		currentTarget = target
		targetConn = target.Destroying:Once(clearMounted)
		local ok, err: any = pcall(mountItem, target, content, 1)
		if not ok then
			clearMounted()
			error(err, 0)
		end
	end

	local function stop()
		if stopped then
			return
		end
		stopped = true
		if eff ~= nil then
			eff:Destroy()
			eff = nil
		end
		clearMounted()
	end

	if Graph.isDynamic(targetSpec) then
		local pendingTarget: any = nil
		local function applyTarget()
			local nextTarget = pendingTarget
			pendingTarget = nil
			mountTo(nextTarget)
		end
		local function mountUntracked()
			untrack(applyTarget)
		end
		eff = withOwner(NO_VALUE, function()
			return effect(function()
				pendingTarget = read(targetSpec)
				withOwner(NO_VALUE, mountUntracked)
			end)
		end)
	else
		mountTo(targetSpec)
	end

	if getOwner() ~= nil then
		cleanup(stop)
	end

	return stop
end

--- @ignore
Bind.mountPortal = mountPortal

return table.freeze(Bind)
