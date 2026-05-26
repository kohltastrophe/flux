---
title: Optimization
description: Best practices for maximizing performance and memory efficiency in Flux.
outline: deep
---

# Optimization

Flux is exceptionally fast by default. Because it uses fine-grained, direct reactive bindings instead of a Virtual DOM, it avoids the diffing overhead that burdens traditional declarative frameworks.

How you structure your state and components directly impacts how well the framework performs. This guide covers the core mental models and practical tips for squeezing the most out of Flux in the Roblox engine.

## 1. Granular State vs. Monolithic State

The most common mistake when adopting a reactive framework is treating state like a monolithic Redux store.

Putting a large, deeply nested table inside a standard `Flux` Value means any change to the table replaces the entire value. This triggers **every single observer** that reads from it, even observers that only care about a property that didn't change.

**Avoid:**

```luau
-- Monolithic primitive state
local gameState = Flux({
    score = 0,
    timeRemaining = 60,
    players = 5,
})

-- Changing the score re-evaluates the timeRemaining UI!
gameState({ score = 10, timeRemaining = 60, players = 5 })

```

**Do this instead:** Break your state into granular, independent Values, or use a **Store** for deep reactivity.

```luau
-- Granular Values (best for flat, distinct state)
local score         = Flux(0)
local timeRemaining = Flux(60)

-- OR deeply reactive Stores (best for complex schemas)
local gameState = Flux.store({
    score = 0,
    timeRemaining = 60,
    players = 5,
})

-- Now this only triggers UI bindings that specifically read `score`
gameState.score = 10

```

## 2. Smart List Rendering

Never map over dynamic arrays using plain `for` loops inside a reactive binding or a Computed. Re-creating Roblox [`Instances`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance) is one of the most expensive operations in the engine. Recreating a list of 50 elements just because one item was added will cause visible frame drops.

Always use **`Flux.forValue`{lua}** or **`Flux.forIndex`{lua}**. These utilities cache the generated instances and perform only the exact insertions or updates necessary.

```luau
-- BAD: destroys and recreates all instances every time 'inventory' changes
Children = Flux(function()
    local instances = {}
    for _, item in inventory() do
        table.insert(instances, new "TextLabel" { Text = item.name })
    end
    return instances
end)

-- GOOD: caches instances, only rendering the exact diff
Flux.forValue(inventory, function(indexNode, item)
    return new "TextLabel" { Text = item.name }
end)

```

## 3. Managing Explicit and Implicit Computeds

A Computed lazily evaluates and memoizes its result. This is powerful for derivations, but establishing the cache and tracking dependencies has a baseline memory and execution cost.

A common misconception is that passing a standard function directly to a UI binding avoids this graph overhead. In reality, any standard function passed to a property in `Flux.new`{lua} or `Flux.edit`{lua} is automatically wrapped in an **implicit Computed**.

Because of this, inline functions carry the exact same overhead as explicitly calling `Flux(function() ... end)`{luau}.

**Optimization Rule:** If a derived value is only needed by a single property, an inline function (implicit computed) is perfectly fine. However, if the _same_ derived result is consumed by multiple properties or components simultaneously, **do not duplicate inline functions**. Create a single explicit Computed and share its reference to reduce the number of graph nodes.

```luau
local health = Flux(50)

-- BAD: Creates TWO separate implicit Computeds evaluating the exact same logic
local healthBar = new "Frame" {
    BackgroundColor3 = function()
        return health() < 20 and Color3.new(1, 0, 0) or Color3.new(1, 1, 1)
    end,
}
local healthLabel = new "TextLabel" {
    TextColor3 = function()
        return health() < 20 and Color3.new(1, 0, 0) or Color3.new(1, 1, 1)
    end,
}

-- GOOD: Share a single explicit Computed to halve the graph node overhead
local healthColor = Flux(function()
    return health() < 20 and Color3.new(1, 0, 0) or Color3.new(1, 1, 1)
end)

local healthBar = new "Frame" { BackgroundColor3 = healthColor }
local healthLabel = new "TextLabel" { TextColor3 = healthColor }

```

## 4. Preventing Memory Leaks (Zombie Nodes)

Reactivity is driven by subscriptions. If a Value exists and an Effect or UI binding is listening to it, both are kept alive in memory.

If you create a temporary UI component that builds its own internal `Flux` nodes, and you `Destroy()`{luau} the Roblox instance without destroying those nodes, they become **zombies**; they continue evaluating in the background indefinitely.

**Always use Scopes for transient state.**

```luau
local function Notification(props)
    local uiScope = Flux.scope()

    -- This Value is tracked by the scope
    local opacity = uiScope(1)

    return new "Frame" {
        BackgroundTransparency = function() return 1 - opacity end,

        -- Automatically destroy the scope (and all its nodes) when the Frame is destroyed
        __CLEAN = {
            uiScope,
        },
    }
end

```

## 5. Engine-Specific Optimizations

Flux was built specifically for Roblox with optimizations tailored to the engine's quirks.

### Implicit LayoutOrder

When building UI lists with `Flux.new`{lua} or `Flux.edit`{lua}, assigning [`LayoutOrder`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject#LayoutOrder) manually to dozens of children is tedious. If you place [`GuiObjects`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject) in the array portion of a constructor and leave their [`LayoutOrder`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject#LayoutOrder) unchanged, Flux assigns them sequentially based on their array index in a single pass.

### Effect Batching

`Flux(effectFn, true)`{luau} effects defer execution to `RunService.Heartbeat`{lua}. If you mutate a Value hundreds of times in a single frame (e.g., inside a physics loop or a complex algorithm), the Effect only runs **once** at the end of the frame with the final value.

If you need truly synchronous, immediate reaction to a change (unusual), call `Flux.Graph.flush()`{lua} manually, but prefer the deferred path whenever possible.

### Graph Short-Circuiting

The graph's `CHECK` state means downstream computations only evaluate after verifying their actual upstream sources have changed. In deep dependency chains, this can skip large subtrees entirely when only a single leaf node updates. You get this performance gain for free simply by composing your state with Computeds rather than re-computing logic inside standalone Effects.
