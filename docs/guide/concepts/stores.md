---
title: Stores
description: Managing deeply reactive, nested state in Flux.
outline: deep
---

# Stores

While **Signals** work well for primitives like numbers and strings, managing large, deeply nested tables needs a different approach. Putting a complex table inside a standard `Flux` signal means the entire table is considered "changed" on every mutation, re-running every Computed and Effect that reads it even if only one deep property changed.

**Stores** solve this with **deep reactivity**. A Store wraps your table in a transparent proxy, tracking each individual key, nested table, and iteration separately. When you mutate a deep property, only the Computeds and Effects that read that exact key will re-run.

If you are coming from other libraries, you can think of Stores as SolidJS's [`createStore`](https://docs.solidjs.com/reference/store-utilities/create-store#createstore) or Vue's `reactive()`{ts}.

## Creating a Store

Initialize a Store by calling `Flux.store`{lua} and passing a starting table. The initial state must be a table.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

-- Create a deeply reactive store
local state = Flux.store({
    player = {
        name = "Guest",
        health = 100,
        inventory = { "Sword", "Shield" },
    },
    settings = {
        volume = 0.5,
    },
})
```

## Deep Reactivity & Mutating State

Stores behave like plain Luau tables. You interact with them the same way you would any plain table.

Under the hood, Flux intercepts reads and writes via metatables. Accessing a nested table creates and caches a proxy for it. You can mutate deeply nested state directly, and Flux will re-run only the nodes that read the key you changed.

```luau
-- Reading a property inside a reactive context tracks it as a dependency.
-- The `..` operator reads the node's current value automatically (see [Signals](/guide/concepts/signals)).
Flux(function()
    print("Health changed to: " .. state.player.health)
end, true) -- the `true` makes this an Effect (see [Effects](/guide/concepts/effects))

-- Direct mutation re-runs only the nodes that read 'health'
state.player.health -= 10
-- > "Health changed to: 90"

-- Updating one branch does NOT re-run nodes that read another
state.settings.volume = 0.8
-- (The health Effect above will NOT run again)
```

> [!NOTE]
> Effects run at the end of the frame, so the printed output above appears on the next frame, not synchronously with the mutation.

## Arrays and Iteration

Stores fully support Luau's standard iteration and length operators. When you iterate over a store with `for k, v in store.table do`{luau} or check its length with `#store.table`{luau}, Flux registers a structural dependency on that level of the table.

If a key is added or removed, or if the array length changes, any Computeds or Effects that iterate over that level will re-evaluate.

> [!CAUTION]
> Luau's `table.insert`{lua} and `table.remove`{lua} bypass metatables, so they **do not work** on Store proxies. Use `Store.insert`{lua} and `Store.remove`{lua} instead; they take the same arguments (and validate the position, so an out-of-range index errors) and reactively update the shifted indices. These helpers are also reachable via `Flux.Store`{lua} (e.g. `Flux.Store.insert`{lua}).

```luau
local Store = Flux.Store

Flux(function()
    -- #state.player.inventory is reactively tracked
    print("You have " .. #state.player.inventory .. " items.")
end, true)

-- Adding to the array triggers the iteration/length tracker
Store.insert(state.player.inventory, "Potion")
-- > "You have 3 items."

-- Removing (and returning) the last item, like table.remove
local removed = Store.remove(state.player.inventory)
-- > "You have 2 items."
```

`Store.move(array, from, to)`{luau} reorders an element in place (e.g. `Store.move(state.player.inventory, 1, 3)`{luau} moves the first item to position 3), shifting the others to fill the gap, as a single tracked step. The length never changes, so no nested proxy is torn down, making it the right tool for drag-and-drop reordering. Both indices must be in range.

## Unwrapping a Store

Sometimes you need to pass your reactive state to a standard Roblox API (like [`DataStoreService`](https://create.roblox.com/docs/en-us/reference/engine/classes/DataStoreService) or [`HttpService`](https://create.roblox.com/docs/en-us/reference/engine/classes/HttpService)) that doesn't understand proxy tables. Passing a Store directly may cause errors.

You can extract the raw, un-proxied Luau table by using `Store.unwrap`{lua}:

```luau
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flux = require(ReplicatedStorage.Flux)
local Store = Flux.Store

local state = Flux.store({ name = "Guest", coins = 0 })

local function saveData(userId)
    -- Safely extract the plain table before passing to DataStore
    local rawData = Store.unwrap(state)
    DataStoreService:GetDataStore("PlayerData"):SetAsync(userId, rawData)
end
```

## Reconciling Snapshots

Game state often arrives as a fresh plain table: a [`RemoteEvent`](https://create.roblox.com/docs/en-us/reference/engine/classes/RemoteEvent) payload, a [`DataStore`](https://create.roblox.com/docs/en-us/reference/engine/classes/DataStoreService) load, a server tick. Assigning that whole table into a Store key would tear down the existing nested proxies and re-run **every** node that reads it, even for values that didn't change.

`Store.reconcile`{lua} (SolidJS's [`reconcile`](https://docs.solidjs.com/reference/store-utilities/reconcile)) diffs the new snapshot into the live store and fires **only the nodes whose leaves actually changed**, reusing the nested proxies that survived. It is the right tool for applying replicated state.

```luau
local Store = Flux.Store

local state = Flux.store({
    player = { health = 100, name = "Guest" },
    settings = { volume = 0.5 },
})

-- An Effect that only reads health
Flux(function()
    print("Health:", state.player.health)
end, true)

-- A snapshot from the server where only health changed
Store.reconcile(state, {
    player = { health = 90, name = "Guest" },
    settings = { volume = 0.5 },
})
-- > "Health: 90"
-- Only the health Effect re-ran; `name` and `volume` did not fire,
-- and `state.player` is still the same proxy it was before.
```

Reconcile is **positional** for arrays (it diffs index `i` against index `i`, growing or shrinking the length as needed) and recurses into nested tables, adding and removing keys to match the snapshot. The snapshot should be a plain, un-proxied table of acyclic data.

For arrays whose elements move or get inserted (a leaderboard, a sortable list), positional diffing rewrites every position from the change onward, firing all of them. Pass a **key** field name as the third argument to match elements by identity instead (like SolidJS's `reconcile({ key })`{ts}), so each element keeps its proxy (and its [`Flux.forValue`](/guide/concepts/mapping#flux-forvalue-keyed-by-value) result) across reorders, and a row's bindings fire only when that row's own data changes:

```luau
-- Match array elements by their `id` field rather than by position
Store.reconcile(state, snapshot, "id")
```

The key applies recursively to every nested array, and elements must have unique keys.

> [!NOTE]
> Like direct assignment, `Store.reconcile`{luau} mutates the store in place; never call it from inside a computation that reads the same store.

## Destroying a Store

Like any reactive node, the proxies inside a Store stay alive as long as something reads them. When a Store belongs to a system that shuts down (a closed menu, an ended round), release it with `Store.destroy`{lua}. It destroys every node the Store created and recurses into nested proxies, freeing the whole tree in one call:

```luau
local Store = require(ReplicatedStorage.Flux.Store)

local inventory = Flux.store({ items = {}, gold = 0 })

-- Later, when the system tears down:
Store.destroy(inventory)
```

A Store created inside a [`Flux.scope`](/guide/concepts/scopes) is torn down automatically when the scope is destroyed, so you only need `Store.destroy`{lua} for stores you manage outside a scope.

## Store vs. Signal

|                         | [`Flux(table)`{luau}](/guide/concepts/signals)    | `Flux.store(table)`{luau}                    |
| :---------------------- | :------------------------------------------------ | :------------------------------------------- |
| **Dependency tracking** | Whole-table granularity                           | Per-key granularity                          |
| **Mutation syntax**     | Must replace entire table: `state({ ... })`{luau} | Direct assignment: `state.health = 90`{luau} |
| **Nested tables**       | Not reactive                                      | Lazily proxied and tracked                   |
| **Arrays / iteration**  | Not tracked                                       | Structurally tracked                         |
| **Best for**            | Simple, flat state that changes wholesale         | Complex schemas, player data, inventories    |
