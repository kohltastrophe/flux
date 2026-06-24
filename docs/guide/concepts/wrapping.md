---
title: Wrapping
description: Recursively converting standard tables into individual reactive nodes in Flux.
outline: deep
---

# Wrapping

When building complex UI components or interacting with external data sources, you often receive static tables of data, such as default configurations, theme settings, or initial properties. **Wrap** is a utility function that recursively iterates over a standard Luau table and converts all primitive values into individual, reactive [Signals](/guide/concepts/signals) (nodes).

If an item in the table is already a node, `Flux.wrap`{lua} safely ignores it. If it encounters a nested table, it will recursively traverse and wrap its contents.

## Basic Usage

You can use `Flux.wrap`{lua} to instantly convert a static dictionary into a reactive one. Keep in mind that `Flux.wrap`{lua} **mutates** the table you pass into it, physically replacing the original primitive values with nodes. It also **returns that same table**, so both `Flux.wrap(t)`{luau} and `local t = Flux.wrap(t)`{luau} work; the return value is the table you passed in.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

local playerStats = {
    health = 100,
    mana = 50,
    isAlive = true
}

-- Convert all primitive properties into reactive nodes
Flux.wrap(playerStats)

-- Now, playerStats properties must be read and written like standard Flux signals
print(playerStats.health()) -- > 100

-- Update the wrapped node
playerStats.health(90)
```

Once a value is wrapped it behaves like any other node, so you can drive reactive code from it. Operators and string interpolation read a node's current value automatically (see [Signals](/guide/concepts/signals)):

```luau
Flux(function()
    print("Health is now " .. playerStats.health())
end, true) -- the `true` makes this an Effect (see [Effects](/guide/concepts/effects))

playerStats.health(75) -- the Effect reruns: "Health is now 75"
```

## Lifecycle

The values `Flux.wrap`{lua} creates are plain [signals](/guide/concepts/signals), so there is no lifecycle to manage by hand: each one lives as long as the table that holds it, and the garbage collector reclaims them once you drop that table. A [Scope](/guide/concepts/scopes) does **not** own wrapped signals: they are not torn down by `scope:Destroy()`{luau}; they simply go away with the table.

```luau
local theme = {
    primaryColor = Color3.fromRGB(255, 0, 0),
    cornerRadius = UDim.new(0, 8),
    fonts = {
        header = Font.fromName("GothamSSm")
    }
}

Flux.wrap(theme)
-- theme.primaryColor, theme.cornerRadius, and theme.fonts.header are now signals.

-- Drop every reference to `theme` and its wrapped signals are collected: nothing to destroy by hand.
```

## Wrap vs. Store

Because both `Flux.wrap`{lua} and `Flux.store`{lua} deal with adding reactivity to tables, it is important to understand their fundamental architectural differences:

|                       | **Mechanism**                                             | **Syntax**                                                        | **Best For**                                                                                 |
| --------------------- | --------------------------------------------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **`Flux.wrap`{lua}**  | Physically replaces primitive values with nodes.          | Requires calling the node to read/write: `state.health(90)`{luau} | Component property destructuring, converting static configurations into standalone bindings. |
| **`Flux.store`{lua}** | Wraps the entire table in an invisible Proxy (metatable). | Uses standard Luau syntax: `state.health = 90`{luau}              | Managing central application state, deeply nested dynamic data, and arrays.                  |

The mechanism also has a performance consequence: `Flux.wrap`{lua} is **eager** (it allocates a node for every leaf the moment you call it), whereas `Flux.store`{lua} is **lazy**, creating a per-key node only the first time that key is read inside a reactive computation. For a small, fully-consumed config or prop table that cost is negligible; for large or mostly-unread data, a Store pays only for what you actually touch.

Use **Flux.wrap** when you are building a reusable UI component that explicitly expects its properties to be Flux nodes, and you want to ensure any static primitives passed by the developer are converted into the correct reactive format.
