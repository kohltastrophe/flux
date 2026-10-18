---
title: Async
description: Managing asynchronous operations, loading states, and race conditions in Flux.
outline: deep
sidebar_position: 10
---

# Async

`Flux.async` runs yielding work (`DataStore` requests, HTTP fetches, `Players:GetNameFromUserIdAsync`) off the reactive graph and exposes its progress as four reactive nodes, discarding stale responses automatically when inputs change rapidly.

```luau
local currentUserId = Flux.signal(1)

local profile = Flux.async(currentUserId, function(userId)
	return Players:GetNameFromUserIdAsync(userId)
end)

local label = Flux.new "TextLabel" {
	Text = function()
		if profile.loading() then
			return "Loading..."
		elseif profile.error() then
			return `Error: {profile.error()}`
		end
		return `Player: {profile.data() or "None"}`
	end,
}
```

## Creating an Async Node

Call `Flux.async(source, fetcher, initialValue?)` (or `Flux.async(fetcher, initialValue?)` for a one-shot fetch with no reactive source):

1. **`source`** *(optional)*: A reactive Node or `() -> S` getter. Whenever `source` changes to a truthy value, `fetcher` runs on a spawned thread. When `source` is `nil` or `false`, the fetch is gated off until `source` becomes truthy.
2. **`fetcher(value, previous, refetching)`**: The yielding callback. It receives `source`'s current `value`, the `previous` resolved `.data`, and `refetching` (`false` on automatic runs, or the argument passed to `:refetch(info)`). The fetcher runs [untracked](/guide/concepts/tracking); declare all reactive inputs via `source`.
3. **`initialValue`** *(optional)*: Starting value for `.data` before the first fetch resolves.

```luau
-- Multiple inputs: combine them in a getter source
local leaderboard = Flux.async(
	function()
		return { region = region(), page = page() }
	end,
	function(query)
		return fetchPageAsync(query.region, query.page)
	end
)
```

## Reading Async State

An `Async<T>` resource exposes four reactive [Nodes](/guide/concepts/signals):

| Node | Type | Description |
| :--- | :--- | :--- |
| **`async.data`** | `Node<T?>` | Latest resolved value (or `initialValue` before first resolution) |
| **`async.loading`** | `Node<boolean>` | `true` while a fetch is in flight |
| **`async.error`** | `Node<string?>` | Error string (`tostring(err)`) if the last fetch threw, else `nil` |
| **`async.state`** | `Node<AsyncState>` | `"unresolved"` \| `"pending"` \| `"refreshing"` \| `"ready"` \| `"errored"` |

> [!TIP] Switching on `async.state`
> Pair `async.state` with [`Flux.switch`](/guide/concepts/conditionals#switching-between-many-branches) to mount dedicated views for `"pending"`, `"errored"`, and `"ready"` states.

## Automatic Race Condition Handling

Each fetch increments an internal request ID. If `source` changes while an older request is still yielding, only the most recent request's result is written to `.data` or `.error` when it finishes; outdated responses are silently ignored.

## Refetching and Mutating

- **`async:refetch(info?)`** re-runs `fetcher` with the current `source` value without writing to `source`. `info` is passed as the third argument (`refetching`) to `fetcher` (defaulting to `true`).
- **`async:mutate(value)`** writes `value` directly to `.data`, clears `.error` and `.loading`, and invalidates any in-flight request so a slow response cannot overwrite the optimistic update.

```luau
local retryButton = Flux.new "TextButton" {
	Text = "Retry",
	Activated = function()
		profile:refetch()
	end,
}
```

## Cleaning Up

Created inside a [`Flux.scope`](/guide/concepts/scopes), an `Async` resource is destroyed automatically with the scope. To tear down an unowned resource manually, call `async:Destroy()`, which cancels any in-flight fetch and disposes its internal nodes.
