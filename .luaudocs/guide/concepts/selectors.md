---
title: Selectors
description: O(1) keyed selection for large reactive lists in Flux.
outline: deep
sidebar_position: 11
---

# Selectors

In a 500-row list where one row is highlighted, having every row read `selectedId() == row.id` wakes all 500 bindings on every selection change. **`Flux.selector(source, equals?)`** reduces single-item selection to **O(1)**: only the row losing selection and the row gaining it re-evaluate.

```luau
local rows = Flux.signal({
	{ id = 1, label = "Sword" },
	{ id = 2, label = "Shield" },
	{ id = 3, label = "Potion" },
})

local selectedId = Flux.signal(1)
local isSelected = Flux.selector(selectedId)

local list = Flux.new "Frame" {
	Flux.list({ gap = 4 }),

	Flux.forValue(rows, function(_, row)
		return Flux.new "TextButton" {
			Text = row.label,
			BackgroundColor3 = function()
				return if isSelected(row.id)
					then Color3.fromRGB(80, 140, 255)
					else Color3.fromRGB(40, 40, 45)
			end,
			Activated = function()
				selectedId(row.id)
			end,
		}
	end),
}
```

## Creating a Selector

Call `Flux.selector(source, equals?)` where `source` is a reactive Node, a getter function `() -> S`, or a plain value. Created inside a [`Flux.scope`](/guide/concepts/scopes), the selector is cleaned up automatically when the scope is destroyed.

## Reading a Selection

Call `isSelected(key)` (or `isSelected:get(key)`) inside a [Computed](/guide/concepts/computeds), [Effect](/guide/concepts/effects), or property binding to subscribe **only** to whether `key` matches `source`:

```luau
local active = isSelected(42) -- true when selectedId() == 42
```

Per-key boolean nodes are allocated lazily when a key is read inside a reactive context and released automatically once no reaction observes that key. Calling `isSelected(key)` outside a reactive context performs an immediate comparison with zero node allocation.

## Custom Matchers

Pass a custom `equals(sourceValue, key)` comparator as the second argument when selection is a predicate rather than `==`:

```luau
local range = Flux.signal({ min = 2, max = 5 })

local inRange = Flux.selector(range, function(value, key: number)
	return key >= value.min and key <= value.max
end)
```

> [!NOTE] Complexity of Custom Matchers
> The default `==` path updates at most **two** per-key nodes per change (**O(1)**). Because a custom comparator can match any subset of keys, it re-tests every currently observed key on each source change (**O(observed keys)**).

## Cleaning Up

A selector created inside a [`Flux.scope`](/guide/concepts/scopes) is destroyed with the scope. To tear down a standalone selector manually, call `isSelected:Destroy()` (or `Flux.dispose(isSelected)`).
