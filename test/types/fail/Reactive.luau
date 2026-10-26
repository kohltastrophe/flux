--!strict
--[[
	Compile-fail checks for reactive values. Lint requires a type error on every marked line and on no other line, so a
	`Reactive` or `Node` that quietly widens to `any` fails lint even though a normal analysis would pass.
]]

local Flux = require("../../../src")

type Props = { label: Flux.Reactive<string>, count: Flux.Reactive<number>? }
local function Label(_props: Props) end

local name = Flux.signal("Save")
local count = Flux.signal(1)
local function five(): number
	return 5
end
local function toText(id: number): string
	return tostring(id)
end
local function frame(): Frame
	return Flux.new("Frame")({})
end

Label({ label = count }) -- expect-error: a number node is not a string
Label({ label = "Save", count = name }) -- expect-error: a string node is not a number
Label({ label = five }) -- expect-error: the getter returns a number
local _read: number = Flux.read(name) -- expect-error: read keeps the node's type
local _getter: string = Flux.read(five) -- expect-error: read keeps the getter's type
local _node: Flux.Node<number> = name -- expect-error: nodes are not interchangeable across types
local _context: number = Flux.context("dark"):get() -- expect-error: the context holds a string
local _spring: string = Flux.spring(count)() -- expect-error: a spring keeps its target's type
local _async: number? = Flux.async(count, toText).data() -- expect-error: data is a string
local _shown: Flux.Node<TextLabel?> = Flux.show(count, frame) -- expect-error: show keeps the branch type
Flux.cleanup(5) -- expect-error: a number cannot be cleaned up
name:set(5) -- expect-error: a signal's writes are checked
Flux.computed(five):onObserved(5) -- expect-error: a hook takes a function
local _picked = Flux.split({ label = "a", Size = 1 } :: { label: string, Size: number }, { label = true }).Size -- expect-error: Size is not in the group
local getCount, setCount = Flux.createSignal(1)
local _badFastGet: string = getCount() -- expect-error: createSignal getter returns number
setCount("not a number") -- expect-error: createSignal setter checks value type
local _badNodeGet: string = Flux.getter(count)() -- expect-error: Flux.getter preserves node type
Flux.setter(name)(123) -- expect-error: Flux.setter checks value type

return nil
