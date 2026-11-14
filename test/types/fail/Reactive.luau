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
Flux.model("not a node") -- expect-error: model requires a writable node
local function badNumToStr(cur: number): string
	return tostring(cur)
end
count:update(badNumToStr) -- expect-error: functional update return must match State<T>
local function takesStr(cur: string): string
	return cur
end
local _badOn = Flux.on(count, takesStr) -- expect-error: Flux.on unwraps dependency type
type TypedSig = { Connect: (self: any, fn: (value: number) -> ()) -> () -> () }
local typedSig: TypedSig = nil :: any
local _badFromSig: Flux.Node<string?> = Flux.fromSignal(typedSig) -- expect-error: fromSignal preserves signal payload type
local mergedRo = Flux.merge({ label = "Hi" }, { count = 1 })
mergedRo.count = 2 -- expect-error: merged props table is read-only
local _badFb = Flux.forValue(function()
	return { 1 }
end, function(_i, v: number)
	return v
end, "not a fn") -- expect-error: fallback must be a function

local function _badNumToStr(_n: number): string
	return "wrong"
end
local _badSpring = Flux.spring(0)
local _badSpringSet = _badSpring:set("wrong") -- expect-error: set expects number | Node<number>
local _badSpringUpdate = _badSpring:update(_badNumToStr) -- expect-error: update fn must return number | Node<number>

return nil
