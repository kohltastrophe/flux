---
title: Stores
description: Managing deeply reactive, nested state in Flux.
outline: deep
---

# Stores

While **Values** are perfect for primitives like numbers and strings, managing large, deeply nested tables requires a different approach. Putting a complex table inside a standard `Flux` Value means the entire table is considered "changed" on every mutation, triggering all observers even if only one deep property changed.

**Stores** solve this with **deep reactivity**. A Store wraps your table in a transparent proxy, tracking each individual key, nested table, and iteration separately. When you mutate a deep property, only the specific bindings that read that exact key will update.

If you are coming from other frameworks, you can think of Stores as SolidJS's [`createStore`](https://docs.solidjs.com/reference/store-utilities/create-store#createstore) or Vue's `reactive()`{ts}.

## Creating a Store

Initialise a Store by calling `Flux.store`{lua} and passing a starting table. The initial state must be a table.

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

Stores are designed to be completely invisible. You interact with them exactly as you would any plain Luau table.

Under the hood, Flux intercepts reads and writes via metatables. Accessing a nested table creates and caches a proxy for it. You can mutate deeply nested state directly, and Flux will notify only the relevant subscribers.

```luau
-- Reading a property inside a reactive context tracks it as a dependency
Flux(function()
    print("Health changed to: " .. state.player.health)
end, true)

-- Direct mutation triggers only the observers of 'health'
state.player.health -= 10
-- > "Health changed to: 90"

-- Updating one branch does NOT trigger observers of another
state.settings.volume = 0.8
-- (The health effect above will NOT run again)
```

## Arrays and Iteration

Stores fully support Luau's standard iteration and length operators. When you iterate over a store with `for k, v in store.table do`{lua} or check its length with `#store.table`{lua}, Flux registers a structural dependency on that level of the table.

If a key is added or removed, or if the array length changes, any Computeds or Effects that iterate over that level will re-evaluate.

```luau
Flux(function()
    -- #state.player.inventory is reactively tracked
    print("You have " .. #state.player.inventory .. " items.")
end, true)

-- Adding to the table triggers the iteration/length tracker
table.insert(state.player.inventory, "Potion")
-- > "You have 3 items."
```

## Unwrapping a Store

Sometimes you need to pass your reactive state to a standard Roblox API (like [`DataStoreService`](https://create.roblox.com/docs/en-us/reference/engine/classes/DataStoreService) or [`HttpService`](https://create.roblox.com/docs/en-us/reference/engine/classes/HttpService)) that doesn't understand proxy tables. Passing a Store directly may cause errors.

You can extract the raw, un-proxied Luau table by using `Store.unwrap`{lua}. Because `unwrap` is not part of the main `Flux` object, require the `Store` module directly:

```luau
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flux = require(ReplicatedStorage.Flux)
local Store = require(ReplicatedStorage.Flux.Store)

local state = Flux.store({ name = "Guest", coins = 0 })

local function saveData(userId)
    -- Safely extract the plain table before passing to DataStore
    local rawData = Store.unwrap(state)
    DataStoreService:GetDataStore("PlayerData"):SetAsync(userId, rawData)
end
```

## Store vs. Value

|                         | `Flux(table)`{luau}                               | `Flux.store(table)`{luau}                   |
| :---------------------- | :------------------------------------------------ | :------------------------------------------ |
| **Dependency tracking** | Whole-table granularity                           | Per-key granularity                         |
| **Mutation syntax**     | Must replace entire table: `state({ ... })`{luau} | Direct assignment: `state.health = 90`{lua} |
| **Nested tables**       | Not reactive                                      | Lazily proxied and tracked                  |
| **Arrays / iteration**  | Not tracked                                       | Structurally tracked                        |
| **Best for**            | Simple, flat state that changes wholesale         | Complex schemas, player data, inventories   |
