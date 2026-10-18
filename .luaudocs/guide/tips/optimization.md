---
title: Optimization
description: Best practices for maximizing performance and memory efficiency in Flux.
outline: deep
sidebar_position: 1
---

# Optimization

Flux's fine-grained reactive core skips Virtual DOM diffing and updates only the exact properties and computations affected by a change. These patterns help you get the most out of the graph in performance-critical UI and game systems.

## 1. Granular State & Stores

Split distinct values into individual [Signals](/guide/concepts/signals) so each binding wakes only for the value it reads. For nested tables or player data schemas, use a [Store](/guide/concepts/stores): each nested key has its own lazy leaf Signal, and [`Flux.Store.reconcile`](/guide/concepts/stores#reconciling-snapshots) diffs incoming server snapshots so unchanged fields never trigger downstream work.

## 2. Smart List & Conditional Rendering

Creating and destroying Roblox [`Instances`](https://create.roblox.com/docs/en-us/reference/engine/classes/Instance) is one of the most expensive operations in the engine:

- **Lists:** Always render dynamic arrays with [`Flux.forValue` or `Flux.forIndex`](/guide/concepts/mapping) instead of rebuilding children in a plain loop. `forValue`{luau} caches instances by item identity and repositions them in place; `forIndex`{luau} caches slots by index and updates a reactive `value`{luau} Signal per slot.
- **Conditionals:** Prefer [`Flux.show`](/guide/concepts/conditionals#showing-one-of-two-branches) over [`Flux.showKeyed`](/guide/concepts/conditionals#keyed-show) unless you specifically need to tear down and recreate the subtree when a truthy value changes identity.
- **Selection:** Use [`Flux.selector`](/guide/concepts/selectors) for active-row highlighting in large lists so changing selection is $O(1)$ (waking only the old and new rows) instead of $O(N)$.

## 3. Sharing Explicit Computeds

Every inline function passed to a property in `Flux.new`{luau} or `Flux.edit`{luau} creates an implicit [Computed](/guide/concepts/computeds). When multiple properties derive from the same calculation, hoist it into a single shared `Flux.computed`{luau} so the math runs once:

```luau
local health = Flux.signal(50)

-- Shared across both bindings: evaluates once per change
local healthColor = Flux.computed(function()
    return if health() < 20 then Color3.new(1, 0, 0) else Color3.new(1, 1, 1)
end)

local healthBar   = Flux.new "Frame"     { BackgroundColor3 = healthColor }
local healthLabel = Flux.new "TextLabel" { TextColor3 = healthColor }
```

## 4. Zero-Wrapper Fast Paths {#zero-wrapper-primitives}

In hot loops or high-frequency reactive graphs where you want to avoid metatable call dispatch and table wrapper allocations, Flux exposes SolidJS-style function tuple primitives:

| Fast-Path API                                   | Equivalent Object API                                                               |
| :---------------------------------------------- | :---------------------------------------------------------------------------------- |
| `local get, set = Flux.createSignal(v, eq?)`{luau} | `local s = Flux.signal(v, eq?)`{luau}                                            |
| `local get = Flux.createMemo(fn, eq?)`{luau}       | `local c = Flux.computed(fn, eq?)`{luau}                                         |
| `Flux.createEffect(fn)`{luau}                      | `Flux.effect(fn)`{luau} (registered to the active [Scope](/guide/concepts/scopes)) |
| `local get = Flux.getter(node)`{luau}              | Extracts a direct `() -> T`{luau} closure from an existing Signal or Computed       |
| `local set = Flux.setter(node)`{luau}              | Extracts a direct `(T) -> ()`{luau} closure from an existing Signal                 |

```luau
local getCount, setCount = Flux.createSignal(0)
local getDoubled = Flux.createMemo(function()
    return getCount() * 2
end)

Flux.createEffect(function()
    print("Doubled:", getDoubled())
end)

setCount(10)
```

> [!NOTE]
> `createSignal`{luau} and `createMemo`{luau} closures are valid `Flux.Reactive<T>`{luau} sources; you can pass `getCount`{luau} or `getDoubled`{luau} directly to property bindings, `Flux.spring`{luau}, or `Flux.show`{luau}.

## 5. How the Reactive Graph Minimizes Work

### Height-Ordered Stabilization & Early Cutoff

When a [Computed](/guide/concepts/computeds) has active downstream observers (such as an Effect or UI binding), Flux maintains its topological height in the dependency graph:

1. **Glitch-free ordering:** Upstream Computeds always settle before deeper Computeds or Effects that read them, so diamond dependency graphs never evaluate a node twice or expose transient half-updated values.
2. **Early cutoff:** If an upstream Computed re-evaluates and produces an equal value (`==`{luau} or custom `equals`{luau}), propagation stops immediately; downstream Computeds and Effects are never woken.
3. **Zero cost when unobserved:** A Computed with no downstream observers unsubscribes from its sources and stays completely dormant until read.

### Custom Equality Short-Circuiting {#equality-short-circuiting}

Roblox value types (`Vector3`{luau}, `Color3`{luau}, `UDim2`{luau}) compare by value automatically, but tables compare by reference. When a Signal or Computed produces a fresh table each time, pass a custom `equals`{luau} comparator to halt propagation when the contents are unchanged:

```luau
local pos = Flux.computed(function()
    return { x = math.floor(rawX()), y = math.floor(rawY()) }
end, function(a, b)
    return a.x == b.x and a.y == b.y
end)
```

### Effect Batching {#effect-batching}

Effects and property bindings batch their updates to the end of the frame, flushing on `RunService.PreRender`{luau} on the client (right before rendering) and `RunService.Heartbeat`{luau} on the server. Updating a Signal hundreds of times in a single frame still runs each dependent Effect at most **once** with the final settled value.

### Implicit LayoutOrder

When you pass child `GuiObject`{luau}s in the array part of `Flux.new`{luau} or `Flux.edit`{luau}, Flux automatically sets `LayoutOrder`{luau} to the child's array index whenever its `LayoutOrder`{luau} is still `0`{luau}.
