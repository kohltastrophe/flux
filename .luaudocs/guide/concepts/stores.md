---
title: Stores
description: Managing deeply reactive, nested tables and arrays in Flux.
outline: deep
sidebar_position: 8
---

# Stores

While a [Signal](/guide/concepts/signals) tracks a single value as a unit, **`Flux.store`** wraps a nested table in a deep proxy that tracks each read key, nested sub-table, and array length independently.

```luau
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

Flux.effect(function()
	print(`Health: {state.player.health}`)
end)

state.player.health -= 10 -- Re-runs the health effect
state.settings.volume = 0.8 -- Does NOT wake the health effect
```

## Creating a Store

Call `Flux.store(initialTable)` with a plain Luau table. Per-key signal nodes and nested proxies are allocated lazily on first access; values that already have metatables (such as Flux nodes or class instances) are left untouched.

## Arrays and Iteration

Iterating over a store (`for k, v in store.list do`) or reading `#store.list` subscribes the running computation to structural changes on that table level.

> [!CAUTION] Use `Flux.Store` Array Helpers Instead of `table.insert` / `table.remove`
> Luau's `table.insert` and `table.remove` bypass metatables. Always mutate store arrays with `Flux.Store.insert`, `Flux.Store.remove`, and `Flux.Store.move`:

```luau
local Store = Flux.Store

Flux.effect(function()
	print(`Items ({#state.player.inventory}): {table.concat(state.player.inventory, ", ")}`)
end)

Store.insert(state.player.inventory, "Potion") -- appends and notifies
Store.move(state.player.inventory, 1, 3)       -- moves index 1 to 3 in one tracked step
local last = Store.remove(state.player.inventory)
```

## Reconciling Snapshots

When a fresh snapshot arrives from a `RemoteEvent` or `DataStore`, assigning the whole table would fire every key. `Flux.Store.reconcile(target, snapshot, key?)` diffs `snapshot` into `target` in place, firing **only** the leaf nodes whose values changed and reusing unchanged nested proxies:

```luau
-- Only `health` changed; `name` and `settings.volume` observers stay asleep
Flux.Store.reconcile(state, {
	player = { name = "Guest", health = 80, inventory = { "Sword", "Shield" } },
	settings = { volume = 0.5 },
})
```

For arrays of objects that reorder or insert in the middle, pass an identity field name (such as `"id"`) as the third argument so `reconcile` matches array items by key instead of position:

```luau
Flux.Store.reconcile(leaderboardStore, serverSnapshot, "userId")
```

## Unwrapping a Store

Roblox APIs like `DataStoreService:SetAsync` or `HttpService:JSONEncode` expect raw tables rather than metatable proxies. Call `Flux.Store.unwrap(store)` for an untracked, plain-table view:

```luau
local rawTable = Flux.Store.unwrap(state)
PlayerDataStore:SetAsync(tostring(userId), rawTable)
```

## Destroying a Store

A store created inside a [`Flux.scope`](/guide/concepts/scopes) is torn down automatically when the scope is destroyed (or via [`Flux.dispose(store)`](/guide/concepts/scopes#disposing-by-hand-with-flux-dispose)). To tear down an unowned store manually, call `Flux.Store.Destroy(store)`:

```luau
Flux.Store.Destroy(state)
```

## Store vs. Signal

| | `Flux.signal(table)` | `Flux.store(table)` |
| :--- | :--- | :--- |
| **Granularity** | Whole table | Per-key and per-level |
| **Read / write syntax** | `state().health` / `state(newTable)` | `state.health` / `state.health = 90` |
| **Nested tables & arrays** | Not tracked individually | Lazily proxied and tracked |
| **Best for** | Small immutable records replaced as a unit | Nested state trees, player data, inventories |
