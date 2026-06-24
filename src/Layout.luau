--!strict

local Compat = require("./Compat")
local Graph = require("./Graph")
local construct = require("./Construct")

local IS_ROBLOX = Compat.isRoblox
local warn = Compat.warn

local isNode = Graph.isNode
local raw = Graph.raw
local read = Graph.read

type Props = { [string]: any }

-- A value that may be static, a reactive Node, or a computation function.
export type Reactive<T> = T | Graph.Node<T> | (() -> T)
export type Length = number | UDim
export type Align = "start" | "center" | "end"
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
	direction: (Direction | Enum.FillDirection)?,
	align: Align?,
	justify: Align?,
	horizontalAlign: (Align | Enum.HorizontalAlignment)?,
	verticalAlign: (Align | Enum.VerticalAlignment)?,
	wraps: Reactive<boolean>?,
}

export type GridConfig = {
	cell: Reactive<number | Vector2 | UDim2>?,
	gap: Reactive<number | Vector2 | UDim2>?,
	fill: (Direction | Enum.FillDirection)?,
	align: (Align | Enum.HorizontalAlignment)?,
	justify: (Align | Enum.VerticalAlignment)?,
	maxCells: Reactive<number>?,
}

local FILL_DIRECTION: Props
local HORIZONTAL_ALIGN: Props
local VERTICAL_ALIGN: Props
local FLEX_MODE: Props
local ASPECT_TYPE: Props
local DOMINANT_AXIS: Props

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
end

--[[ Friendly string → Enum; passes through a real Enum; warns + falls back on a bad string. ]]
local function resolveEnum(map: Props, value: any, default: any, label: string): any
	if value == nil then
		return nil
	end
	if type(value) == "string" then
		local mapped = map[value]
		if mapped == nil then
			warn(`[Flux] unknown {label} "{value}"; falling back to default`)
			return default
		end
		return mapped
	end
	return value -- already an Enum
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
	if isNode(value) then
		return function()
			return convert(read(value))
		end
	elseif type(value) == "function" then
		return function()
			return convert((value :: any)())
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

-- Sets all four padding sides to the same (reactive) length, sharing one closure.
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

-- Reactive closure reading one inset field (e.g. `top`) off a struct node, defaulting to 0.
local function structSide(node: any, field: string): () -> UDim
	return function()
		return UDim.new(0, (read(node) :: any)[field] or 0)
	end
end

local Layout = {}

--[[
Creates a [`UIPadding`](https://create.roblox.com/docs/reference/engine/classes/UIPadding) from a single
length (applied to all sides), a per-side `{ top, bottom, left, right, x, y }` table, or a reactive
[node](https://flux.kohl.gg/guide/concepts/signals) such as
[`Flux.safeArea`](https://flux.kohl.gg/guide/utilities/responsive#safe-area). Plain `number` values are
offset pixels; a [`UDim`](https://create.roblox.com/docs/reference/engine/datatypes/UDim) is used as-is.
<em>Reactive sides bind and update in place.</em>

[Open Documentation](https://flux.kohl.gg/guide/utilities/layout#padding)
]]
function Layout.padding(value: number | UDim | PaddingSides | Graph.Node<any>): UIPadding
	local props: Props = {}

	if isNode(value) then
		if type(raw(value)) == "table" then -- struct node, e.g. safeArea
			props.PaddingTop = structSide(value, "top")
			props.PaddingBottom = structSide(value, "bottom")
			props.PaddingLeft = structSide(value, "left")
			props.PaddingRight = structSide(value, "right")
		else -- single length node, all sides
			applyAllSides(props, value)
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
Creates a [`UIAspectRatioConstraint`](https://create.roblox.com/docs/reference/engine/classes/UIAspectRatioConstraint)
constraining a frame's width-to-height ratio.
@param ratio - The aspect ratio; may be a static number or a reactive [node](https://flux.kohl.gg/guide/concepts/signals).
@param aspectType - `"fit"` (FitWithinMaxSize) or `"scale"` (ScaleWithParentSize), or a raw [`Enum.AspectType`](https://create.roblox.com/docs/reference/engine/enums/AspectType).
@param dominantAxis - `"width"` or `"height"`, or a raw [`Enum.DominantAxis`](https://create.roblox.com/docs/reference/engine/enums/DominantAxis); an unknown string warns and falls back.

[Open Documentation](https://flux.kohl.gg/guide/utilities/layout#aspectratio)
]]
function Layout.aspectRatio(
	ratio: Reactive<number>,
	aspectType: ("fit" | "scale" | Enum.AspectType)?,
	dominantAxis: ("width" | "height" | Enum.DominantAxis)?
): UIAspectRatioConstraint
	local props: Props = { AspectRatio = ratio }
	if aspectType ~= nil then
		props.AspectType = resolveEnum(ASPECT_TYPE, aspectType, Enum.AspectType.FitWithinMaxSize, "aspectType")
	end
	if dominantAxis ~= nil then
		props.DominantAxis = resolveEnum(DOMINANT_AXIS, dominantAxis, Enum.DominantAxis.Width, "dominantAxis")
	end
	return construct("UIAspectRatioConstraint", props) :: any
end

--[[
Creates a [`UISizeConstraint`](https://create.roblox.com/docs/reference/engine/classes/UISizeConstraint)
bounding an element's pixel size. `min` and `max` are
[`Vector2`](https://create.roblox.com/docs/reference/engine/datatypes/Vector2) pixel sizes; either may be
omitted or reactive.

[Open Documentation](https://flux.kohl.gg/guide/utilities/layout#sizeconstraint)
]]
function Layout.sizeConstraint(min: Reactive<Vector2>?, max: Reactive<Vector2>?): UISizeConstraint
	local props: Props = {}
	if min ~= nil then
		props.MinSize = min
	end
	if max ~= nil then
		props.MaxSize = max
	end
	return construct("UISizeConstraint", props) :: any
end

--[[
Creates a [`UIListLayout`](https://create.roblox.com/docs/reference/engine/classes/UIListLayout) that
arranges siblings in a line. `gap` is the spacing between items (offset px or a
[`UDim`](https://create.roblox.com/docs/reference/engine/datatypes/UDim)); `direction` is `"x"`/`"y"`.
`align` sets <strong>cross-axis</strong> and `justify` <strong>main-axis</strong> alignment using flexbox
semantics, while `horizontalAlign`/`verticalAlign` are explicit axis-pinned overrides. `wraps` flows items
onto multiple lines.

[Open Documentation](https://flux.kohl.gg/guide/utilities/layout#list)
]]
function Layout.list(config: ListConfig?): UIListLayout
	local cfg: ListConfig = config or {}
	local props: Props = {}

	if cfg.gap ~= nil then
		props.Padding = udimProp(cfg.gap)
	end
	if cfg.wraps ~= nil then
		props.Wraps = cfg.wraps
	end

	local direction = resolveEnum(FILL_DIRECTION, cfg.direction, nil, "direction")
	if direction ~= nil then
		props.FillDirection = direction
	end

	local horizontal = direction == Enum.FillDirection.Horizontal
	local h = cfg.horizontalAlign
	local v = cfg.verticalAlign
	if cfg.align ~= nil then
		if horizontal then
			v = v or cfg.align
		else
			h = h or cfg.align
		end
	end
	if cfg.justify ~= nil then
		if horizontal then
			h = h or cfg.justify
		else
			v = v or cfg.justify
		end
	end
	if h ~= nil then
		props.HorizontalAlignment = resolveEnum(HORIZONTAL_ALIGN, h, nil, "horizontalAlign")
	end
	if v ~= nil then
		props.VerticalAlignment = resolveEnum(VERTICAL_ALIGN, v, nil, "verticalAlign")
	end

	return construct("UIListLayout", props) :: any
end

--[[
Creates a [`UIGridLayout`](https://create.roblox.com/docs/reference/engine/classes/UIGridLayout) that
arranges siblings in a uniform grid. `cell` is the cell size and `gap` the spacing, each a
[`Vector2`](https://create.roblox.com/docs/reference/engine/datatypes/Vector2), a `number` (offset px), or a
[`UDim2`](https://create.roblox.com/docs/reference/engine/datatypes/UDim2). `fill` is the flow direction
`"x"`/`"y"`; `align`/`justify` map to horizontal/vertical alignment; `maxCells` caps cells per line.

[Open Documentation](https://flux.kohl.gg/guide/utilities/layout#grid)
]]
function Layout.grid(config: GridConfig?): UIGridLayout
	local cfg: GridConfig = config or {}
	local props: Props = {}

	if cfg.cell ~= nil then
		props.CellSize = udim2Prop(cfg.cell)
	end
	if cfg.gap ~= nil then
		props.CellPadding = udim2Prop(cfg.gap)
	end
	if cfg.maxCells ~= nil then
		props.FillDirectionMaxCells = cfg.maxCells
	end

	local fill = resolveEnum(FILL_DIRECTION, cfg.fill, nil, "fill")
	if fill ~= nil then
		props.FillDirection = fill
	end
	if cfg.align ~= nil then
		props.HorizontalAlignment = resolveEnum(HORIZONTAL_ALIGN, cfg.align, nil, "align")
	end
	if cfg.justify ~= nil then
		props.VerticalAlignment = resolveEnum(VERTICAL_ALIGN, cfg.justify, nil, "justify")
	end

	return construct("UIGridLayout", props) :: any
end

--[[
Creates a [`UIFlexItem`](https://create.roblox.com/docs/reference/engine/classes/UIFlexItem) controlling how
a child grows or shrinks inside a flex
[`UIListLayout`](https://create.roblox.com/docs/reference/engine/classes/UIListLayout). `mode` is
`"fill"`/`"grow"`/`"shrink"`/`"none"` or a raw
[`Enum.UIFlexMode`](https://create.roblox.com/docs/reference/engine/enums/UIFlexMode).

[Open Documentation](https://flux.kohl.gg/guide/utilities/layout#flex)
]]
function Layout.flex(mode: FlexMode | Enum.UIFlexMode): UIFlexItem
	local resolved = resolveEnum(FLEX_MODE, mode, Enum.UIFlexMode.Fill, "flex mode")
	return construct("UIFlexItem", { FlexMode = resolved }) :: any
end

return table.freeze(Layout)
