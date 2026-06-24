---
title: Optimization
description: Best practices for maximizing performance and memory efficiency in Flux.
outline: deep
---

# Optimization

Flux is fast by default. Because it uses fine-grained, direct reactive bindings instead of a Virtual DOM, it avoids the diffing overhead those libraries carry.

How you structure your state and components affects how well the library performs. This guide covers the mental models and practical tips for getting the most out of Flux in the Roblox engine.

## 1. Granular State vs. Monolithic State

Split flat, distinct state into granular Signals so each binding wakes only for the value it reads. When the schema is genuinely nested, reach for a [Store](/guide/concepts/stores) instead: it tracks each leaf separately and re-runs only the bindings that read the key you changed. See [Store vs. Signal](/guide/concepts/stores#store-vs-signal) for the full comparison.

## 2. Smart List Rendering

Recreating Roblox [`Instances`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance) is one of the most expensive operations in the engine. Mapping over a dynamic array with a plain `for` loop inside a binding rebuilds the entire list whenever one item changes: a 50-element list can drop frames over a single insertion.

Use [`Flux.forValue` or `Flux.forIndex`](/guide/concepts/mapping) instead: they cache generated instances and apply only the exact diff. See [Mapping](/guide/concepts/mapping) for which to reach for.

The same caching-over-rebuilding instinct applies to conditionals. Plain [`Flux.show`](/guide/concepts/conditionals#showing-one-of-two-branches) keeps its mounted subtree alive across truthy → truthy changes and lets the bindings inside it update, whereas [`Flux.showKeyed`](/guide/concepts/conditionals#keyed-show) tears the subtree down and rebuilds it on every change of value identity. Reach for `showKeyed`{luau} only when a branch genuinely needs to reset per-value state on each change; default to `show`{luau}, since recreating the instances is the expensive part.

For per-item **selection** in a long list (highlighting the focused row, say), having every row read one shared `selected` Signal makes all of them re-evaluate on each change. [`Flux.selector`](/guide/concepts/selectors) makes that O(1): only the row losing selection and the row gaining it update, however long the list.

## 3. Managing Explicit and Implicit Computeds

Any standard function passed to a property binding in `Flux.new`{lua} or `Flux.edit`{lua} is wrapped in an **implicit Computed**, carrying the exact same overhead as an explicit `Flux(function() ... end)`{luau} (see [Implicit vs. Explicit Computeds](/guide/concepts/computeds#implicit-vs-explicit-computeds)). (One exception: a function on an event-named property like `Activated` becomes a `:Connect` handler, not a Computed.)

The performance lever is **reuse**. An inline function is fine when its result feeds a single property; when the _same_ derived result feeds several, share one explicit Computed rather than duplicating the implicit one, so the logic evaluates once instead of once per binding:

```luau
local health = Flux(50)

-- One Computed, shared: evaluates once no matter how many bindings read it
local healthColor = Flux(function()
    return health() < 20 and Color3.new(1, 0, 0) or Color3.new(1, 1, 1)
end)

local healthBar   = new "Frame"     { BackgroundColor3 = healthColor }
local healthLabel = new "TextLabel" { TextColor3 = healthColor }
```

## 4. Preventing Memory Leaks (Zombie Nodes)

A Signal stays alive as long as something reads it. If a transient component builds its own internal `Flux` nodes and you `Destroy()`{luau} the Roblox instance without freeing those nodes, they become **zombies**, evaluating in the background indefinitely.

Build transient state and UI inside a [Scope](/guide/concepts/scopes) and tie that scope to the instance's lifetime with [`__CLEAN`](/guide/roblox/hydration), so destroying the Frame frees every node with it. See [Connecting a Scope to an Instance Lifetime](/guide/concepts/scopes#connecting-a-scope-to-an-instance-lifetime) for the pattern.

## 5. Engine-Specific Optimizations

Flux was built for Roblox with optimizations tailored to the engine's quirks.

### Implicit LayoutOrder

When building UI lists with `Flux.new`{lua} or `Flux.edit`{lua}, assigning [`LayoutOrder`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject#LayoutOrder) manually to dozens of children is tedious. If you place [`GuiObjects`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject) in the array portion of a constructor, Flux assigns them sequentially based on their array index in a single pass.

The rule is precise: Flux only fills in a child's `LayoutOrder` when it is still `0` (the default). If you set an explicit `LayoutOrder` yourself, Flux leaves it untouched, so you can mix auto-ordered children and a few hand-positioned ones in the same list.

### Effect Batching

Effects defer to `RunService.Heartbeat`{lua} and coalesce: mutate a Signal hundreds of times in one frame (inside a physics loop or a heavy algorithm) and the Effect still runs **once**, with the final value. Lean on this rather than reacting synchronously. See [Effects](/guide/concepts/effects#heartbeat-deferral-and-flushing) for the deferral model and the manual `Flux.flush`{lua} escape hatch.

### Graph Short-Circuiting

The graph's `CHECK` state means downstream computations only evaluate after verifying their actual upstream sources have changed. In deep dependency chains, this can skip large subtrees entirely when only a single leaf node updates. You get this performance gain for free by composing your state with Computeds rather than re-computing logic inside standalone Effects.

### Equality Short-Circuiting

By default a node propagates whenever the new value is `~=` the old one. Roblox datatypes (`Vector3`, `Color3`, `UDim2`, …) compare by **value**, so a node that rebuilds one with identical components already short-circuits on its own. A **table** compares by reference, though: a fresh table rebuilt each frame is never `==` to the last, so the node re-fires even when its contents are logically unchanged. Pass an [`equals` comparator](/guide/concepts/signals#custom-equality) to `Flux.signal`/`Flux.computed` to halt propagation when two values should count as equal. It's the most direct lever you have over how often the graph wakes up: reach for it whenever a node produces structurally-equal tables that aren't reference-equal.
