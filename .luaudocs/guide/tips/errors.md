---
title: Error Handling
description: Managing errors and keeping the reactive graph resilient in Flux.
outline: deep
sidebar_position: 2
---

# Error Handling

Unhandled errors inside reactive computations or async tasks can interrupt UI updates if not contained. Flux provides [`Flux.safe`](#structured-error-handling-flux-safe) for reactive error boundaries, built-in error containment in [`Flux.async`](#asynchronous-errors) and [Effects](#reactive-graph-errors), and deterministic teardown via [Scopes](#scope-safety).

## Structured Error Handling (`Flux.safe`{luau}) {#structured-error-handling-flux-safe}

`Flux.safe(tryFn, fallback, equals?)`{luau} wraps a computation in a self-healing reactive error boundary. It returns a [Computed](/guide/concepts/computeds) node that evaluates `tryFn`{luau}; if `tryFn`{luau} throws, it returns `fallback`{luau} (either a static value or a `function(err)`{luau} handler):

```luau
local HttpService = game:GetService("HttpService")
local rawJson = Flux.signal('{"malformed JSON')

local parsed = Flux.safe(function()
    return HttpService:JSONDecode(rawJson())
end, function(err)
    warn("JSON parse failed:", err)
    return nil
end)

print(parsed()) -- nil (after warning)

-- Self-healing: fixing `rawJson` automatically re-evaluates `parsed`
rawJson('{"ok": true}')
print(parsed().ok) -- true
```

Any reactive dependencies read before `tryFn`{luau} threw are still tracked, so updating `rawJson`{luau} automatically re-runs `parsed`{luau} and recovers cleanly.

> [!NOTE]
> The `fallback`{luau} handler itself runs **untracked** so fallback logging or recovery reads never subscribe the computation to unintended dependencies.

## Asynchronous Errors

[`Flux.async`](/guide/concepts/async) automatically runs its task inside `pcall`{luau}. If the task throws, the error is captured into the `.error`{luau} node and `.loading`{luau} settles to `false`{luau} without crashing the thread:

```luau
local userId = Flux.signal(123)

local profile = Flux.async(userId, function(id)
    local raw = game:GetService("HttpService"):GetAsync(`https://api.example.com/users/{id}`)
    return game:GetService("HttpService"):JSONDecode(raw)
end)

local statusLabel = Flux.new "TextLabel" {
    Text = function()
        if profile.error() then
            return `Error: {profile.error()}`
        elseif profile.loading() then
            return "Loading..."
        end
        local data = profile.data()
        return if data then data.username else "No data"
    end,
}
```

## Reactive Graph Errors

Flux isolates failures across the graph so one broken node never corrupts the rest of the frame:

- **Computeds:** If an unprotected Computed throws, Flux caches the error and re-throws it to the caller reading it while keeping the graph state consistent. When one of the dependencies read before the error changes, the Computed automatically re-evaluates and heals if the new run succeeds.
- **Effects:** If an [Effect](/guide/concepts/effects) throws during a flush, Flux logs a warning (`[Flux] suppressed effect error:`{luau}) and continues flushing all remaining queued effects. If a cleanup registered with `Flux.cleanup`{luau} throws, Flux warns and continues running the remaining cleanups.
- **Runaway Loop Protection:** If a self-triggering Effect re-queues itself more than `100`{luau} times in a single flush, Flux warns and disposes that offending Effect so the frame never hangs.

## Scope Safety

Calling `:Destroy()`{luau} on a [Scope](/guide/concepts/scopes) (or passing items to [`Flux.dispose`](/guide/concepts/scopes#disposing-by-hand-with-flux-dispose)) is resilient to errors: even if one cleanup callback throws, Flux logs a warning and finishes tearing down every remaining instance, connection, and child scope.
