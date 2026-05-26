---
title: Async
description: Managing asynchronous operations, loading states, and race conditions in Flux.
outline: deep
---

# Async

In reactive applications, managing asynchronous operations like [`DataStore`](https://create.roblox.com/docs/en-us/reference/engine/classes/DataStoreService) requests, fetching player thumbnails, or HTTP calls can be complicated. You have to track loading states, handle potential errors, and ensure that if a user changes their input quickly, the application doesn't render an outdated, delayed response.

**Flux.async** solves this by wrapping yielding operations in a secure, reactive container. If you are familiar with SolidJS, this is the equivalent of [createResource](https://docs.solidjs.com/guides/fetching-data).

## Creating an Async Node

To create an asynchronous reactive node, you use `Flux.async`{lua} (or `Scope:async`{luau} if you are managing lifecycles via a [Scope](/guide/concepts/scopes)). Because of how Flux tracks dependencies, you only need to provide a single function, but you must follow a strict rule regarding when you read reactive state.

It requires two arguments:

1. **The Asynchronous Function:** The function that performs the yielding work (e.g., calling `:GetAsync()`{luau} or `task.wait`{luau}).
2. **Initial Value (Optional):** A starting value to hold in the state before the very first fetch completes.

> [!CAUTION] ⚠️ The "Read Before Yield" Rule
> Flux tracks dependencies synchronously. When your Async function runs, it executes immediately until it hits its first yield. **You must extract all reactive dependencies at the top of your function, before you yield.** Any reactive nodes read _after_ a yield will not be tracked, and your Async block will not re-run when they change.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

-- A reactive Value holding the target User ID
local currentUserId = Flux(1)

-- Create the Async resource
local profileData = Flux.async(
    function()
        -- 1. READ BEFORE YIELD: Extract reactive state synchronously
        local userId = currentUserId()

        -- 2. YIELD: Perform the async operation
        -- Imagine yielding to a DataStore or external API here
        task.wait(1)

        -- 3. RETURN: Pass back the resolved data
        return { name = "Player_" .. userId, level = userId * 10 }
    end,

    -- Initial Value
    nil
)
```

## Reading Async State

The object returned by `Flux.async`{lua} contains three reactive properties, which are all standard Flux Nodes. You can bind these directly to your UI to conditionally render loading spinners, error messages, or the final data.

- **`data`**: Holds the result of the async function. (Defaults to the `initialValue` or `nil`{lua} until resolved).
- **`loading`**: A boolean Value that is `true`{lua} while the fetcher is yielding.
- **`error`**: A string Value that populates if the fetcher function throws an error (via `pcall`{lua}). Otherwise, it is `nil`{lua}.

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

## Automatic Race Condition Handling

One of the most powerful features of `Flux.async`{lua} is how it handles race conditions.

If your dependencies change rapidly (for example, if a player rapidly clicks through a list of User IDs), the `Async` node will spawn multiple fetch requests. However, Flux internally tracks the ID of every request.

If an older request finally resolves _after_ a newer request has already started, the outdated data is completely ignored. Your `.data` and `.error` nodes will only ever update with the result of the _most recent_ request, ensuring your UI state is never polluted by slow, out-of-date network responses.

## Cleaning Up

If an Async node is no longer needed, you can completely destroy it to free up memory and destroy its internal `data`, `loading`, and `error` nodes.

```luau
profileData:Destroy()
```

_Note: If you create the resource using `Scope:async()`{luau}, it will be automatically destroyed when the Scope is destroyed, keeping your memory management completely hands-off._
