---
title: Selectors
description: O(1) keyed selection for large reactive lists in Flux.
outline: deep
sidebar_position: 13
---

# Selectors

In a 500-row list where one row is highlighted, having every row read `selectedId() == row.id` wakes all 500 bindings on every selection change. **`Flux.selector(source, equals?)`** cuts single-item selection down to **`O(1)`** so only the row losing selection and the row gaining it re-run.

```luau
type Row = { id: number, label: string }

local rows = Flux.signal({
	{ id = 1, label = "Sword" },
	{ id = 2, label = "Shield" },
	{ id = 3, label = "Potion" },
} :: { Row })

local selectedId = Flux.signal(1)
local isSelected = Flux.selector(selectedId)

local list = Flux.new "Frame" {
	Flux.list({ gap = 4 }),

	Flux.forKey(
		rows,
		function(row: Row)
			return row.id
		end,
		function(index, row: Flux.Node<Row>)
			local id = row:peek().id
			return Flux.new "TextButton" {
				LayoutOrder = index,
				Text = function()
					return row().label
				end,
				BackgroundColor3 = function()
					return if isSelected(id)
						then Color3.fromRGB(80, 140, 255)
						else Color3.fromRGB(40, 40, 45)
				end,
				Activated = function()
					selectedId(id)
				end,
			}
		end
	),
}
```

## Creating a Selector

Call `Flux.selector(source, equals?)` where `source` is a reactive Node, a getter function `() -> S`, or a plain value. Leave a 1-argument `local isSelected = Flux.selector(selectedId)` unannotated so Luau infers the key type automatically. Created inside a [`Flux.scope`](/guide/concepts/scopes), the selector cleans up automatically when the scope is destroyed.

## Reading a Selection

Call `isSelected(key)` (or `isSelected:get(key)`) inside a [Computed](/guide/concepts/computeds), [Effect](/guide/concepts/effects), or property binding to subscribe **only** to whether `key` matches `source`:

```luau
local active = isSelected(42) -- true when selectedId() == 42
```

Per-key boolean nodes allocate lazily when a key is read inside a reactive context and release automatically once no reaction observes that key. Calling `isSelected(key)` outside a reactive context runs a direct comparison with zero node allocation.

## Custom Matchers

Pass a custom `equals(sourceValue, key)` comparator as the second argument when selection is a predicate rather than `==`:

```luau
local range = Flux.signal({ min = 2, max = 5 })

local inRange = Flux.selector(range, function(value, key: number)
	return key >= value.min and key <= value.max
end)
```

The default `==` path updates at most **two** per-key nodes per change (`O(1)`). Because a custom comparator can match any subset of keys, it re-tests every currently observed key on each source change (`O(observed keys)`).

## Cleaning Up

A selector created inside a [`Flux.scope`](/guide/concepts/scopes) tears down with the scope. To tear down a standalone selector manually, call `isSelected:Destroy()` (or `Flux.dispose(isSelected)`).
