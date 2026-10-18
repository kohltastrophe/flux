---
title: Tracking
description: Controlling dependency tracking with read, raw, untrack, retrack, and on in Flux.
outline: deep
sidebar_position: 12
---

# Tracking

Whenever a [Computed](/guide/concepts/computeds), [Effect](/guide/concepts/effects), or property binding runs, Flux automatically subscribes it to every node it reads. These utilities let you read values that may or may not be reactive, peek at state without subscribing, or lock a reaction to an explicit dependency list.

| Utility | Subscribes Caller? | Accepts | Typical Use |
| :--- | :--- | :--- | :--- |
| **`Flux.read(value)`** | Yes | Node, getter, or plain value | Reading `Flux.Reactive<T>` component props |
| **`Flux.raw(value)`** | No | Node, getter, or plain value | Peeking at a Node, getter, or value without tracking |
| **`Flux.untrack(fn)`** | No | `() -> ...T` | Running a block of code without tracking reads |
| **`Flux.untrack()` / `Flux.retrack()`** | No | None | Allocation-free untracked fence in hot paths or around `task.spawn` |
| **`Flux.on(deps, fn, defer?)`** | Declared `deps` only | Node/getter or array of them | Running `fn` untracked whenever `deps` change |
| **`Flux.isReactive()`** | - | None | Checking whether code is currently running inside a tracked reaction |

> [!CAUTION] Reactive Bodies Must Be Synchronous
> Never yield (`task.wait`, `:GetAsync()`, `:WaitForChild()`) inside a Computed or Effect body. Use [`Flux.async`](/guide/concepts/async) for yielding work, or spawn a thread fenced by `Flux.untrack()` / `Flux.retrack()`.

## `Flux.read`{lua}

Reads a `Flux.Reactive<T>` **with** tracking: returns `node()` for a Node, calls `fn()` for a getter, and returns plain values unchanged. Its return type is `Flux.Unwrap<T>`:

```luau
local function StatusLabel(props: { text: Flux.Reactive<string> })
	return Flux.new "TextLabel" {
		Text = function()
			return string.upper(Flux.read(props.text))
		end,
	}
end
```

## `Flux.raw`{lua}

Reads a `Flux.Reactive<T>` **without** tracking: returns `node:peek()` for a Node, runs a getter with tracking suspended, and returns plain values unchanged:

```luau
local health = Flux.signal(100)
local damage = Flux.signal(0)

Flux.effect(function()
	-- Re-runs when `damage` changes, but NOT when `health` changes
	print(`Took {damage()} damage at {Flux.raw(health)} HP`)
end)
```

## `Flux.untrack`{lua}

`Flux.untrack(fn)` runs `fn` with dependency tracking suspended and returns all of its results, while preserving the current [Scope](/guide/concepts/scopes) owner so `Flux.cleanup` still attaches to the enclosing reaction:

```luau
local selectedId = Flux.signal(1)
local namesById = Flux.signal({ "Ada", "Grace" })

Flux.effect(function()
	local id = selectedId() -- tracked
	local name = Flux.untrack(function()
		return namesById()[id] -- untracked
	end)
	print(id, name)
end)
```

## Imperative Pairing: `Flux.untrack()`{luau} / `Flux.retrack()`{luau}

Calling `Flux.untrack()` with no arguments suspends tracking for the rest of the current function run or until `Flux.retrack()` is called. It allocates no closure and is the idiomatic way to fence a `task.spawn` call inside an Effect (since a spawned thread runs synchronously up to its first yield):

```luau
local destination = Flux.signal(Vector3.zero)

Flux.effect(function()
	local target = destination()

	Flux.untrack()
	task.spawn(function()
		walkTo(target) -- any reactive reads before the first yield won't subscribe the effect
	end)
	Flux.retrack()
end)
```

## `Flux.on`{lua}

`Flux.on(deps, fn, defer?)` wraps `fn` so only `deps` (a single Node/getter or an array of them) are tracked, while `fn` itself runs untracked. `fn` receives `(input, previousInput, previousResult)`; for an array of `deps`, `input` and `previousInput` are arrays of their values:

```luau
local trigger = Flux.signal(1)
local multiplier = Flux.signal(10)

-- Re-runs ONLY when `trigger` changes; `multiplier` is read untracked
local total = Flux.computed(Flux.on(trigger, function(value, previousValue)
	return value * multiplier()
end))
```

Pass `true` as the third argument (`defer`) to skip the first run and execute `fn` only on subsequent changes to `deps` ( returning `nil` on the skipped initial run):

```luau
local health = Flux.signal(100)

Flux.effect(Flux.on(health, function(current, previous)
	print(`Health changed from {previous} to {current}`)
end, true))
```
