---
title: Wrap
description: Recursively converting standard tables into individual reactive nodes in Flux.
outline: deep
---

# Wrap

When building complex UI components or interacting with external data sources, you often receive static tables of data, such as default configurations, theme settings, or initial properties. **Wrap** is a utility function that recursively iterates over a standard Luau table and converts all primitive values into individual, reactive **Values** (Nodes).

If an item in the table is already a reactive Node, `Flux.wrap`{lua} safely ignores it. If it encounters a nested table, it will recursively traverse and wrap its contents.

## Basic Usage

You can use `Flux.wrap`{lua} to instantly convert a static dictionary into a reactive one. Keep in mind that `Flux.wrap`{lua} mutates the table you pass into it, physically replacing the original primitive values with `Graph.Node`{lua} instances.

```luau

local playerStats = {
    health = 100,
    mana = 50,
    isAlive = true
}

-- Convert all primitive properties into reactive Values
Flux.wrap(playerStats)

-- Now, playerStats properties must be read and written like standard Flux Values
print(playerStats.health()) -- > 100

-- Update the wrapped node
playerStats.health(90)
```

## Scoped Wrapping

Because `Flux.wrap`{lua} iterates through a table and creates potentially dozens of new reactive Nodes, managing their lifecycles manually can be tedious. To prevent memory leaks, you should almost always track wrapped tables using a **Scope**.

You can either pass a Scope object as the second argument to `Flux.wrap`{lua}, or simply use the built-in `Scope:wrap()`{luau} method. When provided, every newly created Node is automatically inserted into the scope's cleanup list.

```luau
local myScope = Flux.scope()

local theme = {
    primaryColor = Color3.fromRGB(255, 0, 0),
    cornerRadius = UDim.new(0, 8),
    fonts = {
        header = Font.fromName("GothamSSm")
    }
}

-- Wrap the table and automatically track all new nodes in 'myScope'
myScope:wrap(theme)

-- theme.primaryColor, theme.cornerRadius, and theme.fonts.header are now Nodes.

-- Later, when the UI is unmounted or the system shuts down:
myScope:Destroy()
-- All generated Nodes inside the 'theme' table are safely destroyed.
```

## Wrap vs. Store

Because both `Flux.wrap`{lua} and `Flux.store`{lua} deal with adding reactivity to tables, it is important to understand their fundamental architectural differences:

Here is the transposed table with the rows and columns flipped:

|                       | **Mechanism**                                                          | **Syntax**                                                        | **Best For**                                                                                 |
| --------------------- | ---------------------------------------------------------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **`Flux.wrap`{lua}**  | Physically replaces primitive values with `Graph.Node`{lua} instances. | Requires calling the node to read/write: `state.health(90)`{luau} | Component property destructuring, converting static configurations into standalone bindings. |
| **`Flux.store`{lua}** | Wraps the entire table in an invisible Proxy (metatable).              | Uses standard Luau syntax: `state.health = 90`{lua}               | Managing central application state, deeply nested dynamic data, and arrays.                  |

Use **Flux.wrap** when you are building a reusable UI component that explicitly expects its properties to be Flux Nodes, and you want to ensure any static primitives passed by the developer are converted into the correct reactive format.
