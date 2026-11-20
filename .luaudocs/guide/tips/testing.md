---
title: Testing
description: Writing deterministic tests for Flux state, animations, timers, and UI components.
outline: deep
sidebar_position: 4
---

# Testing

Components in Flux are plain functions, state lives in standalone nodes, and [`Flux.Clock`](#virtual-time-with-flux-clock) steps animations, timers, and effects frame by frame with zero real-time waits.

## Deterministic Effects with `Flux.flush()` {#deterministic-effects-with-flux-flush}

Because [Effects](/guide/concepts/effects) and property bindings batch their updates to the end of the frame, call `Flux.flush()` in synchronous unit tests to run all queued effects right away:

```luau
local count = Flux.signal(0)
local label = Flux.new "TextLabel" {
	Text = function()
		return `Count: {count()}`
	end,
}

-- Initial property value applies synchronously on creation
assert(label.Text == "Count: 0")

count(5)
Flux.flush() -- flush pending effects and property bindings now

assert(label.Text == "Count: 5")
```

## Virtual Time with `Flux.Clock` {#virtual-time-with-flux-clock}

`Flux.Clock` is the shared time source for Flux's scheduler and animations ([`Flux.spring`](/guide/motion/spring), [`Flux.tween`](/guide/motion/tween), including [`Flux.presence`](/guide/concepts/conditionals#animating-exits-with-presence) exit animations that call `done()` when a spring or tween settles).

In Roblox, `Flux.Clock` defaults to live mode and delegates to `os.clock()`, `workspace:GetServerTimeNow()`, `task.*`, and `RunService`; in Roblox tests, switch to manual mode with `Flux.Clock.manual(true)` so time advances only when you call `Flux.Clock.step(seconds)`. Outside Roblox, `Flux.Clock` defaults to manual virtual time right away (call `Flux.Clock.manual(false)` to opt into live `os.clock()`, `os.time()`, and synchronous `Clock.defer` outside Roblox):

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

Clock.reset() -- clear any pending timers, waits, and deferred tasks between tests
```

### `Flux.Clock` API

| Function | Description |
| :--- | :--- |
| **`Clock.now()`** | Monotonic time in seconds (`os.clock()` live, virtual clock in manual mode). |
| **`Clock.wall()`** | Synchronized Unix timestamp (`workspace:GetServerTimeNow()` when available, `os.time()` live outside Roblox, `2026-01-01T00:00:00Z + now` manual). |
| **`Clock.delay(seconds, fn, ...)`** | Schedules `fn` after `seconds` (`task.delay` live, virtual heap in manual mode). |
| **`Clock.wait(seconds?)`** | Yields the current coroutine for `seconds` (default `0`, waking on `Clock.step(0)` in manual mode) and returns elapsed time. |
| **`Clock.defer(fn, ...)`** | Defers `fn` to the end of the current resumption cycle (`task.defer` live, running synchronously when no `task` scheduler exists). |
| **`Clock.cancel(thread)`** | Cancels a thread scheduled with `Clock.delay`, `Clock.defer`, or `Clock.wait`. |
| **`Clock.connect(phase, fn)`** | Connects `fn(dt)` to `"PreRender"`, `"RenderStepped"`, or `"Heartbeat"`. |
| **`Clock.manual(enabled)`** | Switches between the live clock (`false`, default in Roblox) and the manual virtual clock (`true`, default outside Roblox). |
| **`Clock.isManual()`** | Returns `true` when the clock is in manual mode. |
| **`Clock.step(seconds, frameLength?)`** | Advances manual time by `seconds` in slices of at most `frameLength` (default `1/60`). |
| **`Clock.drain()`** | Runs all pending `Clock.defer` callbacks immediately in FIFO order. |
| **`Clock.reset()`** | Cancels all pending manual timers, waits, deferred calls, and manual frame listeners between tests while preserving live listeners connected outside manual mode. |

Each manual frame of `dt` seconds executes in engine order:
1. Advances `now` by `dt` and wakes due `delay` and `wait` threads in deadline order.
2. Fires `"PreRender"` and `"RenderStepped"` listeners with `dt`.
3. Steps all active springs and tweens by `dt` (`Flux.Motion.step(dt)`), runs `Flux.flush()`, and flushes pending [`Flux.Sync`](/guide/concepts/sync) batches.
4. Fires `"Heartbeat"` listeners with `dt`.
5. Drains `Clock.defer` queues between each phase.

To advance springs and tweens in isolation without stepping timers or `Clock` listeners, call `Flux.Motion.step(dt)` followed by `Flux.flush()` directly.

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

The top-level `Flux` package loads directly in standalone `luau` without synthetic Roblox datatype stubs. Signals, stores, control flow, `Flux.Clock`, `Flux.Responsive` defaults, `Flux.Color.Oklab` `vector` helpers, and `number` or `vector` springs and tweens (with plain config tables) run natively on the VM. `Flux.Color` `Color3` helpers, Roblox datatype animations (`UDim2`, `CFrame`, `Rect`, `Color3`, sequences), `Layout` builders, `Interact` helpers, and `Instance` trees require Roblox or [`sert`](https://github.com/kohltastrophe/sert)'s headless test environment.

For tests that create Roblox `Instance`s or exercise engine services (`CollectionService`, input, and layout geometry), build a test place with [Rojo](https://rojo.space/) and run the suite in Roblox Studio or in CI via the [Open Cloud Luau Execution API](https://create.roblox.com/docs/cloud/guides/luau-execution).
