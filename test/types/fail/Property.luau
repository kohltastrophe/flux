--!strict
--[[
	Compile-fail checks for `Flux.property`, `_Prop`, and `__EVENT` change listeners. Lint requires a type error on
	every marked line and on no other line.
]]

local Flux = require("../../../src")

local box = Instance.new("TextBox")

local _text: Flux.Node<number> = Flux.property(box, "Text") -- expect-error: Text is a string
local _size: string = Flux.property(box, "AbsoluteSize"):get() -- expect-error: AbsoluteSize is a Vector2
local _tag: string = Flux.property(box, "#Focused"):get() -- expect-error: a tag property is boolean
Flux.edit(box)({ __EVENT = { FocusLost = function() end } }) -- expect-error: a signal is not a property listener
Flux.edit(box)({ __EVENT = { Text = function(_value: number) end } }) -- expect-error: Text changes to a string
Flux.edit(box)({ __EVENT = { Text = Flux.signal("") } }) -- expect-error: a node is not a listener
Flux.edit(box)({ _Text = function(_value: number) end }) -- expect-error: _Text listener receives a string
Flux.edit(box)({ __TAG = 123 }) -- expect-error: __TAG expects a tag or tag list, not a number

return nil
