---
title: Signals
description: Understanding primitive reactive state in Flux.
outline: deep
sidebar_position: 1
---

# Signals

A **Signal** is a writable reactive node that holds a value and notifies the graph whenever that value changes.

```luau
local count = Flux.signal(0)
local name = Flux.signal("Roblox")

print(count()) --> 0
count(count() + 1)
print(count()) --> 1
```

## Creating a Signal

Use `Flux.signal(initial, equals?)` to create a strictly typed `State<T>` node whose `:set` method checks the value type. For quick untyped state (`Node<any>`), call `Flux(initial)` directly:

```luau
-- Strictly typed State<T> (recommended)
local count = Flux.signal(0)
local isVisible = Flux.signal(true)

-- Terse shorthand (returns Node<any>)
local score = Flux(0)
```

> [!TIP] Zero-Wrapper Fast Path (`Flux.createSignal`)
> In hot code where you don't need node methods or operator overloading, `local count, setCount = Flux.createSignal(0)` returns a plain `(getter, setter)` function pair with no table wrapper overhead. See [Optimization](/guide/tips/optimization#zero-wrapper-primitives).

## Reading a Signal

Call a node with no arguments (`count()`) or use `count:get()` to read its value and subscribe the running [Computed](/guide/concepts/computeds) or [Effect](/guide/concepts/effects). Use `count:peek()` (or [`Flux.raw(count)`](/guide/concepts/tracking#flux-raw)) to read without subscribing:

```luau
local count = Flux.signal(5)

print(count())      --> 5 (tracked read)
print(count:get())  --> 5 (explicit tracked read)
print(count:peek()) --> 5 (untracked read)
```

## Updating a Signal

Call a node with a new value (`count(10)`) or use `count:set(10)` to write to it. If the new value equals the current value (`==`, or a [custom `equals` comparator](#custom-equality)), propagation is skipped.

```luau
local count = Flux.signal(0)

count(10)        -- write 10
count:set(5)     -- explicit write (type-checked on State<T>)
count(count + 1) -- read via operator overloading, then write 6
```

| Operation | Call Shorthand | Explicit Method | Subscribes / Notifies? |
| :--- | :--- | :--- | :--- |
| **Tracked read** | `node()` | `node:get()` | Subscribes the running reaction |
| **Untracked read** | `Flux.raw(node)` | `node:peek()` | Does not subscribe |
| **Write value** | `node(value)` | `node:set(value)` | Notifies if `value ~= old` |
| **Write `nil`** | `node(nil, true)` | `node:set(nil)` | Notifies if old value was non-`nil` |
| **Force write** | `node(value, true)` | `node:set(value, true)` | Always notifies dependents |
| **In-place update** | - | `node:update()` | Re-fires dependents without writing |

> [!NOTE] Writing `nil`
> Calling `node(nil)` is indistinguishable from `node()` and performs a **read**. To clear a signal to `nil`, call `node:set(nil)` or pass the `force` flag: `node(nil, true)`.

### Forcing an Update

When you mutate a table in place and want to push the same reference through the graph, call `:update()` (or pass `true` as the second argument of `:set`):

```luau
local items = Flux.signal({ "Sword" })

table.insert(items:peek(), "Shield")
items:update() -- re-fires dependents with the mutated table
```

## Operator Overloading

Every node overloads Luau's arithmetic (`+`, `-`, `*`, `/`, `//`, `%`, `^`, unary `-`) and concatenation (`..`) operators, reading the node with tracking automatically:

```luau
local count = Flux(5)

print(count * 2)    --> 10
print(count + 10)   --> 15
print(-count)       --> -5
print(count .. "x") --> "5x"

print(count > 3)    --> error: attempt to compare number < table [!code error]
print(count == 5)   --> false (compares table identity, not value) [!code warning]
```

> [!WARNING] Comparisons Require Reading First
> Luau only invokes `__lt`/`__le` when **both** operands share the metamethod, and never invokes `__eq` across different types. Always read the node when comparing against a plain value: `count() > 3` or `count() == 5`.

## Custom Equality

Pass an `equals(old, new)` function as the second argument to `Flux.signal` (or `Flux.computed`) to customize when a write counts as unchanged:

```luau
-- Only propagate when the position moves beyond 1e-3 studs
local position = Flux.signal(Vector3.zero, function(a, b)
	return a:FuzzyEq(b, 1e-3)
end)
```

## Binding to the UI

Pass a node or a getter function directly to any property in [`Flux.new`](/guide/roblox/creation) or [`Flux.edit`](/guide/roblox/hydration):

```luau
local count = Flux.signal(0)

local button = Flux.new "TextButton" {
	Size = UDim2.fromOffset(200, 50),
	Text = function()
		return `Count: {count()}`
	end,
	Activated = function()
		count(count() + 1)
	end,
}
```

### When a Write Fails

If Roblox rejects a bound property or attribute assignment (such as assigning the wrong type), Flux catches the failure, logs a warning with the full instance path and property name (`[Flux] failed to set property "Text" of ...`), and still applies the node's remaining bindings so one bad property never starves sibling updates.

## Binding from an Instance Property

To mirror a Roblox [`Instance`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance) property, attribute, or [`CollectionService`](https://create.roblox.com/docs/en-us/reference/engine/classes/CollectionService) tag into a reactive node, use `Flux.property(instance, key)` for a strictly typed node, or `Flux(instance, key)` for an untyped shorthand. Prefix `key` with `$` or `_attr_` to follow an attribute (`Node<any>`), or with `#` or `_tag_` to follow a tag (`Node<boolean>`):

```luau
-- Typed Node<string> mirroring TextBox.Text
local text = Flux.property(textBox, "Text")

-- Typed Node<boolean> mirroring instance:HasTag("Enemy") ("#Enemy" or "_tag_Enemy")
local isEnemy = Flux.property(character, "#Enemy")

-- Untyped shorthand for a property, "$Attribute" / "_attr_Attribute", or "#Tag" / "_tag_Tag"
local health = Flux(character, "$Health")

Flux.effect(function()
	print(`User typed: {text()}`)
end)
```

The underlying `GetPropertyChangedSignal`, `GetAttributeChangedSignal`, or `CollectionService` tag connections are cleaned up automatically when the node or its owning [Scope](/guide/concepts/scopes) is destroyed.

## Observer Lifecycle Hooks

Use `node:onObserved(fn)` and `node:onUnobserved(fn)` to start and stop external work (connections, polling) only while at least one [Effect](/guide/concepts/effects) transitively observes the node:

```luau
local clock = Flux.signal(os.clock())
local connection: RBXScriptConnection?

clock:onObserved(function()
	connection = RunService.Heartbeat:Connect(function()
		clock(os.clock())
	end)
end)

clock:onUnobserved(function()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end)
```

## Destroying a Signal

Call `node:Destroy()` to sever a node from its sources and observers and run any registered `node:onDestroy(fn)` callbacks:

```luau
local count = Flux.signal(0)

count:onDestroy(function(lastValue)
	print("Destroyed with last value:", lastValue)
end)

count:Destroy()
```

A plain signal is **not** owned by an enclosing [Scope](/guide/concepts/scopes); once nothing references it, Luau's garbage collector reclaims it automatically. `onDestroy` on a signal fires only when you call `:Destroy()` explicitly (whereas Computeds and Effects also fire `onDestroy` when their owning Scope is destroyed).
