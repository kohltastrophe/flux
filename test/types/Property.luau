--!strict
--[[
	Compile-time checks for `Flux.property`, `_Prop` change listeners, and `__EVENT` / `__ATTR` / `__TAG`: a property
	node takes the property's type, `#Tag` / `_tag_Tag` gives `boolean`, `$Attr` / `_attr_Attr` or an unknown key gives
	`any`, and `_Prop` / `__EVENT` listeners receive the property's value. Lint type-checks this file; it is never run.
]]

local Flux = require("../../src")

local box = Instance.new("TextBox")

local text: Flux.Node<string> = Flux.property(box, "Text")
local size: Flux.Node<Vector2> = Flux.property(box, "AbsoluteSize")
local parent: Flux.Node<Instance?> = Flux.property(box, "Parent")
local tagged: Flux.Node<boolean> = Flux.property(box, "#Focused")
local taggedPrefix: Flux.Node<boolean> = Flux.property(box, "_tag_Focused")
local _name: string = Flux.property(box, "Name"):get()
local _health: number = Flux.property(box, "$Health"):get() -- an attribute is `any`
local _healthPrefix: number = Flux.property(box, "_attr_Health"):get()
local _terse: number = Flux(box, "Text"):get() -- `Flux(instance, prop)` stays untyped

Flux.edit(box)({
	_Text = function(_value: string) end,
	_AbsoluteSize = function(_value: Vector2) end,
	__EVENT = {
		Text = function(_value: string) end,
		AbsoluteSize = function(_value: Vector2) end, -- read-only properties have listeners too
		__ATTR = {
			Health = function(_value: number) end,
		},
		__TAG = {
			Focused = function(_has: boolean) end,
		},
	},
	FocusLost = function() end, -- signals connect at the top level
})

assert(text:peek() == box.Text)

local unionTarget: TextButton | TextLabel = Instance.new("TextButton")
local unionText: Flux.Node<string> = Flux.property(unionTarget, "Text")
Flux.edit(unionTarget)({
	Text = "Union",
})

local dynamicClass: string = "Frame"
local dynamicInst: Instance = Flux.new(dynamicClass)({ Name = "Dynamic" })
assert(dynamicInst.Name == "Dynamic")

local Type = require("../../src/Type")

local _mergedFrame: Frame = Flux.new("Frame")(Flux.merge({ Name = "Merged" }, { ZIndex = 2 }))
local _mergedFrozen: Frame = Flux.new("Frame")(Flux.merge(table.freeze({ Name = "Frozen" }), { ZIndex = 3 }))

local function _checkUnionAndSubclass(
	unionProps: Type.Properties<Frame | TextLabel>,
	btnProps: Type.Properties<TextButton>
)
	local _bg: Flux.Reactive<Color3>? = unionProps.BackgroundColor3
	local _text: Flux.Reactive<string>? = btnProps.Text
	return _bg, _text
end

local NULLABLE_OWN = {
	tag = Flux.prop(nil :: string?),
	opt = Flux.prop() :: Flux.Reactive<number>?,
}
local nullableOwn, nullableRest =
	Flux.split({ Name = "N", tag = "abc" } :: Flux.Props<"Frame", typeof(NULLABLE_OWN)>, NULLABLE_OWN)
local _tagVal: string? = nullableOwn.tag
local _optVal: Flux.Reactive<number>? = nullableOwn.opt
local _restName: Flux.Reactive<string>? = nullableRest.Name

local _onComputed: Flux.Node<number> = Flux.computed(Flux.on(Flux.signal(1), function(v: number): number
	return v + 1
end))
local _refFrameSignal = Flux.signal(nil :: Frame?)
local _refInstanceSignal = Flux.signal(nil :: Instance?)
local _withTypedRefs = Flux.new("Frame")({
	__REF = _refFrameSignal,
	LayoutOrder = _onComputed,
})
local _withInstanceRef = Flux.new("Frame")({ __REF = _refInstanceSignal })
local _withCallbackRef = Flux.new("Frame")({
	__REF = function(frame: Frame)
		local _ = frame.BackgroundTransparency
	end,
})
local _tweenCfg: Flux.TweenConfig = { Time = 0.25, DelayTime = 0.1 }
local _phase: Flux.ClockPhase = "RenderStepped"
local _scaleMode: Flux.ScaleMode = "width"
local _bps: Flux.Breakpoints = { phone = 600, tablet = 900 }
local _respCfg: Flux.ResponsiveConfig = {
	reference = Vector2.new(1920, 1080),
	mode = "min",
	min = 0.75,
	max = 1.5,
	breakpoints = _bps,
}
local _respPartial: Flux.ResponsivePartialConfig = { mode = "width", min = 0.5 }

return {
	text,
	size,
	parent,
	tagged,
	taggedPrefix,
	unionText,
	_mergedFrame,
	_mergedFrozen,
	_checkUnionAndSubclass,
	_tagVal,
	_optVal,
	_restName,
	_withTypedRefs,
	_withInstanceRef,
	_withCallbackRef,
	_onComputed,
	_tweenCfg,
	_phase,
	_scaleMode,
	_bps,
	_respCfg,
	_respPartial,
}
