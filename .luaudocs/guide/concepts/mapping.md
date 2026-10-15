---
title: Mapping
description: Efficiently rendering and updating dynamic lists in Flux.
outline: deep
sidebar_position: 7
---

# Mapping

Mapping over a reactive array inside a plain Computed or property binding rebuilds every Instance whenever a single item changes. **`Flux.forValue`** and **`Flux.forIndex`** cache mapped elements in per-item child [Scopes](/guide/concepts/scopes) and update only the entries that changed.

| Helper | Keyed By | Mapper Signature | Best For |
| :--- | :--- | :--- | :--- |
| **`Flux.forValue(list, fn)`** | Item identity (`value`) | `(index: Node<number>, value: T)` | Unique objects/tables that may be reordered, inserted, or removed |
| **`Flux.forIndex(list, fn)`** | Array index (`number`) | `(index: number, item: Node<T>)` | Primitive values (strings, numbers) or fixed-slot lists |

Place the returned node at a numeric index inside [`Flux.new`](/guide/roblox/creation) or [`Flux.edit`](/guide/roblox/hydration) to bind its results as children.

## `Flux.forValue`{lua} (Keyed by Value)

`Flux.forValue` caches each mapped subtree by its **item value**. When an array is sorted or an item shifts position, its Instance is kept and its `index` node updates in place:

```luau
local players = Flux.signal({
	{ id = 1, name = "Kohl" },
	{ id = 2, name = "Geed" },
})

local list = Flux.new "Frame" {
	Flux.list({ gap = 4 }),

	Flux.forValue(players, function(index, player)
		return Flux.new "TextLabel" {
			Text = player.name,
			LayoutOrder = index, -- updates reactively when the item moves
			Size = UDim2.new(1, 0, 0, 30),
		}
	end),
}
```

> [!IMPORTANT] Bind `LayoutOrder = index` When Sorting
> Values in `forValue` must be **unique** (duplicate values share one entry). Bind `LayoutOrder = index` on the returned `GuiObject` so Roblox's layout container reorders existing instances visually when their array position changes.

## `Flux.forIndex`{lua} (Keyed by Index)

`Flux.forIndex` caches each mapped subtree by its **numeric slot**. When the item at index `1` changes, the Instance at slot `1` stays mounted and its `item` node updates:

```luau
local tags = Flux.signal({ "Admin", "VIP", "Tester" })

local tagList = Flux.new "Frame" {
	Flux.list({ gap = 4 }),

	Flux.forIndex(tags, function(index, tag)
		return Flux.new "TextLabel" {
			Name = `Slot_{index}`,
			Text = tag, -- Node<string>: updates in place when tags()[index] changes
			Size = UDim2.new(1, 0, 0, 30),
		}
	end),
}
```

> [!NOTE] Mapper Functions Run Untracked
> Both `forValue` and `forIndex` run their mapper callback untracked once per entry and destroy that entry's child scope when the item or slot leaves the array. For O(1) single-item selection across a mapped list, pair mapping with [`Flux.selector`](/guide/concepts/selectors).
