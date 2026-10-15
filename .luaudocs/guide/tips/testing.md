---
title: Testing
description: Writing deterministic tests for Flux state, animations, timers, and UI components.
outline: deep
sidebar_position: 4
---

# Testing

Flux is designed for fast, deterministic testing: components are plain functions, state lives in standalone nodes, and [`Flux.Clock`](#virtual-time-with-flux-clock) lets you step animations, timers, and effects frame-by-frame with zero real-time waits.

## Deterministic Effects with `Flux.flush()`{luau} {#deterministic-effects-with-flux-flush}

Because [Effects](/guide/concepts/effects) and property bindings batch their updates to the end of the frame, call `Flux.flush()`{luau} in synchronous unit tests to run all queued effects immediately:

```luau
local count = Flux.signal(0)
local label = Flux.new "TextLabel" {
    Text = function()
        return `Count: {count()}`
    end,
}

-- Initial property value is applied synchronously on creation
assert(label.Text == "Count: 0")

count(5)
Flux.flush() -- flush pending effects and property bindings now

assert(label.Text == "Count: 5")
```

## Virtual Time with `Flux.Clock`{luau} {#virtual-time-with-flux-clock}

`Flux.Clock`{luau} is the single source of time for Flux's scheduler, animations ([`Flux.spring`](/guide/motion/spring), [`Flux.tween`](/guide/motion/tween)), and [`Flux.presence`](/guide/concepts/conditionals#animating-exits-with-presence).

In production on Roblox, `Flux.Clock`{luau} delegates directly to `os.clock()`{luau}, `workspace:GetServerTimeNow()`{luau}, `task.*`{luau}, and `RunService`{luau}. In tests (or headless Luau, which is always in manual mode), enable manual mode with `Flux.Clock.manual(true)`{luau} so time advances only when you call `Flux.Clock.step(seconds)`{luau}:

```luau
local Clock = Flux.Clock
Clock.manual(true)

local x = Flux.spring(0, 4, 1)
x(100)

-- Advance 0.5 seconds in 1/60s frames (steps springs, tweens, timers, and flushes effects)
Clock.step(0.5)
assert(x() > 50 and x() < 100)

-- Advance another 1.5 seconds until settled at rest
Clock.step(1.5)
assert(x() == 100)

Clock.reset() -- clear any pending timers/waits/deferred tasks between tests
```

### `Flux.Clock` API

| Function                                      | Description                                                                                             |
| :-------------------------------------------- | :------------------------------------------------------------------------------------------------------ |
| `Clock.now()`{luau}                           | Monotonic time in seconds (`os.clock()`{luau} live, virtual clock in manual mode).                      |
| `Clock.wall()`{luau}                          | Synchronized Unix timestamp (`GetServerTimeNow()`{luau} live, `2026-01-01T00:00:00Z + now`{luau} manual). |
| `Clock.delay(seconds, fn, ...)`{luau}         | Schedules `fn`{luau} after `seconds`{luau} (`task.delay`{luau} live, virtual heap in manual mode).      |
| `Clock.wait(seconds?)`{luau}                  | Yields the current coroutine for `seconds`{luau} and returns elapsed time.                              |
| `Clock.defer(fn, ...)`{luau}                  | Defers `fn`{luau} to the end of the current resumption cycle (`task.defer`{luau} live).                 |
| `Clock.cancel(thread)`{luau}                  | Cancels a thread scheduled with `Clock.delay`{luau} or `Clock.defer`{luau}.                             |
| `Clock.connect(phase, fn)`{luau}              | Connects `fn(dt)`{luau} to `"PreRender"`{luau}, `"RenderStepped"`{luau}, or `"Heartbeat"`{luau}.        |
| `Clock.manual(enabled)`{luau}                 | Switches between the live Roblox engine clock (`false`{luau}) and the manual virtual clock (`true`{luau}). |
| `Clock.isManual()`{luau}                      | Returns `true`{luau} when the clock is in manual mode.                                                  |
| `Clock.step(seconds, frameLength?)`{luau}     | Advances manual time by `seconds`{luau} in slices of at most `frameLength`{luau} (default `1/60`{luau}). |
| `Clock.drain()`{luau}                         | Runs all pending `Clock.defer`{luau} callbacks immediately in FIFO order.                               |
| `Clock.reset()`{luau}                         | Cancels all pending manual timers, waits, deferred calls, and manual frame listeners between tests.     |

Each manual frame of `dt`{luau} seconds executes in deterministic engine order:
1. Advances `now`{luau} by `dt`{luau} and wakes due `delay`{luau} and `wait`{luau} threads in deadline order.
2. Fires `"PreRender"`{luau} and `"RenderStepped"`{luau} listeners with `dt`{luau}.
3. Steps all active springs and tweens by `dt`{luau} (`Flux.Motion.step(dt)`{luau}) and runs `Flux.flush()`{luau}.
4. Fires `"Heartbeat"`{luau} listeners with `dt`{luau}.
5. Drains `Clock.defer`{luau} queues between each phase.

> [!TIP]
> If you want to advance springs and tweens in isolation without stepping timers or `Clock` listeners, call `Flux.Motion.step(dt)`{luau} followed by `Flux.flush()`{luau} directly.

## Isolating Tests with Scopes

Wrap each test body in [`Flux.scope`](/guide/concepts/scopes) and destroy the scope at the end of the test so effects, animations, and instances never leak between test cases:

```luau
local scope = Flux.scope(function()
    local count = Flux.signal(0)
    local doubled = Flux.computed(function()
        return count() * 2
    end)

    assert(doubled() == 0)
    count(5)
    assert(doubled() == 10)
end)

scope:Destroy()
```

## Headless & Full-Engine Tests in CI {#full-engine-tests-in-ci}

The reactive core (`Flux.signal`{luau}, `Flux.computed`{luau}, `Flux.effect`{luau}, `Flux.scope`{luau}, `Flux.store`{luau}, `Flux.Clock`{luau}, `Flux.Color`{luau}) and most motion datatypes (`number`{luau}, `vector`{luau}, `UDim`{luau}, `UDim2`{luau}, `Vector2`{luau}, `Vector3`{luau}, `Color3`{luau}, `NumberSequence`{luau}, `ColorSequence`{luau}) run directly in the standalone `luau`{luau} CLI via built-in compatibility shims.

For tests that create Roblox `Instance`{luau}s or use full-engine APIs (`CFrame`{luau}, `Rect`{luau}, `NumberRange`{luau}, `CollectionService`{luau}, input, and layout geometry), build a test place with [Rojo](https://rojo.space/) and run the suite in Roblox Studio or in CI via the [Open Cloud Luau Execution API](https://create.roblox.com/docs/cloud/guides/luau-execution).
