--!strict

local Defaults = require("@self/Defaults")
local Edit = require("@self/Edit")
local Find = require("@self/Find")
local Flags = require("@self/Flags")
local Graph = require("@self/Graph")
local Motion = require("@self/Motion")
local Type = require("@self/Type")

local Async = require("@self/Async")
local Bind = require("@self/Bind")
local Clean = require("@self/Clean")
local Conditional = require("@self/Conditional")
local Context = require("@self/Context")
local Directive = require("@self/Directive")
local For = require("@self/For")
local Layout = require("@self/Layout")
local Responsive = require("@self/Responsive")
local Safe = require("@self/Safe")
local Selector = require("@self/Selector")
local Store = require("@self/Store")
local Wrap = require("@self/Wrap")

export type Node<T> = Graph.Node<T>

local construct = require("@self/Construct")

local Constructors = setmetatable({}, {
	__index = function(self: any, class: string)
		if type(class) ~= "string" then
			error(`String expected, got {typeof(class)}`)
		end

		self[class] = function(properties: Type.Map<any>): Instance
			return construct(class, properties)
		end

		return self[class]
	end,
})

local Flux = {
	--[[
	<strong>Bind</strong>: low-level hydration primitives behind
	[`Flux.model`](https://flux.kohl.gg/guide/roblox/creation#flux-model-two-way-binding-in-one-key), the `_EVENT`
	directive, and child parenting. Binds a node to or from a Roblox
	[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) property or attribute.

	[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration)
	]]
	Bind = Bind,
	--[[
	<strong>Color</strong>: a perceptual
	[`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3) toolkit working in
	gamut-clipped Oklab. Provides `lighten`/`darken`, `mix`, `rotateHue`, and WCAG `contrast`/`readable`.

	[Open Documentation](https://flux.kohl.gg/guide/motion/color)
	]]
	Color = Motion.Color,
	--[[
	<strong>Defaults</strong>: per-class default properties auto-applied to every Roblox
	[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) built by
	[`Flux.new`](https://flux.kohl.gg/guide/roblox/creation#the-flux-new-function). Mutable.

	[Open Documentation](https://flux.kohl.gg/guide/roblox/defaults)
	]]
	Defaults = Defaults,
	--[[
	<strong>Find</strong>: Instance selectors for hydration. `Child`, `Descendant`, `Ancestor`, `Query`, and
	class-filtered variants apply props to matched descendants of a Roblox
	[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance).

	[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#instance-selectors-flux-find)
	]]
	Find = Find,
	--[[
	<strong>Flags</strong>: global toggles. `Flags.defaults` enables or disables the automatic per-class
	defaults system applied by [`Flux.new`](https://flux.kohl.gg/guide/roblox/creation#the-flux-new-function).

	[Open Documentation](https://flux.kohl.gg/guide/roblox/defaults#disabling-defaults)
	]]
	Flags = Flags,
	--[[
	<strong>Graph</strong>: the low-level reactive graph. Most members are surfaced flat on `Flux`
	(`Flux.read`, `Flux.retrack`, `Flux.untrack`, …); reach into the namespace for `Flux.flush`.

	[Open Documentation](https://flux.kohl.gg/guide/concepts/tracking)
	]]
	Graph = Graph,
	--[[
	<strong>Layout</strong>: layout and constraint helpers (`padding`, `list`, `grid`, `aspectRatio`,
	`sizeConstraint`, `flex`) that return ready-to-parent Roblox
	[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance)s with reactive arguments.

	[Open Documentation](https://flux.kohl.gg/guide/utilities/layout)
	]]
	Layout = Layout,
	--[[
	<strong>Motion</strong>: animation. `spring` and `tween` return animated
	[node](https://flux.kohl.gg/guide/concepts/signals)s; it also hosts the
	[`Color`](https://flux.kohl.gg/guide/motion/color) toolkit and `step`.

	[Open Documentation](https://flux.kohl.gg/guide/motion/spring)
	]]
	Motion = Motion,
	--[[
	<strong>Responsive</strong>: viewport-driven UI. `viewport`, `scale`, `breakpoint`, and `safeArea` are
	shared reactive [node](https://flux.kohl.gg/guide/concepts/signals)s that update as the Roblox
	[`Camera`](https://create.roblox.com/docs/reference/engine/classes/Camera) viewport changes.

	[Open Documentation](https://flux.kohl.gg/guide/utilities/responsive)
	]]
	Responsive = Responsive,
	--[[
	<strong>Store</strong>: deep reactive proxies over plain tables. Write a nested field and only the
	[node](https://flux.kohl.gg/guide/concepts/signals)s whose leaves changed re-run.

	[Open Documentation](https://flux.kohl.gg/guide/concepts/stores)
	]]
	Store = Store,

	flush = Graph.flush,
	strict = Graph.strict,

	scope = Graph.scope,
	signal = Graph.signal,
	computed = Graph.computed,
	effect = Graph.effect,

	getOwner = Graph.getOwner,
	withOwner = Graph.withOwner,
	cleanup = Graph.cleanup,

	isNode = Graph.isNode,
	isReactive = Graph.isReactive,

	raw = Graph.raw,
	read = Graph.read,
	untrack = Graph.untrack,
	retrack = Graph.retrack,

	on = Bind.on,
	listen = Bind.listen,
	model = Bind.model,

	attr = Directive.attr,
	event = Directive.event,
	onDestroy = Directive.onDestroy,
	ref = Directive.ref,
	tag = Directive.tag,

	-- TODO: better context using scopes
	context = Context.new,

	spring = Motion.spring,
	tween = Motion.tween,

	viewport = Responsive.viewport,
	scale = Responsive.scale,
	breakpoint = Responsive.breakpoint,
	safeArea = Responsive.safeArea,

	padding = Layout.padding,
	aspectRatio = Layout.aspectRatio,
	sizeConstraint = Layout.sizeConstraint,
	list = Layout.list,
	grid = Layout.grid,
	flex = Layout.flex,

	clean = Clean,
	async = Async.new,
	safe = Safe.safe,
	catch = Safe.catch,
	forValue = For.value,
	forIndex = For.index,
	selector = Selector.new,
	default = Conditional.default,
	show = Conditional.show,
	showKeyed = Conditional.showKeyed,
	switch = Conditional.switch,
	store = Store.new,
	wrap = Wrap,
}

local FluxMT = {}

local bindNode = Bind.node

--[[
The terse constructor: `Flux(value)` wraps a static value, `Flux(fn)` a
[computed](https://flux.kohl.gg/guide/concepts/computeds), `Flux(fn, true)` an
[effect](https://flux.kohl.gg/guide/concepts/effects), and `Flux(instance, property)` binds a new node from
a Roblox [`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) property or attribute.
@param obj - A static value, a computation function, or a Roblox [`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) to bind from.
@param effectOrProperty - When `obj` is a function, `true` marks it an [effect](https://flux.kohl.gg/guide/concepts/effects); when `obj` is an [`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance), the property or attribute name to bind.

[Open Documentation](https://flux.kohl.gg/guide/concepts/signals#creating-a-signal)
]]
function FluxMT.__call<T>(self: any, obj: (() -> T) | T, effectOrProperty: boolean? | string?): Graph.Node<T>
	return bindNode(obj, effectOrProperty)
end

--[[
Hydrates an existing Roblox [`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance),
applying reactive properties, event handlers, and directives just like
[`Flux.new`](https://flux.kohl.gg/guide/roblox/creation#the-flux-new-function), but onto an
[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) you already have. Returns a
function that takes the property table. Called inside a [`Flux.scope`](https://flux.kohl.gg/guide/concepts/scopes), the
bindings are owned by that scope and disconnected when it is destroyed.

[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#the-flux-edit-function)
]]
function Flux.edit<T>(instance: T & Instance)
	return function(properties: Type.EditProperties<T>): T
		return Edit(instance, properties)
	end
end

--[[
Creates a new Roblox [`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) of
`className` with per-class [defaults](https://flux.kohl.gg/guide/roblox/defaults) applied, then returns a
function that takes a property table of static values, reactive
[node](https://flux.kohl.gg/guide/concepts/signals)s, children, and directives. Created inside a
[`Flux.scope`](https://flux.kohl.gg/guide/concepts/scopes), the instance is owned by that scope and destroyed with it.

[Open Documentation](https://flux.kohl.gg/guide/roblox/creation#the-flux-new-function)
]]
function Flux.new<T>(className: T | keyof<Type.Creatable>)
	return Constructors[className] :: (Type.Properties<Type.Resolve<T>>) -> Type.Resolve<T>
end

if game then
	game:GetService("RunService").Heartbeat:Connect(function()
		Motion.step()
		Graph.flush()
	end)
end

return table.freeze(setmetatable(Flux, table.freeze(FluxMT)))
