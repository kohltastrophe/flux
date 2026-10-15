---
title: Scopes
description: Managing lifecycles and cleaning up reactive state in Flux.
outline: deep
sidebar_position: 4
---

# Scopes

A **Scope** owns every reactive computation, UI instance, and cleanup created inside it so you can tear them all down with a single `scope:Destroy()`.

```luau
local scope, label = Flux.scope(function()
	local name = Flux.signal("Guest")

	Flux.effect(function()
		print(`Hello, {name()}`)
	end)

	return Flux.new "TextLabel" {
		Text = function()
			return `Welcome, {name()}`
		end,
		Parent = playerGui,
	}
end)

-- Tears down the Effect and destroys `label`:
scope:Destroy()
```

## Creating a Scope

`Flux.scope(fn)` runs `fn(scope)` inside a new owner scope and returns `(scope, result)`. You use the exact same `Flux.signal`, `Flux.computed`, `Flux.effect`, and `Flux.new` calls inside a scope as outside—ownership is tracked automatically.

> [!TIP] Coming from SolidJS or Maid/Trove?
> `Flux.scope` combines a reactive root (like SolidJS's `createRoot`) with a resource cleanup container (like Roblox's Maid or Trove patterns).

## What a Scope Owns

Everything created while a scope is active that holds a subscription or resource attaches to that scope automatically:

- **Computeds and Effects** (`Flux.computed`, `Flux.effect`, `Flux.createMemo`, `Flux.createEffect`, `Flux(fn)`)
- **Instances and bindings** from [`Flux.new`](/guide/roblox/creation), [`Flux.edit`](/guide/roblox/hydration), and [`Flux.property`](/guide/concepts/signals#binding-from-an-instance-property)
- **State helpers:** [Stores](/guide/concepts/stores), [Async](/guide/concepts/async) tasks, [Selectors](/guide/concepts/selectors), [Mapping](/guide/concepts/mapping) (`forValue`, `forIndex`), and [Conditionals](/guide/concepts/conditionals) (`show`, `switch`, `presence`)
- **Interaction & motion nodes:** [`Flux.Interact`](/guide/utilities/interact) state nodes (`hover`, `press`, `selected`, `focused`), [`Flux.spring`](/guide/motion/spring), and [`Flux.tween`](/guide/motion/tween)
- **Custom teardown items** registered with [`Flux.cleanup`](/guide/concepts/effects#cleanup-with-flux-cleanup)

> [!NOTE] Plain Signals Are Garbage-Collected
> Plain signals (`Flux.signal(v)`, `Flux(v)`) hold no upstream subscriptions or external resources, so scopes do not own them; Luau's garbage collector reclaims them once unreferenced.

## Nesting Scopes

Calling `Flux.scope` inside another scope creates a **child scope**. Destroying the parent destroys all remaining children, while destroying a child early unlinks it cleanly from the parent:

```luau
local session = Flux.scope(function()
	local modal = Flux.scope(function()
		return Flux.new "Frame" { Name = "Modal", Parent = playerGui }
	end)

	-- Close just the modal while keeping `session` alive:
	modal:Destroy()
end)

-- Later, tear down the entire session and any remaining child scopes:
session:Destroy()
```

## Capturing the Active Scope

When creating reactions or cleanups inside an asynchronous callback (`task.delay`, a promise, or a remote callback), capture the active owner with `Flux.getOwner()` and restore it with `Flux.withOwner(owner, fn)`:

```luau
local owner = Flux.getOwner()

task.delay(1, function()
	Flux.withOwner(owner, function()
		local toast = Flux.new "TextLabel" { Text = "Saved!", Parent = playerGui }
		Flux.cleanup(toast)
	end)
end)
```

- `Flux.withOwner(owner, fn)` restores both ownership and any [Context](/guide/concepts/context) values active where `owner` was created, without enabling dependency tracking.
- Pass `nil` as `owner` to create unowned root reactions from inside an existing scope.
- If `owner` was **already destroyed** before `withOwner` runs (for example, a late timer callback firing after a modal closed), `withOwner` immediately disposes everything created inside `fn` as soon as `fn` returns.

## Disposing by Hand with `Flux.dispose`{lua}

`Flux.dispose(obj)` runs the same teardown engine immediately on any `Cleanable` (a function, `Instance`, `RBXScriptConnection`, suspended `thread`, object with a `Destroy`/`destroy`/`Disconnect`/`disconnect` method, or an array of them):

```luau
local connections = {
	part.Touched:Connect(onTouched),
	part.Destroying:Connect(onGone),
}

Flux.dispose(connections) -- disconnects both immediately
```

`Flux.dispose` runs [untracked](/guide/concepts/tracking) and isolates errors via `warn` so one failing cleanup never aborts the rest. Use `Flux.dispose` to tear something down **now**; use `Flux.cleanup` to attach teardown to the active owner.

## Connecting a Scope to an Instance Lifetime

When a component returns a root `Instance` that callers may `:Destroy()` directly, pass the scope to the `__CLEAN` directive so destroying either the `Instance` or the `scope` tears down the whole unit once:

```luau
local function Toast(message: string): Frame
	local _, frame = Flux.scope(function(scope)
		local opacity = Flux.tween(0, TweenInfo.new(0.25))

		return Flux.new "Frame" {
			BackgroundTransparency = opacity,
			Size = UDim2.fromOffset(300, 60),
			__CLEAN = { scope },

			Flux.new "TextLabel" { Text = message },
		}
	end)

	return frame
end
```
