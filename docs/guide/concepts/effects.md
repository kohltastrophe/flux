---
title: Effects
description: Managing side effects and Heartbeat-deferred execution in Flux.
outline: deep
---

# Effects

While **Values** and **Computeds** are designed to hold and derive state, **Effects** are designed to _act_ upon it.

An Effect is a reactive observer that runs a function whenever its tracked dependencies change. Unlike property bindings which update immediately, Effects are optimised for side-effectful work like logging, network requests, audio, or interacting with non-reactive Roblox instances, and are batched to Roblox's render cycle.

If you are coming from other frameworks, you can think of Effects as `createEffect` or `useEffect`.

## Creating an Effect

You create an Effect implicitly by calling the main `Flux` function, passing your callback as the first argument and `true`{lua} as the second argument to mark it as an Effect, or explicitly by using `Flux.effect`{lua}.

Just like Computeds, Effects automatically track any Values or Computeds read inside their execution context.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

local count = Flux(0)

-- Create an effect implicitly by passing the function and `true`
Flux(function()
    -- Prints immediately once, then again whenever 'count' changes
    print("The current count is: " .. count)
end, true)

count(1) -- Triggers the effect to queue and run again
```

## Heartbeat Deferral and Flushing

In game development, changing state multiple times in a single script execution cycle can bottleneck performance if the UI or logic reacts instantly to every single mutation.

To solve this, Flux Effects are **deferred by default**.

When a dependency changes, the Effect is not executed immediately. Instead, at the end of the current frame, tied to `RunService.Heartbeat`{lua}, Flux **flushes** the queue and runs the Effect once with the final state.

This mechanism ensures batched updates. If a Value is updated fifty times in a single `while` loop, your Effect will run _once_ at the end of the frame with the most recent value.

```luau
local count = Flux(0)

Flux(function()
    print("Effect ran! Count is " .. count)
end, true)

-- These updates happen in the same frame
count(1)
count(2)
count(3)

-- > "Effect ran! Count is 3" prints on the next Heartbeat.
-- The intermediate states (1 and 2) are skipped entirely.
```

## Cleanup with `Flux.onCleanup`{lua}

Effects often set up resources (connections, timers, or highlighted objects) that need to be torn down before the Effect re-runs with new state. Use `Flux.onCleanup`{lua} inside an Effect to register a teardown callback. It fires right before the next re-execution of the Effect.

```luau
local selected = Flux(nil) -- holds the currently selected Part

Flux(function()
    local part = selected()

    if part then
        -- Highlight the selected part
        local highlight = Instance.new("SelectionBox")
        highlight.Adornee = part
        highlight.Parent = workspace

        -- Remove the highlight before this Effect re-runs (i.e., before selection changes)
        Flux.onCleanup(function()
            highlight:Destroy()
        end)
    end
end, true)

selected(workspace.SomePart)   -- creates a SelectionBox
selected(workspace.AnotherPart) -- destroys the old SelectionBox, creates a new one
selected(nil)                   -- destroys the last SelectionBox; effect runs but does nothing
```

`Flux.onCleanup`{lua} may only be called from within a reactive function (a Computed or Effect body). Calling it at the top level will throw an error.

## Effects vs. Computeds

Because both `Flux(effectFn, true)`{luau} and `Flux(computeFn)`{luau} automatically track dependencies, it can be easy to confuse when to use which.

The distinction is **Side Effects** vs. **Pure Calculations**:

### Use `Flux(computeFn)`{luau} when:

- You need to derive new data from existing state.
- The function returns a value.
- The function is _pure_; it does not mutate other state, interact with external systems, or touch the UI manually.
- You want the result to be lazily evaluated only when read.

```luau
-- GOOD: pure calculation returning a derived value
local doubled = Flux(function()
    return count * 2
end)
```

### Use an Effect `Flux(effectFn, true)`{luau} when:

- You need to synchronise reactive state with an external system.
- The function does _not_ return a meaningful value.
- You are performing a side effect that benefits from Heartbeat batching.

```luau
-- GOOD: side effect interacting with a non-reactive system
Flux(function()
    workspace.IndicatorPart.Color = if isReady() then Color3.new(0, 1, 0) else Color3.new(1, 0, 0)
end, true)
```

By keeping pure calculations in Computeds and side effects in Effects, your Flux architecture remains predictable, performant, and perfectly aligned with the Roblox rendering pipeline.
