---
title: Mapping tables
description: Efficiently rendering and updating dynamic tables in Flux.
outline: deep
---

# Table Rendering

Mapping over an array of data to create multiple UI elements is a common pattern. However, doing this inside a standard Computed or a property binding causes performance issues; adding a single new item would destroy and recreate every element in the list.

Flux provides two specialised control flow utilities: **`Flux.forValue`{lua}** and **`Flux.forIndex`{lua}**. These cache your mapped results and only update the specific elements that changed, exactly like `<For>`{ts} and `<Index>`{ts} in SolidJS.

Both functions return a reactive Node. When placed at a numeric index in a `Flux.new`{lua} or `Flux.edit`{lua} constructor, the node is automatically used as a **children binder**. Flux handles parenting, ordering, and cleanup as the source list changes. When an item is removed, its cached result is automatically cleaned up and destroyed.

## `Flux.forIndex`{lua} (Keyed by Index)

Use `forIndex` when working with arrays of primitives (strings, numbers) where the **position in the array** is what matters.

`forIndex` caches elements by their **index**. If the array updates at position `1`, the UI element at slot `1` stays in place and its data node is updated in-place; nothing is recreated.

The mapping function receives:

- `index` - the raw numeric index (a plain `number`, constant for the life of this slot)
- `item` - a **reactive `Node`** that holds the current value at this index

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

The mapping function receives:

- `indexNode` - a **reactive `Node<number>`{luau}** that tracks the current position of this item in the array
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

## Summary: Which Should I Use?

| Method                   | Best For                      | Mapping Signature                           | Caching Strategy                                                 |
| :----------------------- | :---------------------------- | :------------------------------------------ | :--------------------------------------------------------------- |
| **`Flux.forIndex`{lua}** | Primitives (strings, numbers) | `(index: number, item: Node<T>)`{luau}      | Keyed by position. Data updates in-place; UI slot is preserved.  |
| **`Flux.forValue`{lua}** | Objects / unique tables       | `(indexNode: Node<number>, value: T)`{luau} | Keyed by value. UI follows the object if the array is re-sorted. |

**Rule of thumb:** if you have unique objects that might be reordered (like player cards in a leaderboard), use `forValue`. If you have a list of strings or numbers that change in value but not in length (like skill names mapped to slots), use `forIndex`.
