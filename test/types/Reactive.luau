--!strict
local Flux = require("../../src")

type Node<T> = Flux.Node<T>
type Reactive<T> = Flux.Reactive<T>

local name = Flux.signal("Save")
local count = Flux.signal(1)
local tone = Flux.signal("tonal" :: "filled" | "tonal")
local tint = Flux.signal(Color3.new(1, 1, 1))

type Option = { value: string, label: Reactive<string> }
type Props = {
	label: Reactive<string>,
	hint: Reactive<string?>?,
	color: Reactive<Color3 | string>?,
	variant: Reactive<"filled" | "tonal">?,
	options: Reactive<{ Option }>?,
}
local function Button(_props: Props) end

Button({ label = name, hint = name, color = tint, variant = tone })
Button({ label = "Save", variant = "filled", options = { { value = "a", label = "A" } } })
Button({
	label = function()
		return `{count()} items`
	end,
	options = { { value = "b", label = name } },
})
Button({ label = Flux.computed(function()
	return "Computed"
end) })

local anyLabel: Reactive<string> = name
local maybeLabel: Reactive<string>? = nil
local _read: string = Flux.read(anyLabel)
local _raw: string = Flux.raw(anyLabel)
local _maybe: string? = Flux.read(maybeLabel)
local _getter: number = Flux.read(function()
	return count() + 1
end)
local _value: boolean = Flux.read(true)
local _literal: "filled" | "tonal" = Flux.read(tone)

local function doubled<A>(value: A): Node<Flux.Unwrap<A>>
	return Flux.computed(function()
		return Flux.read(value)
	end) :: any
end
local _doubled: Node<number> = doubled(count)

local _signal: Node<number> = Flux.signal(5)
local _terse: number = Flux(5)()
local _derived: Node<string> = Flux.computed(function()
	return name() .. "!"
end)
local getCount, setCount = Flux.createSignal(10)
local _fastVal: number = setCount(getCount() + 1)
local fastMemo: () -> number = Flux.createMemo(function()
	return getCount() * 2
end)
local _memoVal: number = fastMemo()
Flux.createEffect(function()
	local _ = fastMemo()
end)
local nodeGetter: () -> number = Flux.getter(count)
local nodeSetter: (value: number, force: boolean?) -> number = Flux.setter(count)
local _nodeGetSet: number = nodeSetter(nodeGetter())

local frame = Flux.new("Frame")({})
local _shown: Node<Frame?> = Flux.show(count, function()
	return Flux.new("Frame")({})
end)
local _either: Node<(Frame | TextLabel)?> = Flux.show(count, function()
	return Flux.new("Frame")({})
end, function()
	return Flux.new("TextLabel")({})
end)
local _presence: Node<Frame?> = Flux.presence(count, function(_visible: Node<boolean>, done: () -> ())
	done()
	return Flux.new("Frame")({})
end)
local _picked: Node<number | string> = Flux.pick(count, 1, name)
local _fallback: Node<string> = Flux.fallback(maybeLabel, "Untitled")
local _mapped: Node<{ string }> = Flux.forValue(function()
	return { "a", "b" }
end, function(_index, value: string)
	return string.upper(value)
end)
local _indexed: Node<{ number }> = Flux.forIndex(Flux.signal({ 1, 2 }), function(_index, item: Node<number>)
	return item() * 2
end)
local spring = Flux.spring(count, 4)
local _spring: number = spring()
spring:impulse(2)
local _tween: Node<number> = Flux.tween(function()
	return count() * 10
end)

local theme = Flux.context("dark")
local _theme: string = theme:get()
local _provided: number = theme:provide("light", function()
	return 1
end)
local profile = Flux.async(count, function(id: number, previous: string?): string
	return previous or tostring(id)
end)
local _data: string? = profile.data()
local once = Flux.async(function(): number
	return 1
end)
local _once: number? = once.data()
local selected = Flux.selector(name)
local _isSelected: boolean = selected("Save")

local model = Flux.model(name)
local _modelNode: Node<any>? = Flux.modelNode(model)
local _isModel: boolean = Flux.isModel(model)
type SplitProps = { label: string, hint: string?, Name: string }
local splitProps: SplitProps = { label = "Save", Name = "Button" }
local OWN: { "label" | "hint" } = { "label", "hint" }
local own, rest = Flux.split(splitProps, OWN)
local _own: string = own.label
local _hint: string? = own.hint
local _rest: string = rest.Name
local loose = Flux.split(splitProps, { "label" })
local _loose: string? = loose.label

local state: Flux.State<string> = Flux.signal("idle")
state:set("busy")
local _asNode: Node<string?> = state
Flux.dispose({ name, frame, function() end })

state:onObserved(function() end)
local hooked: Node<number> = Flux.computed(function(): number
	return 2
end)
hooked:onObserved(function() end)
hooked:onUnobserved(function() end)
assert(hooked:peek() == 2)

local a, b = Flux.withOwner(nil, function(): (number, string)
	return 1, "two"
end)
local _a: number = a
local _b: string = b

return nil
