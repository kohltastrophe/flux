---
title: Computeds
description: Caching and deriving reactive state in Flux.
outline: deep
sidebar_position: 2
---

# Computeds

A **Computed** derives a cached reactive value from other reactive nodes, recomputing only when its dependencies change.

```luau
local price = Flux.signal(25)
local quantity = Flux.signal(3)

local total = Flux.computed(function()
	return price() * quantity()
end)

print(total()) --> 75
```

## Creating a Computed

Use `Flux.computed(fn, equals?)` for a typed `Node<T>`, or pass a function to `Flux(fn)` for the terse untyped shorthand:

```luau
local count = Flux.signal(5)

-- Explicitly typed Node<number>
local doubled = Flux.computed(function()
	return count() * 2
end)

-- Terse shorthand (Node<any>)
local tripled = Flux(function()
	return count * 3
end)
```

Pass an optional `equals(old, new)` comparator as the second argument to stop downstream propagation when a recomputed result is logically unchanged (see [Custom Equality](/guide/concepts/signals#custom-equality)).

> [!TIP] Zero-Wrapper Fast Path (`Flux.createMemo`)
> When you only need a tracked getter function `() -> T` without node methods or operators, `Flux.createMemo(fn, equals?)` skips the node table wrapper. See [Optimization](/guide/tips/optimization#zero-wrapper-primitives).

## How Computeds Evaluate

A Computed adapts its evaluation strategy depending on whether an [Effect](/guide/concepts/effects) or UI binding is actively watching it:

1. **Dormant when unobserved:** While no Effect or UI binding depends on a Computed, it holds zero upstream subscriptions and does not run until you read `computed()`. Once read, it caches the result and only recalculates on a future read if an upstream source changed.
2. **Stabilized in order when observed:** While watched by an Effect or UI property, the Computed subscribes to its sources. When a signal changes, Flux stabilizes dirty observed Computeds in **dependency height order** (shallowest to deepest) during the frame flush—before any Effect runs—so no node ever evaluates twice or sees a half-updated "diamond" state.
3. **Early cutoff:** If a Computed re-evaluates to the same value (`==` or `equals`), propagation stops immediately and downstream Computeds and UI bindings do not wake up.

```luau
local count = Flux.signal(1)

local isEven = Flux.computed(function()
	return count() % 2 == 0
end)

-- Dormant until first read:
print(isEven()) --> false
print(isEven()) --> false (cached, body does not re-run)

count(3)
-- 3 is still odd: when `isEven` re-evaluates, its value stays `false`,
-- so any UI binding watching `isEven` is skipped entirely.
```

## Reading the Previous Value

A Computed (or [Effect](/guide/concepts/effects)) receives its own **previous return value** as its first argument (`nil` on the first run), making folds and running maximums straightforward:

```luau
local score = Flux.signal(0)

local highScore = Flux.computed(function(previous: number?)
	return math.max(previous or 0, score())
end)

score(40)
print(highScore()) --> 40
score(15)
print(highScore()) --> 40
score(90)
print(highScore()) --> 90
```

## Binding to the UI

Pass a Computed directly to any property in [`Flux.new`](/guide/roblox/creation) or [`Flux.edit`](/guide/roblox/hydration):

```luau
local items = Flux.signal({ "Sword", "Shield", "Potion" })

local summary = Flux.computed(function()
	return `Inventory ({#items()}): {table.concat(items(), ", ")}`
end)

local label = Flux.new "TextLabel" {
	Size = UDim2.fromOffset(300, 50),
	Text = summary,
}
```

## Implicit vs. Explicit Computeds

Passing an inline function (`Text = function() ... end`) to `Flux.new` or `Flux.edit` binds that property reactively with the same tracking as an explicit Computed. Choose between them based on **reuse**:

- **Inline function (`Property = function() ... end`):** Best when a derived value is used by a **single** property.
- **Explicit Computed (`Flux.computed`):** Best when the **same** derived value feeds **multiple** properties or downstream computations, so the logic runs once and cuts off early when unchanged.

```luau
local health = Flux.signal(50)

-- Shared across two properties: computed once per change
local lowHealthColor = Flux.computed(function()
	return if health() < 20 then Color3.fromRGB(255, 60, 60) else Color3.fromRGB(255, 255, 255)
end)

local bar = Flux.new "Frame" { BackgroundColor3 = lowHealthColor }
local label = Flux.new "TextLabel" { TextColor3 = lowHealthColor }
```
