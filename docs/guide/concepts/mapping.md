---
title: Mapping
description: Efficiently rendering and updating dynamic tables in Flux.
outline: deep
---

# Mapping

Mapping over an array of data to create multiple UI elements is a common pattern. However, doing this inside a standard Computed or a property binding causes performance issues; adding a single new item would destroy and recreate every element in the list.

Flux provides two control flow utilities: **`Flux.forValue`{lua}** and **`Flux.forIndex`{lua}**. These cache your mapped results and only update the specific elements that changed, like `<For>`{ts} and `<Index>`{ts} in SolidJS.

Both functions return a reactive node. When placed at a numeric index in a `Flux.new`{lua} or `Flux.edit`{lua} constructor, the node is used as a **children binder**. Flux handles parenting, ordering, and cleanup as the source list changes. When an item is removed, its cached result is cleaned up and destroyed.

> [!NOTE]
> The mapping function runs **untracked**: reading other nodes inside it will not re-run the mapper. Reactivity inside a mapped result should come from the node argument (`item`/`indexNode`) or from bindings created within it.

For efficiently picking one item out of a mapped list (such as a highlighted row), see [Selectors](/guide/concepts/selectors).

## `Flux.forIndex`{lua} (Keyed by Index)

Use `forIndex` when working with arrays of primitives (strings, numbers) where the **position in the array** is what matters.

`forIndex` caches elements by their **index**. If the array updates at position `1`, the UI element at slot `1` stays in place and its data node is updated in-place; nothing is recreated.

The mapping function receives:

- `index` - the raw numeric index (a plain `number`, constant for the life of this slot)
- `item` - a **reactive node** that holds the current value at this index

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

-- An array of primitives
local tags = Flux({ "Admin", "VIP", "Tester" })

local tagsListUI = new "Frame" {
    new "UIListLayout" {},

    -- forIndex: one slot per array position; the node updates when the value changes
    Flux.forIndex(tags, function(index, tagNode)
        return new "TextLabel" {
            Name = "TagSlot_" .. index,  -- index is constant for this slot
            Text = tagNode,               -- tagNode updates reactively in place
            Size = UDim2.new(1, 0, 0, 30),
        }
    end),
}
```

## `Flux.forValue`{lua} (Keyed by Value)

Use `forValue` when working with arrays of objects or unique tables where the **identity of the item** is what matters, not its position.

`forValue` caches elements by their **value**. If an item moves to a different position in the array (e.g., after a sort), Flux preserves the mapped result and updates the index node instead of recreating the UI.

> [!WARNING]
> Because the value is the cache key, values must be **unique**. Duplicate values in the list share a single mapped result; use `forIndex` for lists that may contain duplicates.

The mapping function receives:

- `indexNode` - a **reactive node** (`Node<number>`{luau}) that tracks the current position of this item in the array
- `value` - the raw value (the item itself, constant for the life of this cache entry)

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

-- An array of unique table objects
local players = Flux({
    { id = 1, name = "Kohl" },
    { id = 2, name = "Geed" },
})

local playerListUI = new "Frame" {
    new "UIListLayout" {},

    -- forValue: re-uses each mapped result even if items change position
    Flux.forValue(players, function(indexNode, player)
        return new "TextLabel" {
            -- player.name is a plain string constant for this entry
            Text = player.name,

            -- The index can change (e.g., after sorting), so read it reactively
            LayoutOrder = indexNode,

            Size = UDim2.new(1, 0, 0, 30),
        }
    end),
}
```

> [!IMPORTANT] Reordering needs `LayoutOrder = indexNode`
> A reused `forValue` result keeps the [`LayoutOrder`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject#LayoutOrder) it was first assigned, so binding it to `indexNode` (as above) is what actually re-orders the list on screen when the array is sorted; leave it out and the visual order won't change even though the data did. `forIndex` needs no such binding: its slots are position-keyed, so the order Flux auto-assigns already matches.

## Summary: Which Should I Use?

| Method                    | Best For                      | Mapping Signature                           | Caching Strategy                                                 |
| :------------------------ | :---------------------------- | :------------------------------------------ | :--------------------------------------------------------------- |
| **`Flux.forIndex`{luau}** | Primitives (strings, numbers) | `(index: number, item: Node<T>)`{luau}      | Keyed by position. Data updates in-place; UI slot is preserved.  |
| **`Flux.forValue`{luau}** | Objects / unique tables       | `(indexNode: Node<number>, value: T)`{luau} | Keyed by value. UI follows the object if the array is re-sorted. |

**Rule of thumb:** the choice is about what each entry is keyed on, not about list length; both handle items being added and removed. `forIndex` keys by **position**, so when you insert or remove in the middle, every later slot's data node is updated in place rather than the UI moving. Use it for primitives where the slot matters more than the item (like skill names mapped to fixed slots). `forValue` keys by **identity**, so a mapped result follows its object even when the array is reordered. Use it when you have unique objects that might be sorted or shuffled (like player cards in a leaderboard).
