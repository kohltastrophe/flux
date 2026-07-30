--!strict

local Compat = require("./Compat")
local Graph = require("./Graph")

local IS_ROBLOX = Compat.isRoblox
local warn = Compat.warn

local computed = Graph.computed
local readDep = Graph.readDep
local signal = Graph.signal

export type ScaleMode = "min" | "width" | "height" | "max"
export type Breakpoint = "phone" | "tablet" | "desktop"
export type Platform = "console" | "mobile" | "pc" | "vr"
export type SafeAreaInsets = { top: number, bottom: number, left: number, right: number }
export type Breakpoints = { phone: number, tablet: number }

export type Config = {
	reference: Vector2,
	mode: ScaleMode,
	min: number?,
	max: number?,
	breakpoints: Breakpoints,
}

export type PartialConfig = {
	reference: Vector2?,
	mode: ScaleMode?,
	min: number?,
	max: number?,
	breakpoints: Breakpoints?,
	viewport: Graph.Reactive<Vector2>?,
}

local DEFAULT_SIZE = (if IS_ROBLOX then Vector2.new(1920, 1080) else { X = 1920, Y = 1080 }) :: any

--[[
	Live defaults shared by every derived node; mutate once at startup.

	[Open Documentation](https://flux.kohl.gg/guide/utilities/responsive#configuration)
]]
local config: Config = {
	reference = DEFAULT_SIZE,
	mode = "min",
	breakpoints = { phone = 600, tablet = 1024 },
}

local EMPTY: PartialConfig = {}

-- Pure scale derivation: viewport (width, height) → UIScale factor (1.0 = at reference).
-- Falls back to the live `config` field-by-field: this runs per recompute, so overridden
-- fields stay fixed while the rest inherit later `config` mutations without allocating.
local function scaleFor(width: number, height: number, partial: PartialConfig): number
	local ref = partial.reference or config.reference
	local mode = partial.mode or config.mode

	local factor: number
	if mode == "width" then
		factor = width / ref.X
	elseif mode == "height" then
		factor = height / ref.Y
	elseif mode == "max" then
		factor = math.max(width / ref.X, height / ref.Y)
	else
		if mode ~= "min" then
			warn(`[Flux] unknown scale mode "{mode}"; falling back to "min"`)
		end
		factor = math.min(width / ref.X, height / ref.Y)
	end

	local min = if partial.min ~= nil then partial.min else config.min
	if min ~= nil and factor < min then
		factor = min
	end
	local max = if partial.max ~= nil then partial.max else config.max
	if max ~= nil and factor > max then
		factor = max
	end

	return factor
end

-- Pure breakpoint derivation: viewport width → size class.
local function breakpointFor(width: number, partial: PartialConfig): Breakpoint
	local breakpoints = partial.breakpoints or config.breakpoints
	if width < breakpoints.phone then
		return "phone"
	elseif width < breakpoints.tablet then
		return "tablet"
	end
	return "desktop"
end

--[[
	The active camera's `ViewportSize` as a node, live on the client.

	[Open Documentation](https://flux.kohl.gg/guide/utilities/responsive#viewport)
]]
local viewport: Graph.Node<Vector2> = signal(DEFAULT_SIZE)

--[[
	Factory escape hatch: a `scale` node with per-surface config (merged over defaults).

	[Open Documentation](https://flux.kohl.gg/guide/utilities/responsive#per-surface-overrides)
]]
local function scaleOf(partial: PartialConfig?): Graph.Node<number>
	local cfg = partial or EMPTY
	local source = cfg.viewport or viewport
	return computed(function(): number
		local vp = readDep(source) :: Vector2
		return scaleFor(vp.X, vp.Y, cfg)
	end)
end

--[[
	Factory escape hatch: a `breakpoint` node with per-surface thresholds.

	[Open Documentation](https://flux.kohl.gg/guide/utilities/responsive#per-surface-overrides)
]]
local function breakpointOf(partial: PartialConfig?): Graph.Node<Breakpoint>
	local cfg = partial or EMPTY
	local source = cfg.viewport or viewport
	return computed(function(): Breakpoint
		local vp = readDep(source) :: Vector2
		return breakpointFor(vp.X, cfg)
	end)
end

--[[
	UIScale factor derived from `viewport`; `1.0` at `config.reference`.

	[Open Documentation](https://flux.kohl.gg/guide/utilities/responsive#scale)
]]
local scale: Graph.Node<number> = scaleOf()

--[[
	Size class derived from `viewport` width.

	[Open Documentation](https://flux.kohl.gg/guide/utilities/responsive#breakpoint)
]]
local breakpoint: Graph.Node<Breakpoint> = breakpointOf()

--[[
	The device class detected at startup: `"vr"`, `"console"` (ten-foot interface), `"pc"`
	(keyboard and mouse), or `"mobile"`; `"pc"` where detection is unavailable (server, headless).

	[Open Documentation](https://flux.kohl.gg/guide/utilities/responsive#platform)
]]
local platform: Platform = "pc"

--[[
	Topbar / Core-UI inset pixels from `GuiService:GetGuiInset()`.

	[Open Documentation](https://flux.kohl.gg/guide/utilities/responsive#safe-area)
]]
local safeArea: Graph.Node<SafeAreaInsets> = signal(
	{ top = 0, bottom = 0, left = 0, right = 0 },
	function(a: SafeAreaInsets, b: SafeAreaInsets): boolean
		return a.top == b.top and a.bottom == b.bottom and a.left == b.left and a.right == b.right
	end
)

if IS_ROBLOX and game:GetService("RunService"):IsClient() then
	local GuiService = game:GetService("GuiService")
	local UserInputService = game:GetService("UserInputService")

	platform = if UserInputService.VREnabled
		then "vr"
		elseif GuiService:IsTenFootInterface() then "console"
		elseif UserInputService.KeyboardEnabled and UserInputService.MouseEnabled then "pc"
		else "mobile"

	local function recomputeSafeArea()
		local topLeft, bottomRight = GuiService:GetGuiInset()
		safeArea:set({
			top = topLeft.Y,
			bottom = bottomRight.Y,
			left = topLeft.X,
			right = bottomRight.X,
		})
	end

	local viewportConnection: RBXScriptConnection?
	local function bindCamera(camera: Camera?)
		if viewportConnection ~= nil then
			viewportConnection:Disconnect()
			viewportConnection = nil
		end
		if camera ~= nil then
			viewport:set(camera.ViewportSize)
			viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				viewport:set(camera.ViewportSize)
				recomputeSafeArea()
			end)
		end
	end

	bindCamera(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera(workspace.CurrentCamera)
	end)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(recomputeSafeArea)
	recomputeSafeArea()
end

return table.freeze({
	config = config,
	platform = platform,

	viewport = viewport,
	scale = scale,
	breakpoint = breakpoint,
	safeArea = safeArea,

	scaleOf = scaleOf,
	breakpointOf = breakpointOf,
})
