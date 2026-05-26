---
title: Values
description: Understanding primitive reactive state in Flux.
outline: deep
---

# Values

Values are the cornerstone of reactivity in Flux. They are the most basic unit of reactive state, a node that holds a piece of data and notifies the graph whenever that data changes.

If you are coming from other reactive frameworks, you can think of Values as _signals_ or _atoms_.

## Creating a Value

Call the main `Flux` function with an initial value. Any non-function argument creates a Value node.

```luau
local Flux = require(ReplicatedStorage.Flux)

local count     = Flux(0)
local name      = Flux("Roblox")
local isVisible = Flux(true)
```

## Reading a Value

Call the node with no arguments to read its current value. Reading a node inside a reactive context (a Computed or Effect body, or a function passed to a property binding) automatically registers it as a dependency.

```luau
local count = Flux(5)

print(count:get()) --> 5
print(count())   --> 5 (shorthand for :get())
```

## Operator Overloading

Values overload the full set of Luau arithmetic and comparison operators, so you can use them transparently in expressions; no need to call `()` at every use site.

```luau
local count = Flux(5)

print(count * 2)   --> 10
print(count + 10)  --> 15
print(count > 3)   --> true
print(-count)      --> -5
print(count .. "x") --> "5x"
```

These overloads call `:get()`{luau} under the hood, so they also register the node as a reactive dependency when evaluated inside a computation.

## Updating a Value

Call the node with a new value to set it. This immediately updates the stored state and notifies any downstream observers.

```luau
local count = Flux(0)

count:set(5)      -- set to 5
count(10)         -- set to 10 (shorthand for :set())
count(count + 1)  -- arithmetic reads the current value via __add, then sets the result
```

## Binding to the UI

You can pass a Value (or any reactive node) **directly** to a property in `Flux.new`{lua} or `Flux.edit`{lua}. Flux detects the node and binds to it, and the property updates automatically whenever the node changes.

```luau
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

For derived values you only need in one place, you can also pass an **inline function**. Flux wraps it in an implicit computation:

```luau
local button = new "TextButton" {
    -- Inline function: Flux creates an implicit memo for this binding
    Text = function()
        return "Count: " .. count
    end,
}
```

### Under the Hood

When Flux sees a reactive node or a function assigned to a property, it establishes a reactive subscription. During the first evaluation, Flux observes which nodes were accessed and maps the property as a dependent of those nodes.

Whenever `count(newValue)`{luau} is called, Flux propagates the change through the graph, ensuring your UI stays in sync without any manual `.Changed` or `GetPropertyChangedSignal` connections.
