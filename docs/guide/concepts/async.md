---
title: Async
description: Managing asynchronous operations, loading states, and race conditions in Flux.
outline: deep
---

# Async

In reactive applications, asynchronous operations like [`DataStore`](https://create.roblox.com/docs/en-us/reference/engine/classes/DataStoreService) requests, fetching player thumbnails, or HTTP calls take work to manage. You have to track loading states, handle errors, and ensure that if a user changes their input quickly, the application doesn't render an outdated, delayed response.

**Flux.async** wraps yielding operations in a reactive container. If you are familiar with SolidJS, this is the equivalent of [createResource](https://docs.solidjs.com/guides/fetching-data).

## Creating an Async Node

To create an asynchronous reactive node, you use `Flux.async`{lua}; created inside a [Scope](/guide/concepts/scopes), it is torn down with that scope. It takes three arguments:

1. **Source:** The tracked input: a reactive node, or a function that reads reactive state like a computed body. Whenever it changes, the fetcher re-runs with its new value. If it reads `nil`{luau} or `false`{luau}, the fetch is gated off until the source turns truthy, handy for deferring work until a prerequisite exists.
2. **Fetcher:** The function that performs the yielding work (e.g., calling `:GetAsync()`{luau} or `task.wait`{luau}). It is called as `fetcher(value, previous, refetching)`{luau}: the source's current `value`, the `previous` resolved data (handy for pagination or accumulation), and a `refetching` flag: `false`{luau} on an automatic source-driven run, or the payload passed to [`:refetch`](#refetching-and-mutating). **Nothing the fetcher reads is tracked**. All of its reactive inputs must arrive through the source.
3. **Initial Value** _(Optional)_: A starting value to hold in `.data` before the very first fetch completes.

> [!TIP] Dependencies are explicit
> Reactive functions in Flux must be synchronous, so the yielding fetcher can never be tracked itself. Instead, the source declares exactly what the fetch depends on, visible at the call site, with no "which reads happened before the yield?" ambiguity.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

-- A reactive Signal holding the target User ID
local currentUserId = Flux(1)

-- Create the Async resource
local profileData = Flux.async(
    -- SOURCE: tracked; a change here re-runs the fetcher
    currentUserId,

    -- FETCHER: untracked; receives the source's current value
    function(userId)
        -- Imagine yielding to a DataStore or external API here
        task.wait(1)

        return { name = "Player_" .. userId, level = userId * 10 }
    end,

    -- Initial Value
    nil
)
```

If the fetch needs several reactive inputs, derive them in a function source: `Flux.async(function() return { id = currentUserId(), realm = currentRealm() } end, fetcher)`{luau}.

For a one-shot fetch with no reactive input, omit the source entirely and pass the fetcher first: `Flux.async(function() return HttpService:GetAsync(url) end, initialValue)`{luau}.

## Reading Async State

The object returned by `Flux.async`{lua} contains four reactive properties, which are all standard Flux nodes. You can bind these directly to your UI to conditionally render loading spinners, error messages, or the final data.

- **`data`**: Holds the result of the async function. (Defaults to the `initialValue` or `nil`{luau} until resolved).
- **`loading`**: A boolean node that is `true`{luau} while the fetcher is yielding.
- **`error`**: Holds the error message (a string) if the fetcher throws; the thrown value is passed through `tostring`{luau}. Otherwise `nil`{luau}.
- **`state`**: A string node holding the lifecycle state, derived from `error`/`loading` and whether a fetch has resolved: `"unresolved"`{luau} (nothing fetched yet), `"pending"`{luau} (first fetch in flight, no value), `"refreshing"`{luau} (fetch in flight over an existing value), `"ready"`{luau} (resolved), or `"errored"`{luau} (last fetch threw).

```luau
local new = Flux.new

local ui = new "TextLabel" {
    Name = "ProfileCard",
    Size = UDim2.fromOffset(300, 100),

    -- Bind a function to conditionally render based on the Async state
    Text = function()
        if profileData.loading() then
            return "Loading profile..."
        end

        if profileData.error() then
            return "Failed to load: " .. profileData.error()
        end

        local data = profileData.data()
        if data then
            return `Name: {data.name} | Level: {data.level}`
        end

        return "No data available."
    end
}
```

The `.. profileData.error()`{luau} concatenation reads the node's current value automatically (see [Signals](/guide/concepts/signals)). It's guarded by the preceding `if profileData.error() then`{luau} check, so it only runs once we know the error is a non-`nil`{luau} string.

> [!TIP] Render one branch per state
> `state`{luau} collapses the loading/error/data combination into a single value, so it pairs naturally with [`Flux.switch`](/guide/concepts/conditionals#switching-between-many-branches): one UI branch per state, with [`Flux.default`](/guide/concepts/conditionals#a-default-branch) as the catch-all.

## Automatic Race Condition Handling

`Flux.async`{lua} handles race conditions for you.

If your dependencies change rapidly (for example, if a player rapidly clicks through a list of User IDs), the `Async` node will spawn multiple fetch requests. However, Flux internally tracks the ID of every request.

If an older request finally resolves _after_ a newer request has already started, the outdated data is completely ignored. Your `.data` and `.error` nodes will only ever update with the result of the _most recent_ request, ensuring your UI state is never polluted by slow, out-of-date network responses.

## Refetching and Mutating

The object returned by `Flux.async`{lua} exposes two methods for driving it imperatively, mirroring SolidJS's `refetch` and `mutate`.

**`resource:refetch(info?)`{luau}** re-runs the fetcher with the source's _current_ value, without writing the source; the optional `info` reaches the fetcher as its `refetching` argument (defaulting to `true`{luau}). It's exactly what a "Retry" button needs, or a manual "pull to refresh":

```luau
local profile = Flux.async(currentUserId, fetchProfile)

local retryButton = new "TextButton" {
    Text = "Retry",
    Activated = function()
        profile:refetch()
    end,
}
```

Refetch honors the same race handling as an automatic re-fetch: if a previous request is still in flight, its result is discarded in favor of the new one.

**`resource:mutate(value)`{luau}** optimistically writes `.data` immediately, without running the fetcher, useful for reflecting a local change in the UI before (or instead of) a round-trip. It also invalidates any in-flight fetch, so a slow request that resolves afterward won't overwrite your optimistic value:

```luau
-- Show the new name instantly, then persist in the background
local function rename(newName)
    profile:mutate({ name = newName, level = profile.data().level })
    saveNameToServer(newName) -- if this later refetches, it wins; the stale one is dropped
end
```

> [!NOTE]
> Both methods are safe to call after the resource has been destroyed; they become no-ops rather than erroring.

## Cleaning Up

If an Async node is no longer needed, you can completely destroy it to free up memory and destroy its internal `data`, `loading`, `error`, and `state` nodes.

```luau
profileData:Destroy()
```

_Note: Created inside a [`Flux.scope`](/guide/concepts/scopes), the resource is destroyed when that scope is destroyed, so you don't have to clean it up yourself._
