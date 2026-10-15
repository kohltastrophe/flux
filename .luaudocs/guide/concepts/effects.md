---
title: Effects
description: Managing side effects and frame-batched execution in Flux.
outline: deep
sidebar_position: 3
---

# Effects

While [Signals](/guide/concepts/signals) and [Computeds](/guide/concepts/computeds) hold and derive state, **Effects** run side effects (logging, audio, network calls, or imperative instance updates) in response to state changes.

```luau
local count = Flux.signal(0)

Flux.effect(function()
	print(`The current count is: {count()}`)
end)

count(1) -- Queues the effect to run on the next frame flush
```

## Creating an Effect

Call `Flux.effect(fn)` to schedule a reactive observer. It runs on the next flush, automatically subscribes to every reactive node read during its execution, and re-runs whenever any of those dependencies change.

- `Flux.effect(fn)` returns a `Node` handle so you can stop it early with `effectNode:Destroy()` (it is also destroyed automatically with its enclosing [Scope](/guide/concepts/scopes)).
- If you don't need a node handle, `Flux.createEffect(fn)` schedules the same scoped effect with zero wrapper allocation.

## Heartbeat Deferral and Flushing

In game loops, mutating state dozens of times in a single frame would waste work if side effects fired synchronously on every write. Flux **batches Effects to the frame** (`RunService.PreRender` on the client, `RunService.Heartbeat` on the server):

1. All dirty observed [Computeds](/guide/concepts/computeds) stabilize in dependency height order first.
2. Queued Effects run once with the final settled state.

```luau
local count = Flux.signal(0)

Flux.effect(function()
	print(`Effect ran! Count is {count()}`)
end)

-- Mutate multiple times in the same frame:
count(1)
count(2)
count(3)

-- On the next frame flush, prints once:
-- > "Effect ran! Count is 3"
```

In tests (or when you need synchronous execution), call [`Flux.flush()`](/guide/tips/testing#deterministic-effects-with-flux-flush) or step [`Flux.Clock`](/guide/tips/testing) to drain pending effects immediately.

> [!NOTE] Runaway Loop Protection
> If an Effect writes to a signal that it also read during the same run, Flux re-queues it. If a single Effect re-triggers itself more than **100 times** in one flush, Flux warns with its `source:line` and disposes the Effect automatically so it cannot freeze the client.

## Cleanup with `Flux.cleanup`{lua}

Register resources inside an Effect (or Computed/Scope) with `Flux.cleanup(cleanable)`. Inside an Effect, registered cleanups run **right before the next re-run** and **when the Effect is destroyed**:

```luau
local selectedPart = Flux.signal(nil :: BasePart?)

Flux.effect(function()
	local part = selectedPart()
	if not part then
		return
	end

	local highlight = Instance.new("SelectionBox")
	highlight.Adornee = part
	highlight.Parent = workspace

	-- Destroy the highlight before the next run or when the effect is disposed
	Flux.cleanup(highlight)
end)
```

`Flux.cleanup` accepts any `Cleanable`:
- A **function** `() -> ()` or `(oldValue, destroyed) -> ()`
- An **`Instance`** (destroyed via `:Destroy()`)
- An **`RBXScriptConnection`** (disconnected)
- A suspended **`thread`** (cancelled via `task.cancel`)
- Any **table** with a `:Destroy()`, `:destroy()`, `:Disconnect()`, or `:disconnect()` method (including Flux nodes, scopes, stores, and async tasks)
- An **array** of cleanables

## Effects vs. Computeds

| | `Flux.computed(fn)` | `Flux.effect(fn)` |
| :--- | :--- | :--- |
| **Purpose** | Derive a new value from state | Synchronize state with an external system |
| **Return value** | Cached and read via `node()` | Ignored (passed only to its own next run as `prev`) |
| **Purity** | Must be pure (no side effects) | Built for side effects and resource setup |
| **When it runs** | On demand when unobserved; before effects on flush when observed | Once per frame flush after upstream computeds settle |

## Bridging to External Systems with `Flux.on`{lua}

When an Effect should react **only** to specific nodes while reading other state without subscribing (or skip its initial run until the first change), wrap the callback in [`Flux.on(deps, fn, defer?)`](/guide/concepts/tracking#flux-on):

```luau
local volume = Flux.signal(0.5)

-- `defer = true` skips the initial flush and fires only when `volume` changes
Flux.effect(Flux.on(volume, function(level, previousLevel)
	SoundService.AmbientReverb = if level > 0.8 then Enum.ReverbType.ConcertHall else Enum.ReverbType.NoReverb
end, true))
```
