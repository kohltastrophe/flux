---
title: Effects
description: Managing side effects and Heartbeat-deferred execution in Flux.
outline: deep
---

# Effects

While **Signals** and **Computeds** are designed to hold and derive state, **Effects** are designed to _act_ upon it.

An Effect is a reactive observer that runs a function whenever its tracked dependencies change. Effects are designed for side-effectful work (logging, network requests, audio, or driving non-reactive Roblox instances) and, like property bindings, are batched to Roblox's render cycle.

## Creating an Effect

You create an Effect implicitly by calling the main `Flux` function, passing your callback as the first argument and `true`{luau} as the second argument to mark it as an Effect, or explicitly by using `Flux.effect`{lua}.

Just like Computeds, Effects automatically track any Signals or Computeds read inside their execution context. An Effect returns a Node, but unlike a Signal or Computed you normally don't read from it: it exists for its side effects. Like a Computed, an Effect also receives its own previous return value as its function's first argument (see [Reading the Previous Value](/guide/concepts/computeds#reading-the-previous-value)).

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

local count = Flux(0)

-- Create an effect implicitly by passing the function and `true`
Flux(function()
    -- Runs once on the next flush, then again whenever 'count' changes.
    -- `.. count` automatically reads the node's current value; you could
    -- also write `count()` for the same result.
    print("The current count is: " .. count)
end, true)

-- The explicit form does exactly the same thing
Flux.effect(function()
    print("The current count is: " .. count())
end)

count(1) -- Triggers the effects to queue and run again
```

## Heartbeat Deferral and Flushing

In game development, changing state multiple times in a single script execution cycle can bottleneck performance if the UI or logic reacts instantly to every single mutation.

To solve this, Flux Effects are **deferred by default**.

When a dependency changes, the Effect is not executed immediately. Instead, at the end of the current frame, tied to `RunService.Heartbeat`{lua}, Flux **flushes** the queue and runs the Effect once with the final state.

This mechanism ensures batched updates. If a Signal is updated fifty times in a single `while` loop, your Effect will run _once_ at the end of the frame with the most recent value.

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

## Cleanup with `Flux.cleanup`{lua}

Effects often set up resources (connections, timers, or highlighted objects) that need to be torn down before the Effect re-runs with new state. Use `Flux.cleanup`{lua} inside an Effect to register a teardown callback. It fires right before the next re-execution of the Effect.

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
        Flux.cleanup(function()
            highlight:Destroy()
        end)
    end
end, true)
```

Remember that Effects are batched: the Effect above queues on each write but only runs once per flush, with the **final** value. If you change `selected` several times in one frame, no intermediate `SelectionBox` is ever created; only the last value's highlight is built when the queue flushes.

To watch the cleanup fire across distinct states, let each write reach the Effect on its own, either across separate frames or by flushing the queue between writes (handy in tests; see [Testing](/guide/tips/testing)):

```luau
selected(workspace.SomePart)
Flux.flush() -- runs the Effect now: creates a SelectionBox

selected(workspace.AnotherPart)
Flux.flush() -- destroys the old SelectionBox, creates a new one

selected:set(nil)
Flux.flush() -- destroys the last SelectionBox; the Effect runs but does nothing
```

> [!NOTE]
> `selected:set(nil)`{luau} uses the explicit method because calling a node with `nil`{luau} is a read, not a write. See [Signals](/guide/concepts/signals#updating-a-signal).

`Flux.cleanup`{lua} must run inside a reactive owner: a Computed or Effect body, or a [`Flux.scope`](/guide/concepts/scopes). Called at the top level, with no owner, it throws an error.

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

- You need to synchronize reactive state with an external system.
- The function does _not_ return a meaningful value.
- You are performing a side effect that benefits from Heartbeat batching.

```luau
-- GOOD: side effect interacting with a non-reactive system
Flux(function()
    workspace.IndicatorPart.Color = if isReady() then Color3.new(0, 1, 0) else Color3.new(1, 0, 0)
end, true)
```

By keeping pure calculations in Computeds and side effects in Effects, your Flux code stays predictable, performant, and aligned with the Roblox rendering pipeline.

## Effects vs. `Flux.listen`{lua}

An Effect reacts to state from _inside_ the reactive graph. When a system _outside_ the graph needs to react to a node (a non-Flux module, a service wrapper, an analytics hook), use `Flux.listen`{lua} to subscribe a plain callback to a node. It returns a disconnect function.

```luau
local volume = Flux(0.5)

local function applyReverb(level)
    SoundService.AmbientReverb = level > 0.8 and "BigHall" or "NoReverb"
end

-- Flux.listen invokes the callback with the current value on the next flush
-- after subscribing, then again on every change -- no need to seed it yourself.
local disconnect = Flux.listen(volume, applyReverb)

-- Later, when no longer needed:
disconnect()
```

A few things to keep in mind:

- **It fires with the current value on the next flush, then on each update.** The callback runs once with the node's current value on the flush after you subscribe, then again whenever the value changes, so you don't need to seed it yourself.
- **Each callback runs on its own thread** (via `task.spawn`{lua}), so callbacks may yield freely without blocking each other, but they are not synchronous with the change.
- **For synchronous, in-graph reactions, prefer an Effect.** `Flux.listen`{lua} is for bridging _out_ to non-Flux systems; an Effect is the right tool when one node should drive another part of the reactive graph.
