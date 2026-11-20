--!strict
--[[
	Compile-fail checks for component props. Lint requires a type error on every marked line and on no other line, so a
	props type that quietly accepts these calls fails lint even though a normal analysis would pass.
]]

local Flux = require("../../../src")

type ButtonProps = Flux.Props<"TextButton", {
	label: Flux.Reactive<string>,
	variant: Flux.Reactive<"filled" | "tonal">?,
}>

local function Button(_props: ButtonProps): TextButton
	return Flux.new("TextButton")({})
end

Button({ label = 5 }) -- expect-error: label is not a string
Button({ label = "Save", variant = "ghost" }) -- expect-error: variant is not one of the options
Button({ label = "Save", Size = "big" }) -- expect-error: Size is not a UDim2
Button({ variant = "tonal" }) -- expect-error: label is required
type ReadOnlyHost = { read Locked: number, Name: string }
local function idNum(v: number): number
	return v
end

Button({ label = "Save", _Text = 123 }) -- expect-error: _Text change listener must be a function
local _badRef = Flux.new("Frame")({ __REF = 123 }) -- expect-error: __REF expects a callback or state node
local _badRefClass = Flux.new("Frame")({ __REF = Flux.signal(nil :: TextLabel?) }) -- expect-error: State<TextLabel?> is incompatible with Frame
local _badTextNode = Flux.new("TextLabel")({ Text = Flux.signal(123) }) -- expect-error: Text expects string or Node<string>
local _badReadOnly: Flux.Props<ReadOnlyHost> = { Locked = 1 } -- expect-error: read-only properties map to nil
local _badDeferredOn: Flux.Node<number> = Flux.computed(Flux.on(Flux.signal(1), idNum, true)) -- expect-error: deferred Flux.on returns (number?) -> number?
local _badFrame: Flux.Props<"Frame"> = { BackgroundTransparency = "opaque" } -- expect-error: BackgroundTransparency is a number

-- Own props given as an intersection merge like a single table: every part's members are checked.
type FieldProps = Flux.Props<"Frame", { label: string } & { help: string? }>
local _field: FieldProps = { label = "Name", help = 5 } -- expect-error: help is not a string
local _missing: FieldProps = { help = "Shown under the field" } -- expect-error: label is required

return nil
