---
title: Computeds
description: Caching and lazily evaluating derived state in Flux.
outline: deep
---

# Computeds

While you can derive state with plain functions, recalculating expensive operations on every read is slow. **Computeds** solve this by caching (memoizing) their results and only recomputing when their dependencies actually change.

A Computed is a reactive node that automatically tracks its dependencies. It is **lazily evaluated**; it won't execute its logic until it is actually read, and it returns a cached result as long as its dependencies remain clean.

## Creating a Computed

You create an implicit Computed by calling the main `Flux` function, and passing a pure function that returns the derived value, or explicitly by using `Flux.computed`{luau}.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

local count = Flux(5)

-- Create a computed value implicitly
local doubledCount = Flux(function()
    return count * 2 -- the operator reads count's current value automatically
end)
```

Writing `count * 2`{luau} works because Computeds, like [Signals](/guide/concepts/signals#operator-overloading), overload Luau's arithmetic and concatenation operators; each reads the node's current value for you, so `count * 2`{luau} and `"Count: " .. count`{luau} work without a call. Comparison operators are the exception: they only work between two nodes, so to compare against a plain value, read it first: `count() < 5`{luau}.

`Flux.computed`{luau} also accepts an optional `equals` function as its second argument; when the recomputed result is considered equal to the previous one, downstream nodes are not notified. See [Custom Equality](/guide/concepts/signals#custom-equality).

## Lazy Evaluation & Caching

A Computed avoids unnecessary work through three mechanisms:

1. **Lazy Execution** - The function does not run immediately. It only runs the first time the Computed is read.
2. **Memoization** - Once evaluated, the result is cached. Subsequent reads return the cached value instantly without re-running the function.
3. **Smart Invalidation** - Flux tracks the Computed's dependencies. The cache is only invalidated when a dependency actually changes; even then, the Computed won't recalculate until the next read.

```luau
local Flux = require(ReplicatedStorage.Flux)

local count = Flux(1)

local expensiveMath = Flux(function()
    print("Executing expensive calculation...")
    return count * 100
end)

-- The function hasn't run yet.

print(expensiveMath())
-- > "Executing expensive calculation..."
-- > 100

print(expensiveMath())
-- No print! Returns the cached value.
-- > 100

count(2) -- Invalidates the cache by updating the dependency

print(expensiveMath())
-- > "Executing expensive calculation..."
-- > 200
```

> [!NOTE]
> The body here is impure (it calls `print`{luau}), so under [strict mode](/guide/tips/strict) it runs twice per evaluation and you will see the line doubled. The memoization itself is unchanged: the cached read still never re-runs.

## Reading the Previous Value

A Computed (or [Effect](/guide/concepts/effects)) receives its **own previous value** as the first argument to its function. On the first run that argument is `nil`{luau}; on every subsequent run it is whatever the body returned last time. This is the same convention as SolidJS's `createMemo((prev) => …)`{ts}, and it makes accumulators and delta calculations straightforward.

```luau
local Flux = require(ReplicatedStorage.Flux)

local score = Flux(0)

-- A running maximum: fold each new score into the previous result
local highScore = Flux(function(previous)
    return math.max(previous or 0, score())
end)

score(40)
print(highScore()) -- > 40
score(15)
print(highScore()) -- > 40 (the previous high is retained)
score(90)
print(highScore()) -- > 90
```

The previous value is just an argument, so existing zero-argument bodies are unaffected: Luau ignores extra arguments. Reach for it whenever the new result depends on the old one: smoothed values, counters, "did this increase?" flags, and similar folds.

> [!NOTE]
> [Strict mode](/guide/tips/strict) double-runs a body and feeds the second run the result of the first run (not the original previous value). An **idempotent** fold like this running maximum re-runs to the same value and is unaffected; an additive accumulator (`prev + n`{luau}) advances twice while strict mode is on. See [Accumulators read their own previous value](/guide/tips/strict#accumulators-read-their-own-previous-value).

## Binding to the UI

Computeds can be passed **directly** to Roblox instance properties. Flux detects that the value is a reactive node and binds to it automatically; no wrapping function is needed.

```luau
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

local items = Flux({ "Sword", "Shield", "Potion" })

-- Only recalculate this string when 'items' actually changes
local inventoryDisplay = Flux(function()
    return "Inventory: " .. table.concat(items(), ", ")
end)

local label = new "TextLabel" {
    Name = "InventoryLabel",
    Size = UDim2.fromOffset(300, 50),

    -- Pass the Computed directly, no function wrapper required
    Text = inventoryDisplay,
}
```

Because `inventoryDisplay` is lazily evaluated, it only processes the `table.concat`{luau} when the UI actually needs it. If `items` updates multiple times in a single frame before the UI reads it, the Computed still calculates the string exactly once.

## Implicit vs. Explicit Computeds

Because `Flux.new`{luau} and `Flux.edit`{luau} accept standard functions for property bindings, a common misconception is that using an inline function avoids the overhead of creating a reactive graph node.

In reality, any standard function passed directly to a property binding is automatically wrapped in an **implicit Computed Binding** by the library.

```luau
-- These two approaches have the EXACT same execution and memory overhead:

-- 1. Implicit Computed Binding
local label = new "TextLabel" {
    Text = function() return "Count: " .. count end
}

-- 2. Explicit Computed Binding
local textNode = Flux(function() return "Count: " .. count end)
local label = new "TextLabel" {
    Text = textNode
}
```

Because inline functions carry the exact same overhead as explicit Computeds, you should structure your code based on **reusability**:

- **Use inline functions (Implicit Computeds):** When a derived value is unique and only ever consumed by a **single** property on a single UI element.
- **Use explicit Computeds (`Flux(function()`{luau})**: When the exact same derived result is needed by **multiple** properties or UI elements simultaneously. By passing the same explicit Computed reference around, you avoid duplicating the implicit computed overhead, ensuring the graph evaluates the logic only once.
