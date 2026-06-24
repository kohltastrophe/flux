---
title: Tracking
description: Controlling dependency tracking with untrack, raw, and read in Flux.
outline: deep
---

# Tracking

Whenever a reactive function runs (a Computed, an Effect, or a property binding), every node it reads is automatically registered as a dependency. That automatic tracking is what makes Flux work, but sometimes you need to opt out of it: peek at a value without subscribing, or write a helper that accepts both nodes and plain values.

> [!CAUTION] Reactive functions must be synchronous
> Computations and effects must not yield (`task.wait`{luau}, `:GetAsync()`{luau}, etc.); move yielding work into [`Flux.async`{lua}](/guide/concepts/async). [Strict mode](/guide/tips/strict) catches an illegal yield and raises a clear error rather than letting it corrupt the flush. And when you start a thread from inside a reactive function, bracket it with `Flux.untrack()`{luau} / `Flux.retrack()`{luau} (see [Imperative pairing](#imperative-pairing-flux-untrack-flux-retrack) below): the child runs synchronously until its first yield, so with a bare `task.spawn`{luau} everything it reads would be captured as dependencies of the calling computation.

Flux exposes five small utilities for this.

## `Flux.untrack`{lua}

Runs a function with dependency tracking suppressed and returns its results. Reads inside the function do not become dependencies of the calling computation.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

local message = Flux("hello")
local timestamp = Flux(0)

Flux(function()
    -- Re-runs when 'message' changes...
    local text = message()

    -- ...but NOT when 'timestamp' changes
    local stamp = Flux.untrack(function()
        return timestamp()
    end)

    print(`[{stamp}] {text}`)
end, true)
```

The function is called with no arguments, and every value it returns passes straight through. If the function throws, the error re-throws after tracking is restored.

> [!NOTE]
> `Flux.cleanup`{luau} still registers on the calling computation inside an untracked block (matching SolidJS's `untrack`{ts}). Never yield inside the untracked function. Suppression is global until the function returns.

## Imperative pairing: `Flux.untrack()`{luau} / `Flux.retrack()`{luau}

Calling `Flux.untrack`{luau} with **no arguments** suppresses tracking imperatively until you call `Flux.retrack()`{luau} (or the computation finishes). The pair is cheaper than the wrapped form (no closure, no protected call) and is how you start threads from inside a reactive function:

```luau
local target = Flux(nil)

Flux(function()
    local destination = target()

    -- The pathfinding call yields, so it can't run inside the effect itself;
    -- the bracket keeps anything the child reads out of the effect's dependencies
    Flux.untrack()
    task.spawn(function()
        walkTo(destination)
    end)
    Flux.retrack()
end, true)
```

Once the child yields, later resumes run outside any reactive context, so post-yield reads are never tracked. If an error escapes between the two calls, suppression ends with the computation, but pair them explicitly; prefer the wrapped `Flux.untrack(fn)`{luau} when an error can be caught and handled mid-computation.

## `Flux.raw`{lua}

Reads a single node without registering a dependency, an untracked "peek". Like `Flux.read`{lua}, non-node values pass through unchanged.

```luau
local health = Flux(100)
local damage = Flux(0)

Flux(function()
    -- Re-runs when 'damage' changes, but not when 'health' changes
    print(`Took {damage()} damage at {Flux.raw(health)} HP`)
end, true)
```

`Flux.raw(node)`{luau} is equivalent to wrapping a single read in `Flux.untrack`{lua}, without the extra function. `node:peek()`{luau} is the method form of `Flux.raw(node)`{luau}, an untracked read of the node's current value.

`Flux.isReactive()`{luau} returns `true`{luau} when called inside a tracking computed or effect body, and `false`{luau} otherwise. Use it when code wants to behave differently depending on whether it is currently being observed.

## `Flux.read`{lua}

Reads a node **with** tracking, or passes a plain value through unchanged. This is the idiomatic way to consume "node or value" inputs, like component props:

```luau
local function StatusLabel(props)
    return new "TextLabel" {
        -- Works whether props.status is a reactive node or a static string
        Text = function()
            return Flux.read(props.status)
        end,
    }
end
```

## `Flux.on`{lua}

By default a computation depends on **everything** it reads. Sometimes you want the opposite: a body that re-runs only when a specific, declared set of inputs changes, while reading other state without subscribing to it. `Flux.on`{lua} (SolidJS's [`on`](https://docs.solidjs.com/reference/reactive-utilities/on)) builds exactly that.

It takes the dependencies, a callback, and a third boolean argument `defer`, then returns a function you pass to `Flux`{lua} / `Flux.computed`{lua} / `Flux.effect`{lua}:

```luau
local a = Flux(1)
local b = Flux(2)

-- Re-runs ONLY when `a` changes. `b` is read untracked inside the body
local sum = Flux(Flux.on(a, function(value, previousValue)
    return value + b()
end))
```

The dependency argument can be a single Node, a **getter function** (called like a SolidJS accessor, so its own reads are tracked), or an array of either. The callback receives the dependency's current value, its previous value, and the previous result; only the declared dependencies are tracked. Everything the callback itself reads is suppressed.

Pass `true`{luau} as the third argument (`defer`) to skip the very first run, so the body fires only on subsequent changes:

```luau
local health = Flux(100)

-- Does NOT run on creation; runs on the first change to `health` and after
Flux.effect(Flux.on(health, function(current, previous)
    print(`health changed from {previous} to {current}`)
end, true))
```

This is the explicit counterpart to automatic tracking: use it when a body reads many things but should only react to a few.

## Summary

| Utility                                         | Registers a dependency? | Accepts                 | Use for                                           |
| :---------------------------------------------- | :---------------------- | :---------------------- | :------------------------------------------------ |
| `Flux.read(value)`{luau}                        | Yes                     | Node or plain value     | Consuming "node or value" inputs (props)          |
| `Flux.raw(value)`{luau}                         | No                      | Node or plain value     | Peeking at state without subscribing to it        |
| `Flux.untrack(fn)`{luau}                        | No                      | Function                | Suppressing tracking across a whole block of code |
| `Flux.untrack()`{luau} … `Flux.retrack()`{luau} | No                      | n/a                     | Hot paths and bracketing `task.spawn`{luau}       |
| `Flux.on(deps, fn, defer)`{luau}                | Declared deps only      | Deps, callback, `defer` | Reacting to a few inputs while reading many       |
