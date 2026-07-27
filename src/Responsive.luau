--!strict

local Compat = require("./Compat")
local Graph = require("./Graph")

local IS_ROBLOX = Compat.isRoblox
local warn = Compat.warn

local computed = Graph.computed
local readDep = Graph.readDep
local signal = Graph.signal

export type ScaleMode = "min" | "width" | "height" | "max" | "diagonal"
export type Breakpoint = "phone" | "tablet" | "desktop"
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

local config: Config = {
	reference = DEFAULT_SIZE,
	mode = "min",
	breakpoints = { phone = 600, tablet = 1024 },
}

--[[ Merges a partial config over the live defaults; `nil` returns the live table. ]]
local function mergeConfig(partial: PartialConfig?): Config
	if partial == nil then
		return config
	end
	return {
		reference = partial.reference or config.reference,
		mode = partial.mode or config.mode,
		min = if partial.min ~= nil then partial.min else config.min,
		max = if partial.max ~= nil then partial.max else config.max,
		breakpoints = partial.breakpoints or config.breakpoints,
	}
end

--[[ Pure scale derivation: viewport (width, height) → UIScale factor (1.0 = at reference). ]]
local function scaleFor(width: number, height: number, partial: PartialConfig?): number
	local cfg = mergeConfig(partial)
	local ref = cfg.reference
	local mode = cfg.mode

	local factor: number
	if mode == "width" then
		factor = width / ref.X
	elseif mode == "height" then
		factor = height / ref.Y
	elseif mode == "max" then
		factor = math.max(width / ref.X, height / ref.Y)
	elseif mode == "diagonal" then
		factor = math.sqrt(width * width + height * height) / math.sqrt(ref.X * ref.X + ref.Y * ref.Y)
	else
		if mode ~= "min" then
			warn(`[Flux] unknown scale mode "{tostring(mode)}"; falling back to "min"`)
		end
		factor = math.min(width / ref.X, height / ref.Y)
	end

	local min = cfg.min
	if min ~= nil and factor < min then
		factor = min
	end
	local max = cfg.max
	if max ~= nil and factor > max then
		factor = max
	end

	return factor
end

--[[ Pure breakpoint derivation: viewport width → size class. ]]
local function breakpointFor(width: number, partial: PartialConfig?): Breakpoint
	local breakpoints = mergeConfig(partial).breakpoints
	if width < breakpoints.phone then
		return "phone"
	elseif width < breakpoints.tablet then
		return "tablet"
	end
	return "desktop"
end

local viewport: Graph.Node<Vector2> = signal(DEFAULT_SIZE)

--[[ Factory escape hatch: a `scale` node with per-surface config (merged over defaults). ]]
local function scaleOf(partial: PartialConfig?): Graph.Node<number>
	local source = (if partial then partial.viewport else nil) or viewport
	return computed(function(): number
		local vp = readDep(source) :: Vector2
		return scaleFor(vp.X, vp.Y, partial)
	end)
end

--[[ Factory escape hatch: a `breakpoint` node with per-surface thresholds. ]]
local function breakpointOf(partial: PartialConfig?): Graph.Node<Breakpoint>
	local source = (if partial then partial.viewport else nil) or viewport
	return computed(function(): Breakpoint
		local vp = readDep(source) :: Vector2
		return breakpointFor(vp.X, partial)
	end)
end

local scale: Graph.Node<number> = scaleOf()
local breakpoint: Graph.Node<Breakpoint> = breakpointOf()

local safeArea: Graph.Node<SafeAreaInsets> = signal(
	{ top = 0, bottom = 0, left = 0, right = 0 },
	function(a: SafeAreaInsets, b: SafeAreaInsets): boolean
		return a.top == b.top and a.bottom == b.bottom and a.left == b.left and a.right == b.right
	end
)

if IS_ROBLOX and game:GetService("RunService"):IsClient() then
	local GuiService = game:GetService("GuiService")

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

	viewport = viewport,
	scale = scale,
	breakpoint = breakpoint,
	safeArea = safeArea,

	scaleOf = scaleOf,
	breakpointOf = breakpointOf,

	scaleFor = scaleFor,
	breakpointFor = breakpointFor,
})
