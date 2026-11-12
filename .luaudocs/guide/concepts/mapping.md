---
title: Mapping
description: Efficiently rendering and updating dynamic lists in Flux.
outline: deep
sidebar_position: 7
---

# Mapping

Mapping over a reactive array inside a plain Computed or property binding rebuilds every Instance whenever a single item changes. **`Flux.forValue`**, **`Flux.forKey`**, and **`Flux.forIndex`** cache mapped elements in per-item child [Scopes](/guide/concepts/scopes) and update only the entries that changed.

| Helper | Keyed By | Mapper Signature | Best For |
| :--- | :--- | :--- | :--- |
| **`Flux.forValue(list, fn)`** | Item identity (`value`) | `(index: Node<number>, value: T)` | Unique object references or instances that reorder, insert, or remove |
| **`Flux.forKey(list, keyOf, fn)`** | `keyOf(item)` | `(index: Node<number>, item: Node<T>)` | Immutable records or snapshots keyed by a stable ID (`item.id`, `userId`) |
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

Values in `forValue` must be **unique** (duplicate values share one entry). Bind `LayoutOrder = index` on the returned `GuiObject` so Roblox's layout container reorders existing instances visually when their array position changes.

## `Flux.forKey`{lua} (Keyed by Function)

When a server snapshot or immutable update replaces `{ id = 1, score = 10 }` with a fresh `{ id = 1, score = 20 }` table, `forValue` sees a new table reference and rebuilds that row. `Flux.forKey(list, keyOf, fn)` keys each entry by `keyOf(item)` instead, keeping the row's Instance mounted while updating both `index` (`Node<number>`) and `item` (`Node<T>`) in place:

```luau
type Entry = { userId: number, name: string, score: number }

local leaderboard = Flux.signal({
	{ userId = 101, name = "Kohl", score = 40 },
	{ userId = 202, name = "Geed", score = 35 },
} :: { Entry })

local board = Flux.new "Frame" {
	Flux.list({ gap = 4 }),

	Flux.forKey(
		leaderboard,
		function(entry: Entry)
			return entry.userId
		end,
		function(index, entry: Flux.Node<Entry>)
			return Flux.new "TextLabel" {
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, 30),
				Text = function()
					local current = entry()
					return `#{index()} {current.name}: {current.score}`
				end,
			}
		end
	),
}
```

Keys returned by `keyOf` must be unique across the list. If `keyOf(item)` returns `nil`, Flux falls back to keying that entry by `item` itself.

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

All three mappers run their callback untracked once per entry and destroy that entry's child scope when the item, key, or slot leaves the array. For O(1) single-item selection across a mapped list, pair mapping with [`Flux.selector`](/guide/concepts/selectors).
