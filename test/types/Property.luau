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

return { text, size, parent, tagged, taggedPrefix, unionText }
