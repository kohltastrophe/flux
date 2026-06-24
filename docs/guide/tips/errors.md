---
title: Error Handling
description: Managing errors and preventing reactive graph interruptions in Flux.
outline: deep
---

# Error Handling

In reactive systems, errors require attention. Because Flux automatically triggers Computeds, Effects, and UI property bindings in response to state changes, an unhandled error inside one of these can halt an execution thread or leave the UI in an inconsistent state.

Where web libraries like SolidJS use [`<ErrorBoundary>`{ts}](https://docs.solidjs.com/reference/components/error-boundary), Flux gives you `Flux.safe`{lua} and `Flux.catch`{lua} for structured recovery, backed by Luau's native `pcall`{luau} and reactive node patterns for everything else.

## Structured Error Handling: `Flux.safe`{lua} and `Flux.catch`{lua}

`Flux.safe`{luau} wraps a computation in an error boundary. It evaluates its first function; if that throws, it serves a **fallback** instead of letting the error escape. The fallback can be a plain value or a function that receives the error:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

local raw = Flux('{"malformed JSON')

-- A computed that can't break the graph: on a parse error it yields the fallback
local parsed = Flux.safe(function()
    return game:GetService("HttpService"):JSONDecode(raw())
end, function(err)
    warn("parse failed:", err)
    return nil -- fallback value
end)
```

`Flux.safe`{lua} returns an ordinary [Computed](/guide/concepts/computeds) node: bind it, read it, derive from it like any other. It is **self-healing**: the reads the protected function performs before it throws are still tracked as dependencies, so when one of them changes the boundary re-evaluates and recovers automatically. (It also takes an optional `equals` comparator as a third argument, like `Flux.computed`{lua}.)

`Flux.catch`{lua} is the one-shot, non-reactive form: a try/handler that runs immediately and returns a value, useful inside a larger body:

```luau
local label = Flux(function()
    local id = userId() -- tracked: label re-runs whenever userId changes
    local name = Flux.catch(function()
        return riskyLookup(id)
    end, function()
        return "Unknown"
    end)
    return "Player: " .. name
end)
```

Both functions you pass to `Flux.catch`{lua} (the protected function and the handler) run **untracked**, so reads inside them never subscribe the surrounding computation. Reads in the enclosing body, like `userId()` above, track normally, so `label` still re-runs when `userId` changes. If the handler itself throws, the error propagates.

> [!TIP]
> Use `Flux.safe`{lua} when you want a reactive node that recovers and re-evaluates on its own; use `Flux.catch`{lua} for a local, immediate try/handler inside another computation.

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

> [!NOTE]
> Setting `jsonError` from inside the Computed is a side effect. It is fine here (the write is idempotent and gives the error its own node for several bindings to read), but when you only need a value-or-fallback, `Flux.safe`{lua} recovers **purely**, without writing to a separate node.

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

`Flux.async`{lua} handles this for you automatically. The wrapper runs your fetcher inside `pcall`{luau}; if it throws, the error message is placed into the `.error` node and the game remains stable. You never need to wrap `Flux.async`{lua} in a `pcall`{luau} yourself.

```luau
local userId = Flux(123)

local profileData = Flux.async(userId, function(id)
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

If an [Effect](/guide/concepts/effects)'s body throws while the queue flushes, Flux catches it, prints a traceback via `warn`{luau}, and keeps flushing the remaining effects so a single failing effect can't strand the rest of the frame.

A throwing [Computed](/guide/concepts/computeds) instead **propagates** the error to whoever reads it. Wrap reads that may fail in [`Flux.safe` or `Flux.catch`](#structured-error-handling-flux-safe-and-flux-catch) to recover with a fallback value.

> [!WARNING]
> In normal mode, Flux does **not** detect dependency cycles: a node that reads or writes itself, directly or through a cycle of nodes, recurses until the stack overflows. [Strict mode](/guide/tips/strict) catches cycles and raises a clear error instead, one more reason to develop with it on. Either way, structure your graph so a node never depends on its own output.

## Scope Safety

Sometimes an unexpected error leaves a component in a broken state. If you built that system with a **Scope**, you have a failsafe: calling `:Destroy()`{luau} on the scope still wipes all instances, disconnects all signals, and frees all memory, even if the internal reactive graph errored out.

```luau
local roundScope = Flux.scope(function()
    -- … complex, potentially error-prone UI generation …
end)

local function endRound()
    -- Guaranteed cleanup regardless of internal errors
    roundScope:Destroy()
end
```

By anticipating failure points with `pcall`{luau} and relying on Scopes for memory safety, localized errors can't cascade into memory leaks or frozen interfaces.
