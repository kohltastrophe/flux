---
title: Optimization
description: Best practices for maximizing performance and memory efficiency in Flux.
outline: deep
sidebar_position: 1
---

# Optimization

Flux's reactive core skips Virtual DOM diffing and updates only the properties and computations affected by a change. These patterns help you get the most out of the graph in performance-sensitive UI and game systems.

## 1. Granular State & Stores

Split distinct values into individual [Signals](/guide/concepts/signals) so each binding wakes only for the value it reads. For nested tables or player data schemas, use a [Store](/guide/concepts/stores). Each nested key gets its own lazy leaf Signal, and [`Flux.Store.reconcile`](/guide/concepts/stores#reconciling-snapshots) diffs incoming server snapshots so unchanged fields never trigger downstream work.

## 2. Smart List & Conditional Rendering

Creating and destroying Roblox [`Instances`](https://create.roblox.com/docs/reference/engine/classes/Instance) is one of the more expensive operations in the engine:

- **Lists:** Always render dynamic arrays with [`Flux.forValue`, `Flux.forKey`, or `Flux.forIndex`](/guide/concepts/mapping) instead of rebuilding children in a plain loop. `forValue` caches instances by item reference and updates their `index` node in place (bind `LayoutOrder = index` on the returned `GuiObject` so `UIListLayout` reorders them visually). `forKey` caches instances by a stable ID (`keyOf(item)`) while updating both `index` and `item` nodes across snapshot replacements. `forIndex` caches slots by index for primitive lists.
- **Conditionals:** Prefer [`Flux.show`](/guide/concepts/conditionals#showing-one-of-two-branches) over [`Flux.showKeyed`](/guide/concepts/conditionals#keyed-show) unless you specifically need to tear down and recreate the subtree when a truthy value changes identity.
- **Selection:** Use [`Flux.selector`](/guide/concepts/selectors) for active-row highlighting in large lists so changing selection is `O(1)` (waking only the old and new rows) instead of `O(N)`.

## 3. Sharing Explicit Computeds

Every inline function passed to a property in `Flux.new` or `Flux.edit` creates an implicit [Computed](/guide/concepts/computeds). When multiple properties derive from the same calculation, hoist it into a single shared `Flux.computed` so the math runs once:

```luau
local health = Flux.signal(50)

-- Shared across both bindings: evaluates once per change
local healthColor = Flux.computed(function()
	return if health() < 20 then Color3.new(1, 0, 0) else Color3.new(1, 1, 1)
end)

local healthBar = Flux.new "Frame" { BackgroundColor3 = healthColor }
local healthLabel = Flux.new "TextLabel" { TextColor3 = healthColor }
```

## 4. Zero-Wrapper Fast Paths {#zero-wrapper-primitives}

In hot loops or high-frequency reactive graphs where you want to avoid metatable call dispatch and table wrapper allocations, Flux exposes SolidJS-style function tuple primitives:

| Fast-Path API | Equivalent Object API |
| :--- | :--- |
| `local get, set = Flux.createSignal(v, eq?)` | `local s = Flux.signal(v, eq?)` (`set(v, force?)` returns `T`) |
| `local get = Flux.createMemo(fn, eq?)` | `local c = Flux.computed(fn, eq?)` |
| `Flux.createEffect(fn)` | `Flux.effect(fn)` (registered to the active [Scope](/guide/concepts/scopes)) |
| `local get = Flux.getter(node)` | Extracts a direct `() -> T` closure from an existing Signal or Computed |
| `local set = Flux.setter(node)` | Extracts a direct `(value: T, force: boolean?) -> T` closure from an existing Signal |

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

`createSignal` and `createMemo` closures are valid `Flux.Reactive<T>` sources. You can pass `getCount` or `getDoubled` directly to property bindings, `Flux.spring`, or `Flux.show`.

## 5. How the Reactive Graph Minimizes Work

### Height-Ordered Stabilization & Early Cutoff

When a [Computed](/guide/concepts/computeds) has active downstream observers (such as an Effect or UI binding), Flux maintains its topological height in the dependency graph:

1. **Ordered stabilization:** Upstream Computeds always settle before deeper Computeds or Effects that read them. Diamond dependency graphs never evaluate a node twice or expose half-updated values.
2. **Early cutoff:** If an upstream Computed re-evaluates and produces an equal value (`==` or custom `equals`), propagation stops right away. Downstream Computeds and Effects aren't woken.
3. **Zero cost when unobserved:** A Computed with no downstream observers unsubscribes from its sources and stays dormant until read.

### Custom Equality Short-Circuiting {#equality-short-circuiting}

Roblox value types (`Vector3`, `Color3`, `UDim2`) compare by value automatically, whereas tables compare by reference. When a Signal or Computed produces a fresh table each time, pass a custom `equals` comparator to stop propagation when the contents haven't changed:

```luau
local pos = Flux.computed(function()
	return { x = math.floor(rawX()), y = math.floor(rawY()) }
end, function(a, b)
	return a.x == b.x and a.y == b.y
end)
```

### Effect Batching {#effect-batching}

Effects and property bindings batch their updates to the end of the frame, flushing on `RunService.PreRender` on the client (right before rendering) and `RunService.Heartbeat` on the server. Updating a Signal hundreds of times in a single frame still runs each dependent Effect at most **once** with the final settled value.

### Implicit LayoutOrder

When you pass unpinned child `GuiObject`s (or reactive child-node slots) in the array part of `Flux.new` or `Flux.edit`, Flux assigns sequential `LayoutOrder` values (`1, 2, 3, ...`) automatically while leaving any explicit `LayoutOrder` (including `LayoutOrder = 0`) pinned.
