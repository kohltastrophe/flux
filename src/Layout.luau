--!strict

local Compat = require("./Compat")
local Graph = require("./Graph")
local construct = require("./Construct")

local IS_ROBLOX = Compat.isRoblox
local warn = Compat.warn

local computed = Graph.computed
local isNode = Graph.isNode
local new = Graph.new
local readDep = Graph.readDep

type Props = { [string]: any }
type EnumMap = { [string]: EnumItem }

-- Re-exported from Graph: a value that may be static, a reactive Node, or a computation function.
export type Reactive<T> = Graph.Reactive<T>
export type Length = number | UDim
-- The struct a reactive padding source yields (e.g. `Flux.safeArea`); missing sides read as 0.
export type Insets = { top: number?, bottom: number?, left: number?, right: number? }
export type Align = "start" | "center" | "end"
-- Adds the flex distribution values: space-* spread items along an axis; stretch/fill resize them to fill it.
export type FlexAlign = Align | "between" | "around" | "evenly" | "stretch" | "fill" | "none"
export type LineAlign = Align | "stretch" | "automatic"
export type Direction = "x" | "y"
export type FlexMode = "fill" | "grow" | "shrink" | "none"

export type PaddingSides = {
	top: Reactive<Length>?,
	bottom: Reactive<Length>?,
	left: Reactive<Length>?,
	right: Reactive<Length>?,
	x: Reactive<Length>?,
	y: Reactive<Length>?,
}

export type ListConfig = {
	gap: Reactive<Length>?,
	direction: Reactive<Direction | Enum.FillDirection>?,
	align: Reactive<FlexAlign>?,
	justify: Reactive<FlexAlign>?,
	horizontalAlign: Reactive<FlexAlign | Enum.HorizontalAlignment | Enum.UIFlexAlignment>?,
	verticalAlign: Reactive<FlexAlign | Enum.VerticalAlignment | Enum.UIFlexAlignment>?,
	lineAlign: Reactive<LineAlign | Enum.ItemLineAlignment>?,
	wraps: Reactive<boolean>?,
}

export type GridConfig = {
	cell: Reactive<number | Vector2 | UDim2>?,
	gap: Reactive<number | Vector2 | UDim2>?,
	fill: Reactive<Direction | Enum.FillDirection>?,
	align: Reactive<Align | Enum.HorizontalAlignment>?,
	justify: Reactive<Align | Enum.VerticalAlignment>?,
	maxCells: Reactive<number>?,
}

export type StrokeConfig = {
	thickness: Reactive<number>?,
	color: Reactive<Color3>?,
	transparency: Reactive<number>?,
	mode: Reactive<"contextual" | "border" | Enum.ApplyStrokeMode>?,
	joins: Reactive<"round" | "bevel" | "miter" | Enum.LineJoinMode>?,
}

local FILL_DIRECTION: EnumMap
local HORIZONTAL_ALIGN: EnumMap
local VERTICAL_ALIGN: EnumMap
local FLEX_ALIGNMENT: EnumMap
local ITEM_LINE_ALIGN: EnumMap
local FLEX_MODE: EnumMap
local ASPECT_TYPE: EnumMap
local DOMINANT_AXIS: EnumMap
local STROKE_MODE: EnumMap
local LINE_JOIN: EnumMap

if IS_ROBLOX then
	FILL_DIRECTION = { x = Enum.FillDirection.Horizontal, y = Enum.FillDirection.Vertical }
	HORIZONTAL_ALIGN = {
		start = Enum.HorizontalAlignment.Left,
		center = Enum.HorizontalAlignment.Center,
		["end"] = Enum.HorizontalAlignment.Right,
	}
	VERTICAL_ALIGN = {
		start = Enum.VerticalAlignment.Top,
		center = Enum.VerticalAlignment.Center,
		["end"] = Enum.VerticalAlignment.Bottom,
	}
	FLEX_ALIGNMENT = {
		none = Enum.UIFlexAlignment.None,
		fill = Enum.UIFlexAlignment.Fill,
		stretch = Enum.UIFlexAlignment.Fill,
		between = Enum.UIFlexAlignment.SpaceBetween,
		around = Enum.UIFlexAlignment.SpaceAround,
		evenly = Enum.UIFlexAlignment.SpaceEvenly,
	}
	ITEM_LINE_ALIGN = {
		automatic = Enum.ItemLineAlignment.Automatic,
		start = Enum.ItemLineAlignment.Start,
		center = Enum.ItemLineAlignment.Center,
		["end"] = Enum.ItemLineAlignment.End,
		stretch = Enum.ItemLineAlignment.Stretch,
	}
	FLEX_MODE = {
		fill = Enum.UIFlexMode.Fill,
		grow = Enum.UIFlexMode.Grow,
		shrink = Enum.UIFlexMode.Shrink,
		none = Enum.UIFlexMode.None,
	}
	ASPECT_TYPE = {
		fit = Enum.AspectType.FitWithinMaxSize,
		scale = Enum.AspectType.ScaleWithParentSize,
	}
	DOMINANT_AXIS = { width = Enum.DominantAxis.Width, height = Enum.DominantAxis.Height }
	STROKE_MODE = { contextual = Enum.ApplyStrokeMode.Contextual, border = Enum.ApplyStrokeMode.Border }
	LINE_JOIN = { round = Enum.LineJoinMode.Round, bevel = Enum.LineJoinMode.Bevel, miter = Enum.LineJoinMode.Miter }
end

-- A value the reactive pipeline must read through: a Node or a computation function.
local function isReactiveValue(value: any): boolean
	return isNode(value) or type(value) == "function"
end

local warnedEnums: { [string]: boolean } = {}

--[[ Friendly string → Enum; passes through a real Enum; a bad string warns and resolves `nil`, leaving the property on its engine default. ]]
local function resolveEnum(map: EnumMap, value: any, label: string): any
	if value == nil then
		return nil
	end
	if type(value) == "string" then
		local mapped = map[value]
		if mapped == nil then
			local key = `{label}:{value}`
			if not warnedEnums[key] then
				warnedEnums[key] = true
				warn(`[Flux] unknown {label} "{value}"; falling back to default`)
			end
			return nil
		end
		return mapped
	end
	return value -- already an Enum
end

--[[
Reactive-aware `resolveEnum`: a Node/function source becomes a closure re-resolving on every
change. A closure cannot leave the property unset, so `default` (the engine default, always
expressed as a map entry) is written when resolution fails.
]]
local function enumProp(map: EnumMap, value: any, label: string, default: EnumItem): any
	if isReactiveValue(value) then
		return function()
			local resolved = resolveEnum(map, readDep(value), label)
			return if resolved == nil then default else resolved
		end
	end
	return resolveEnum(map, value, label)
end

local function toUDim(value: any): UDim
	if type(value) == "number" then
		return UDim.new(0, value)
	end
	return value
end

local function toUDim2(value: any): UDim2
	local kind = typeof(value)
	if kind == "Vector2" then
		return UDim2.fromOffset(value.X, value.Y)
	elseif kind == "number" then
		return UDim2.fromOffset(value, value)
	end
	return value
end

local function reactiveProp(value: any, convert: (any) -> any): any
	if isReactiveValue(value) then
		return function()
			return convert(readDep(value))
		end
	end
	return convert(value)
end

-- Resolves a Length value to a UDim, preserving reactivity (Node/fn → computed).
local function udimProp(value: any): any
	return reactiveProp(value, toUDim)
end

local function udim2Prop(value: any): any
	return reactiveProp(value, toUDim2)
end

-- Sets all four padding sides to the same static length.
local function applyAllSides(props: Props, value: any)
	local side = udimProp(value)
	props.PaddingTop, props.PaddingBottom, props.PaddingLeft, props.PaddingRight = side, side, side, side
end

-- Sets one padding side from a Length, skipping `nil` so the engine default shows through.
local function setSide(props: Props, prop: string, value: any)
	if value ~= nil then
		props[prop] = udimProp(value)
	end
end

-- Reactive closure for one padding side
local function paddingSide(source: any, field: string): () -> UDim
	return function()
		local value = readDep(source)
		if type(value) == "table" then
			return toUDim(value[field] or 0)
		elseif value == nil then
			return UDim.new()
		end
		return toUDim(value)
	end
end

-- Flex distribution values (friendly strings and raw UIFlexAlignment) route to the axis
-- Flex property instead of the Alignment one.
local function toFlexAlignment(value: any): EnumItem?
	if type(value) == "string" then
		return FLEX_ALIGNMENT[value]
	end
	if typeof(value) == "EnumItem" and (value :: EnumItem).EnumType == Enum.UIFlexAlignment then
		return value
	end
	return nil
end

--[[
Resolves one axis ("x"/"y") of a list's alignment to its (Alignment, Flex) prop values: an
axis-pinned override wins, otherwise `justify` routes to the main axis and `align` to the cross one
based on `direction`. Reactive inputs produce closures re-deriving the routing, which write engine
defaults where a static config would leave the property unset.
]]
local function listAlign(cfg: ListConfig, direction: any, axis: Direction, map: EnumMap, label: string): (any, any)
	local pinned = if axis == "x" then cfg.horizontalAlign else cfg.verticalAlign
	local align, justify = cfg.align, cfg.justify

	if pinned == nil and align == nil and justify == nil then
		return nil, nil
	end

	-- Yields the chosen input and its config key, so a bad string warns as the key the user wrote.
	-- A reactive pinned override that yields `nil` falls through to routing, like an absent one.
	local function value(): (any, string)
		if pinned ~= nil then
			local override = readDep(pinned)
			if override ~= nil then
				return override, label
			end
		end
		local main = readDep(direction) == FILL_DIRECTION.x
		if (axis == "x") == main then
			return readDep(justify), "justify"
		end
		return readDep(align), "align"
	end

	local reactive = if pinned ~= nil
		then isReactiveValue(pinned) -- a static pinned override never re-routes
		else isReactiveValue(direction) or isReactiveValue(align) or isReactiveValue(justify)
	if reactive then
		return function()
			local v, source = value()
			return if toFlexAlignment(v) ~= nil then map.start else resolveEnum(map, v, source) or map.start
		end, function()
			return toFlexAlignment((value())) or FLEX_ALIGNMENT.none
		end
	end

	local v, source = value()
	local flex = toFlexAlignment(v)
	if flex ~= nil then
		return nil, flex
	end
	return resolveEnum(map, v, source), nil
end

local Layout = {}

--[[
Creates a [`UIPadding`](https://create.roblox.com/docs/reference/engine/classes/UIPadding) from a single
length (applied to all sides), a per-side `{ top, bottom, left, right, x, y }` table, or a reactive
[node](https://flux.kohl.gg/guide/concepts/signals) or function yielding a length or a
`{ top, bottom, left, right }` struct such as
[`Flux.safeArea`](https://flux.kohl.gg/guide/utilities/responsive#safe-area). Plain `number` values are
offset pixels; a [`UDim`](https://create.roblox.com/docs/reference/engine/datatypes/UDim) is used as-is.
<em>Reactive sides bind and update in place; a reactive source may change shape between updates, and
`nil` reads as no padding.</em>

[Open Documentation](https://flux.kohl.gg/guide/utilities/layout#padding)
]]
function Layout.padding(value: Length | PaddingSides | Graph.Node<any> | (() -> Length | Insets)): UIPadding
	local props: Props = {}

	if isReactiveValue(value) then
		local source: any = new(value :: any) -- a function source becomes one computed shared by the sides
		props.PaddingTop = paddingSide(source, "top")
		props.PaddingBottom = paddingSide(source, "bottom")
		props.PaddingLeft = paddingSide(source, "left")
		props.PaddingRight = paddingSide(source, "right")
		if source ~= value then
			props._CLEAN = { source } -- the helper computed dies with the instance, not just its scope
		end
	elseif type(value) == "table" then
		local sides = value :: PaddingSides
		setSide(props, "PaddingTop", sides.top or sides.y)
		setSide(props, "PaddingBottom", sides.bottom or sides.y)
		setSide(props, "PaddingLeft", sides.left or sides.x)
		setSide(props, "PaddingRight", sides.right or sides.x)
	else -- single length, all sides
		applyAllSides(props, value)
	end

	return construct("UIPadding", props) :: any
end

--[[
Creates a [`UICorner`](https://create.roblox.com/docs/reference/engine/classes/UICorner) rounding the
parent's corners. `radius` is offset pixels or a
[`UDim`](https://create.roblox.com/docs/reference/engine/datatypes/UDim), optionally reactive; omit it
for the engine default (8 px).

[Open Documentation](https://flux.kohl.gg/guide/utilities/layout#corner)
]]
function Layout.corner(radius: Reactive<Length>?): UICorner
	return construct("UICorner", { CornerRadius = udimProp(radius) }) :: any
end

--[[
Creates a [`UIStroke`](https://create.roblox.com/docs/reference/engine/classes/UIStroke) outlining the
parent. `thickness` (px), `color`, and `transparency` bind reactively; `mode` is `"contextual"` (text
outline on text objects, border otherwise) or `"border"`, and `joins` is `"round"`/`"bevel"`/`"miter"`,
each also accepting the raw Enum or a reactive source.

[Open Documentation](https://flux.kohl.gg/guide/utilities/layout#stroke)
]]
function Layout.stroke(config: StrokeConfig?): UIStroke
	local cfg: StrokeConfig = config or {}
	return construct("UIStroke", {
		Thickness = cfg.thickness,
		Color = cfg.color,
		Transparency = cfg.transparency,
		ApplyStrokeMode = enumProp(STROKE_MODE, cfg.mode, "strokeMode", STROKE_MODE.contextual),
		LineJoinMode = enumProp(LINE_JOIN, cfg.joins, "lineJoin", LINE_JOIN.round),
	}) :: any
end

--[[
Creates a [`UIAspectRatioConstraint`](https://create.roblox.com/docs/reference/engine/classes/UIAspectRatioConstraint)
constraining a frame's width-to-height ratio. Every argument may be reactive.
@param ratio - The aspect ratio; may be a static number or a reactive [node](https://flux.kohl.gg/guide/concepts/signals).
@param aspectType - `"fit"` (FitWithinMaxSize) or `"scale"` (ScaleWithParentSize), or a raw [`Enum.AspectType`](https://create.roblox.com/docs/reference/engine/enums/AspectType).
@param dominantAxis - `"width"` or `"height"`, or a raw [`Enum.DominantAxis`](https://create.roblox.com/docs/reference/engine/enums/DominantAxis); an unknown string warns and falls back.

[Open Documentation](https://flux.kohl.gg/guide/utilities/layout#aspectratio)
]]
function Layout.aspectRatio(
	ratio: Reactive<number>,
	aspectType: Reactive<"fit" | "scale" | Enum.AspectType>?,
	dominantAxis: Reactive<"width" | "height" | Enum.DominantAxis>?
): UIAspectRatioConstraint
	return construct("UIAspectRatioConstraint", {
		AspectRatio = ratio,
		AspectType = enumProp(ASPECT_TYPE, aspectType, "aspectType", ASPECT_TYPE.fit),
		DominantAxis = enumProp(DOMINANT_AXIS, dominantAxis, "dominantAxis", DOMINANT_AXIS.width),
	}) :: any
end

--[[
Creates a [`UIListLayout`](https://create.roblox.com/docs/reference/engine/classes/UIListLayout) that
arranges siblings in a line with flexbox semantics. `gap` is the spacing between items (offset px or a
[`UDim`](https://create.roblox.com/docs/reference/engine/datatypes/UDim)); `direction` is `"x"`/`"y"`.
`align` sets the <strong>cross-axis</strong> and `justify` the <strong>main-axis</strong> value:
`"start"`/`"center"`/`"end"` align items, `"between"`/`"around"`/`"evenly"` distribute the free space,
and `"stretch"`/`"fill"` resize items to fill the axis. `horizontalAlign`/`verticalAlign` are explicit
axis-pinned overrides, `wraps` flows items onto multiple lines, and `lineAlign` aligns items within
their wrapped line. <em>Every value, including `direction`, may be reactive; alignments re-route when a
reactive `direction` flips.</em>

[Open Documentation](https://flux.kohl.gg/guide/utilities/layout#list)
]]
function Layout.list(config: ListConfig?): UIListLayout
	local cfg: ListConfig = config or {}
	local props: Props = {}

	props.Padding = udimProp(cfg.gap)
	props.Wraps = cfg.wraps
	props.ItemLineAlignment = enumProp(ITEM_LINE_ALIGN, cfg.lineAlign, "lineAlign", ITEM_LINE_ALIGN.automatic)

	local direction: any = cfg.direction
	if isReactiveValue(direction) then
		local source = direction
		direction = computed(function()
			return resolveEnum(FILL_DIRECTION, readDep(source), "direction") or FILL_DIRECTION.y
		end)
		props._CLEAN = { direction }
	else
		direction = resolveEnum(FILL_DIRECTION, direction, "direction")
	end
	props.FillDirection = direction

	props.HorizontalAlignment, props.HorizontalFlex =
		listAlign(cfg, direction, "x", HORIZONTAL_ALIGN, "horizontalAlign")
	props.VerticalAlignment, props.VerticalFlex = listAlign(cfg, direction, "y", VERTICAL_ALIGN, "verticalAlign")

	return construct("UIListLayout", props) :: any
end

--[[
Creates a [`UIGridLayout`](https://create.roblox.com/docs/reference/engine/classes/UIGridLayout) that
arranges siblings in a uniform grid. `cell` is the cell size and `gap` the spacing, each a
[`Vector2`](https://create.roblox.com/docs/reference/engine/datatypes/Vector2), a `number` (offset px), or a
[`UDim2`](https://create.roblox.com/docs/reference/engine/datatypes/UDim2). `fill` is the flow direction
`"x"`/`"y"`; `align`/`justify` map to horizontal/vertical alignment; `maxCells` caps cells per line.
<em>Every value may be reactive.</em>

[Open Documentation](https://flux.kohl.gg/guide/utilities/layout#grid)
]]
function Layout.grid(config: GridConfig?): UIGridLayout
	local cfg: GridConfig = config or {}
	return construct("UIGridLayout", {
		CellSize = udim2Prop(cfg.cell),
		CellPadding = udim2Prop(cfg.gap),
		FillDirectionMaxCells = cfg.maxCells,
		FillDirection = enumProp(FILL_DIRECTION, cfg.fill, "fill", FILL_DIRECTION.x),
		HorizontalAlignment = enumProp(HORIZONTAL_ALIGN, cfg.align, "align", HORIZONTAL_ALIGN.start),
		VerticalAlignment = enumProp(VERTICAL_ALIGN, cfg.justify, "justify", VERTICAL_ALIGN.start),
	}) :: any
end

--[[
Creates a [`UIFlexItem`](https://create.roblox.com/docs/reference/engine/classes/UIFlexItem) controlling how
a child grows or shrinks inside a flex
[`UIListLayout`](https://create.roblox.com/docs/reference/engine/classes/UIListLayout). `mode` is `"fill"`
(the default when omitted), `"grow"`, `"shrink"`, or `"none"`, or a raw
[`Enum.UIFlexMode`](https://create.roblox.com/docs/reference/engine/enums/UIFlexMode), optionally reactive.

[Open Documentation](https://flux.kohl.gg/guide/utilities/layout#flex)
]]
function Layout.flex(mode: Reactive<FlexMode | Enum.UIFlexMode>?): UIFlexItem
	local resolved: any
	if isReactiveValue(mode) then
		resolved = function()
			local value = readDep(mode)
			return resolveEnum(FLEX_MODE, if value == nil then "fill" else value, "flexMode") or FLEX_MODE.none
		end
	else
		resolved = resolveEnum(FLEX_MODE, if mode == nil then "fill" else mode, "flexMode")
	end
	return construct("UIFlexItem", { FlexMode = resolved }) :: any
end

return table.freeze(Layout)
