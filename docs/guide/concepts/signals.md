---
title: Signals
description: Understanding primitive reactive state in Flux.
outline: deep
---

# Signals

Signals are the basic unit of reactive state in Flux: a node that holds a piece of data and notifies the graph whenever that data changes.

## Creating a Signal

Call the main `Flux` function, with an initial value. Any non-function argument implicitly creates a signal.

> [!NOTE]
> You can also use `Flux.signal`{luau} to explicitly create a signal.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

-- Create signals implicitly
local count     = Flux(0)
local name      = Flux("Roblox")
local isVisible = Flux(true)

-- Or create signals explicitly
local count     = Flux.signal(0)
local name      = Flux.signal("Roblox")
local isVisible = Flux.signal(true)
```

## Reading a Signal

Call the node with no arguments to read its current value. This call form, `count()`{luau}, is the idiomatic default; it is shorthand for the explicit `count:get()`{luau}. Reading a node inside a reactive context (a Computed or Effect body, or a function passed to a property binding) automatically registers it as a dependency.

```luau
local count = Flux(5)

print(count())     --> 5
print(count:get()) --> 5 (the explicit equivalent)
```

## Operator Overloading

Signals overload Luau's arithmetic and concatenation operators, so you can use them transparently in expressions; no need to call `()` at every use site.

```luau
local count = Flux(5)

print(count * 2)   --> 10
print(count + 10)  --> 15
print(-count)      --> -5
print(count .. "x") --> "5x"

print(count > 3)   --> attempt to compare number < table [!code error]
print(count == 5)  --> false (not true! == is identity, not value) [!code warning]
```

These overloads call `:get()`{luau} under the hood, so they also register the node as a reactive dependency when evaluated inside a computation.

> [!NOTE]
> Comparison has two gotchas. **Relational** operators (`<`, `<=`, `>`, `>=`) only work between two nodes: comparing a node against a primitive value _(like a number)_ throws, due to a Luau restriction on the `__lt`/`__le` metamethods. **Equality** (`==`/`~=`) is not overloaded at all, so `node == value`{luau} tests table identity and is silently always `false`{luau}. In both cases, read the value first: `count() > 3`{luau} or `count() == 5`{luau}.

## Updating a Signal

Call the node with a new value to set it: `count(10)`{luau} is the idiomatic shorthand for the explicit `count:set(10)`{luau}. Either form immediately updates the stored state and notifies any downstream nodes.

```luau
local count = Flux(0)

count(10)         -- set to 10
count:set(5)      -- the explicit equivalent, set to 5
count(count + 1)  -- arithmetic reads the current value, then sets the result
```

In `count + 1`{luau}, the `+` operator reads the node's current value automatically (see [Operator Overloading](#operator-overloading) below), so you do not have to call `count()`{luau} first.

> [!NOTE]
> Calling a node with `nil`{luau} is a **read**, not a write; `node(nil)`{luau} is indistinguishable from `node()`{luau}. To set a signal to `nil`{luau}, use `node:set(nil)`{luau}, or force the call shorthand with `node(nil, true)`{luau} (see [Forcing an Update](#forcing-an-update) below).

### Forcing an Update

Setting a signal to something equal to its current value skips propagation. Pass `true`{luau} as the second argument of `:set()`{luau} to notify dependents anyway. This is useful when you mutate a table in place and need to push the same reference through the graph:

```luau
local items = Flux({ "Sword" })

local list = items()
table.insert(list, "Shield")
items:set(list, true) -- same table reference; force dependents to update
```

When there is no new value to write, `:update()`{luau} is the terser equivalent: it re-fires dependents with the value the node already holds, and returns the node so a read or write can be chained.

```luau
table.insert(items:peek(), "Axe")
items:update() -- nothing written; dependents re-run with the same table
```

## Custom Equality

By default, a node only propagates when the new value is `~=` the old one. The explicit constructors `Flux.signal`{luau} and `Flux.computed`{luau} accept an optional `equals` function as their final argument; when it returns `true`{luau}, the values are considered equal and dependents are not notified:

```luau
-- Only propagate when the position moves beyond a fuzzy epsilon
local position = Flux.signal(Vector3.zero, function(a, b)
    return a:FuzzyEq(b, 1e-3)
end)
```

## Binding to the UI

You can pass a signal (or any reactive node) **directly** to a property in `Flux.new`{luau} or `Flux.edit`{luau}. Flux detects the node and binds to it, and the property updates automatically whenever the node changes.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

local count = Flux(0)

local button = new "TextButton" {
    Size = UDim2.fromOffset(200, 50),

    -- Direct node binding: the Text property mirrors count automatically
    Text = count,

    Activated = function()
        count(count + 1)
    end,
}
```

For derived values you only need in one place, you can also pass an **inline function**. Flux wraps it in an implicit [Computed](/guide/concepts/computeds) for this binding:

```luau
local button = new "TextButton" {
    -- Inline function: Flux creates an implicit Computed for this binding
    Text = function()
        -- `.. count` reads the node's current value automatically
        return "Count: " .. count
    end,
}
```

### Under the Hood

When Flux sees a reactive node or a function assigned to a property, it establishes a reactive binding. During the first evaluation, Flux tracks which nodes were accessed and maps the property as a dependent of those nodes.

Whenever `count(newValue)`{luau} is called, Flux propagates the change through the graph, ensuring your UI stays in sync without any manual `.Changed` or `GetPropertyChangedSignal` connections.

### When a Write Fails

If the engine rejects a bound write (a `nil`{luau} written to a string property, a value of the wrong type, a locked property), Flux re-runs that node's writes checked: every failure is collected into one error naming the **full instance path, the property or attribute name, and the rejected value** (with its type), and the node's remaining property, attribute, and children bindings still receive the update instead of being starved by the failure.

```luau
local text = Flux("hello")
local label = new "TextLabel" { Text = text }

text:set(nil, true)
-- failed to write nil (nil) to:
--     Players.you.PlayerGui.ScreenGui.TextLabel.Text: Unable to assign property Text. string expected, got nil
```

The checked re-run only happens after a write has already failed, so the happy path stays raw and free. Since binding writes run in an [effect](/guide/concepts/effects), the error surfaces through the flush as a `suppressed effect error` warning; the update that *caused* the bad value is best tracked down in development with [strict mode](/guide/tips/strict) on.

## Binding from an Instance Property

The reverse direction also works: passing an Instance to the `Flux` constructor creates a signal that **mirrors** one of its properties, updating whenever the property changes. Prefix the name with `$` to mirror an attribute instead:

```luau
-- A node that always holds the TextBox's current text
local text = Flux(textBox, "Text")

-- A node that mirrors the character's 'Health' attribute
local health = Flux(character, "$Health")

Flux(function()
    print("User typed: " .. text)
end, true) -- the `true` makes this an Effect (see [Effects](/guide/concepts/effects))
```

The mirror connection is disconnected automatically when the node is destroyed.

## Destroying a Signal

Call `:Destroy()`{luau} to sever a node from the graph; all upstream and downstream links are removed. Use `:onDestroy(fn)`{luau} to register teardown logic that runs at that moment:

```luau
local count = Flux(0)

count:onDestroy(function()
    print("count destroyed")
end)

count:Destroy()
```

Destroying strips the node's stored value, so a later read returns `nil`{luau}, and unsubscribes it from the graph. The node object itself is simply left for Luau's garbage collector to reclaim once you drop your references, so `Flux.isNode`{luau} still reports `true`{luau} for a destroyed node. A signal is **not owned by any [scope](/guide/concepts/scopes)**, so `:onDestroy(fn)`{luau} runs **only** on an explicit `:Destroy()`{luau}; a signal you merely stop referencing is collected silently, without firing `onDestroy`. (A computed or effect, which a scope _does_ own, fires `onDestroy` on that scope's teardown as well.)

In practice you rarely call `:Destroy()`{luau} on a signal by hand; an unreferenced signal is collected on its own, and a [Scope](/guide/concepts/scopes) tears down the reactions and resources it owns in a single call.
