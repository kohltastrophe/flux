---
title: Selectors
description: O(1) keyed selection for large reactive lists in Flux.
outline: deep
---

# Selectors

Imagine a list of 500 rows where exactly one is highlighted. When the player clicks a different row, the highlight must move. The naive approach is for every row to ask "am I the selected one?", but that means all 500 rows re-evaluate on every selection change, even though only two of them actually flipped state.

**`Flux.selector`{lua}** solves this. It is the Flux equivalent of SolidJS's [`createSelector`](https://docs.solidjs.com/reference/reactive-utilities/create-selector): an O(1) keyed selection primitive that, when the selection moves from one key to another, re-evaluates only the two affected rows, not the whole list.

## Creating a Selector

Create one with `Flux.selector`{lua}; created inside a [Scope](/guide/concepts/scopes), it is torn down with that scope. It takes a **source** (the currently selected key) and returns a callable object.

The source can be any of three things:

- A reactive **node** (a `Flux` Signal, Computed, etc.).
- A **function** that reads reactive nodes, like a Computed body.
- A plain **value** (rarely useful, since it never changes).

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

-- The currently selected row id (a reactive Signal)
local selectedId = Flux(1)

-- A selector keyed by row id
local isSelected = Flux.selector(selectedId)
```

## Reading a Selection

The returned object is **callable**. Call it with a key to reactively read whether that key is the currently selected one:

```luau
isSelected(42) -- true if selectedId() == 42, false otherwise
```

`isSelected(key)`{luau} is exactly equivalent to `isSelected:get(key)`{luau}; the call form is just sugar. Either way, the read is **reactive**: it makes the calling computation or binding depend on _just that one key_. A row binding on `isSelected(row.id)`{luau} only re-runs when `row.id`'s selected state actually changes, not when some other row's does.

> [!NOTE]
> A per-key node is created lazily on a key's first read **from inside a reactive computation or binding**. A key never read that way costs nothing, and an imperative `isSelected(key)`{luau} check in plain code (e.g. an event handler) returns the current answer without allocating a node at all. So the selector scales with the number of _rendered_ rows, not the size of your underlying data.

## Why It's Fast

This is the point of a selector, so here is the contrast explicitly.

Consider a binding that reads the selection directly:

```luau
-- Naive: re-runs for EVERY row on EVERY selection change
Highlighted = function()
    return row.id == selectedId()
end
```

Every row's binding depends on `selectedId`, so changing it dirties all 500 bindings, and the flush re-evaluates all 500, even though 498 of them return the same value they did before.

A selector inverts this. The selector keeps one internal watcher that is the _only_ thing tracking the source. Each row instead depends on its own per-key node. When the selection moves from key `A` to key `B`, the watcher flips exactly two nodes (`A` to `false` and `B` to `true`) and only the two rows depending on those keys re-evaluate:

```luau
-- O(1): only the two affected rows re-run
Highlighted = function()
    return isSelected(row.id)
end
```

In a 500-row list, moving the highlight touches 2 rows, not 500.

## A Worked Example

Here is a selectable list built with a [mapped list](/guide/concepts/mapping). Each row binds its highlight to `isSelected(row.id)`{luau}, and clicking a row sets the selected id. Only the previously-selected row and the newly-selected row ever re-render their color.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

local new = Flux.new

local rows = Flux({
    { id = 1, label = "Sword" },
    { id = 2, label = "Shield" },
    { id = 3, label = "Potion" },
})

-- Currently selected row id
local selectedId = Flux(1)

-- O(1) selector keyed by row id
local isSelected = Flux.selector(selectedId)

local list = new "Frame" {
    Name = "Inventory",

    Flux.forValue(rows, function(_, row)
        return new "TextButton" {
            Name = row.label,
            Text = row.label,

            -- Reactive, but only flips when THIS row's selected state changes
            BackgroundColor3 = function()
                return if isSelected(row.id)
                    then Color3.fromRGB(80, 140, 255)
                    else Color3.fromRGB(40, 40, 40)
            end,

            -- Clicking sets the selection; the selector flips just two nodes
            Activated = function()
                selectedId(row.id)
            end,
        }
    end),
}
```

When the player clicks "Shield" while "Sword" is selected, only the "Sword" and "Shield" buttons recompute their `BackgroundColor3`. "Potion" (and every other row in a larger list) is untouched.

## Custom Matchers

By default, a selector matches with `==`{luau}: a key is selected when it is equal to the source value. You can pass a custom matcher as the second argument when "selected" means something more involved than identity:

```luau
-- Select every row whose id falls inside a chosen range
local range = Flux({ min = 2, max = 5 })

local inRange = Flux.selector(range, function(value, key)
    return key >= value.min and key <= value.max
end)
```

The matcher receives `(sourceValue, key)`{luau} and returns a boolean.

> [!CAUTION]
> The custom-matcher path is **not** O(1). The default `==`{luau} path can flip exactly the two affected nodes because it knows precisely which key the old and new source values correspond to. A custom comparator's match is opaque (Flux cannot know which keys it newly includes or excludes), so on every source change it must re-test _every per-key node it has created so far (one per key ever read)_: O(live keys). Use a custom matcher when you need range or predicate selection, but prefer the default for plain single-selection.

## Cleaning Up

A selector holds an internal watcher and one node per key it has seen. When you no longer need it, destroy it to tear all of that down:

```luau
isSelected:destroy()
```

Created inside a [`Flux.scope`](/guide/concepts/scopes), the selector is destroyed automatically when that scope is destroyed, so you never have to track it by hand.
