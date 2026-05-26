---
title: Error Handling
description: Managing errors and preventing reactive graph interruptions in Flux.
outline: deep
---

# Error Handling

In highly reactive systems, errors require special attention. Because Flux automatically triggers Computeds, Effects, and UI property bindings in response to state changes, an unhandled error inside one of these can halt an execution thread or leave the UI in an inconsistent state.

While web frameworks like SolidJS use concepts like [`<ErrorBoundary>`{ts}](https://docs.solidjs.com/reference/components/error-boundary), Flux relies on Luau's native error handling paradigms combined with reactive state patterns.

## Synchronous Errors (`pcall`{luau})

If you are performing a risky synchronous operation inside a Computed, an Effect, or a UI property binding, such as deep-indexing a table that might be `nil`{luau}, or parsing user input, use Luau's [`pcall`{luau}](https://create.roblox.com/docs/en-us/reference/engine/globals/LuaGlobals#pcall) to prevent the error from breaking the reactive update cycle.

Combine `pcall`{luau} with a dedicated error state node to build reactive fallbacks.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

local rawData  = Flux('{"malformed JSON')
local jsonError = Flux(nil :: string?)

local parsedData = Flux(function()
    local success, result = pcall(function()
        return game:GetService("HttpService"):JSONDecode(rawData())
    end)

    if not success then
        jsonError(tostring(result)) -- surface the error reactively
        return nil
    end

    jsonError(nil)
    return result
end)
```

## Handling Errors in the UI

Once you have a reactive node representing an error state, bind it directly in your `Flux.new`{lua} declarations to conditionally render error messages or fallback UIs.

```luau
local dataPanel = new "Frame" {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(0.1, 0.1, 0.1),

    new "TextLabel" {
        Size = UDim2.fromScale(1, 1),

        Text = function()
            local err = jsonError()
            if err then
                return "Failed to parse: " .. err
            end
            local data = parsedData()
            return data and "Data loaded!" or "Waiting for data…"
        end,

        TextColor3 = function()
            return jsonError() and Color3.new(1, 0.2, 0.2) or Color3.new(1, 1, 1)
        end,
    },
}
```

## Asynchronous Errors

Handling errors is most important when dealing with yielding operations like network requests or [`DataStore`](https://create.roblox.com/docs/en-us/reference/engine/classes/DataStoreService) calls.

`Flux.async`{lua} handles this for you automatically. The wrapper runs your function inside `pcall`{luau}; if it throws, the error message is placed into the `.error` node and the game remains stable. You never need to wrap `Flux.async`{lua} in a `pcall`{luau} yourself.

```luau
local userId = Flux(123)

local profileData = Flux.async(function()
    local id = userId()  -- read dependency before any yield

    -- If this throws, profileData.error() will be set;
    -- the thread won't die and the rest of the UI keeps working.
    local raw = game:GetService("HttpService"):GetAsync(`https://api.example.com/users/{id}`)
    return game:GetService("HttpService"):JSONDecode(raw)
end)

local ui = new "TextLabel" {
    Text = function()
        if profileData.error() then
            return "Connection lost. Please try again."
        end
        if profileData.loading() then
            return "Loading…"
        end
        local data = profileData.data()
        return data and data.username or "No data."
    end,
}
```

## Reactive Graph Errors

Flux's graph protects against two common structural problems at runtime:

| Problem                                                                      | How Flux handles it                                                                        |
| :--------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------- |
| **Cyclic write** - a node sets itself (or a cycle of nodes) while evaluating | The `BUSY` state guard raises `"Cyclic write detected"` immediately with a clear traceback |
| **Cyclic read** - a computation depends on itself                            | Raises `"Cyclic read detected"` immediately                                                |

If a Computed or Effect's function throws an unexpected error, Flux catches it with `pcall`{luau}, prints a traceback via `warn`{luau}, and marks the node `DIRTY` so it will retry next time it is read or flushed. The rest of the graph continues running normally.

## Scope Safety

Sometimes an unexpected error leaves a component in a broken state. If you built that system with a **Scope**, you have an ultimate failsafe; calling `:Destroy()`{luau} on the scope still wipes all instances, disconnects all signals, and frees all memory, even if the internal reactive graph errored out.

```luau
local roundScope = Flux.scope()

-- … complex, potentially error-prone UI generation …

local function endRound()
    -- Guaranteed cleanup regardless of internal errors
    roundScope:Destroy()
end
```

By anticipating failure points with `pcall`{luau} and relying on Scopes for memory safety, localised errors can never cascade into game-breaking memory leaks or permanently frozen interfaces.
