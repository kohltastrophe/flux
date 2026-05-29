---
title: Computeds
description: Caching and lazily evaluating derived state in Flux.
outline: deep
---

# Computeds

While you can derive state with plain functions, recalculating expensive operations on every read can create performance bottlenecks. **Computeds** solve this by caching (memoizing) their results and only recomputing when their dependencies actually change.

A Computed is a reactive node that automatically tracks its dependencies. It is **lazily evaluated**; it won't execute its logic until it is actually read, and it returns a cached result as long as its dependencies remain clean.

If you are coming from other reactive frameworks, you can think of Computeds as _memos_ or _cached selectors_.

## Creating a Computed

You create an implicit Computed by calling the main `Flux` function, and passing a pure function that returns the derived value, or explicitly by using `Flux.computed`{lua}.

```luau
local Flux = require(ReplicatedStorage.Flux)

local count = Flux(5)

-- Create a computed value implicitly
local doubledCount = Flux(function()
    return count * 2  -- operator overloading reads count reactively
end)
```

Like [Values](/guide/concepts/values), Computeds overload Luau's arithmetic and comparison operators, so you can use them naturally in expressions.

## Lazy Evaluation & Caching

The defining feature of a Computed is its efficiency. It avoids unnecessary work through three mechanisms:

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

Because `Flux.new`{lua} and `Flux.edit`{lua} accept standard functions for property bindings, a common misconception is that using an inline function avoids the overhead of creating a reactive graph node.

In reality, any standard function passed directly to a property binding is automatically wrapped in an **implicit Computed** by the framework.

```luau
-- These two approaches have the EXACT same execution and memory overhead:

-- 1. Implicit Computed
local label = new "TextLabel" {
    Text = function() return "Count: " .. count end
}

-- 2. Explicit Computed
local textNode = Flux(function() return "Count: " .. count end)
local label = new "TextLabel" {
    Text = textNode
}
```

Because inline functions carry the exact same overhead as explicit Computeds, you should structure your code based on **reusability**:

- **Use inline functions (Implicit Computeds):** When a derived value is unique and only ever consumed by a **single** property on a single UI element.
- **Use explicit Computeds (`Flux(function()`{luau})**: When the exact same derived result is needed by **multiple** properties or UI elements simultaneously. By passing the same explicit Computed reference around, you avoid duplicating the implicit computed overhead, ensuring the graph evaluates the logic only once.
