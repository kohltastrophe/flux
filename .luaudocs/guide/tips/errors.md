---
title: Error Handling
description: Managing errors and isolating failures across the reactive graph in Flux.
outline: deep
sidebar_position: 2
---

# Error Handling

Unhandled errors inside reactive computations or async tasks can interrupt UI updates when left uncontained. Flux provides [`Flux.safe`](#structured-error-handling-flux-safe) for reactive error boundaries, built-in error containment in [`Flux.async`](#asynchronous-errors) and [Effects](#reactive-graph-errors), and isolated teardown via [Scopes](#scope-safety).

## Structured Error Handling (`Flux.safe`) {#structured-error-handling-flux-safe}

`Flux.safe(tryFn, fallback, equals?)` wraps a computation in a self-healing reactive error boundary. It returns a [Computed](/guide/concepts/computeds) node that evaluates `tryFn`. If `tryFn` throws, it returns `fallback` (or calls `fallback(err, reset)` whenever `type(fallback) == "function"`):

```luau
local HttpService = game:GetService("HttpService")
local rawJson = Flux.signal('{"malformed JSON')
local retry: (() -> ())? = nil

local parsed = Flux.safe(function()
	return HttpService:JSONDecode(rawJson())
end, function(err, reset)
	warn("JSON parse failed:", err)
	retry = reset
	return nil
end)

print(parsed()) -- nil (after warning)

-- Self-healing: fixing `rawJson` automatically re-evaluates `parsed`,
-- or call `retry()` later to attempt `tryFn` again manually
rawJson('{"ok": true}')
print(parsed().ok) -- true
```

Any reactive dependencies read before `tryFn` threw remain tracked, so updating `rawJson` re-runs `parsed` and recovers cleanly. Calling `reset()` forces `tryFn` to re-run even when no tracked signal changed (such as retrying a time-dependent or external check), while calling `reset` after `parsed` heals or is destroyed does nothing. The `fallback` handler itself runs **untracked** so fallback logging or recovery reads don't subscribe the computation to unintended dependencies.

## Asynchronous Errors

[`Flux.async`](/guide/concepts/async) runs its task inside `pcall` automatically. If the task throws, `.error` captures the error string and `.loading` settles to `false` without crashing the thread:

```luau
local HttpService = game:GetService("HttpService")
local userId = Flux.signal(123)

local profile = Flux.async(userId, function(id)
	local raw = HttpService:GetAsync(`https://api.example.com/users/{id}`)
	return HttpService:JSONDecode(raw)
end)

local statusLabel = Flux.new "TextLabel" {
	Text = function()
		if profile.error() then
			return `Error: {profile.error()}`
		elseif profile.loading() then
			return "Loading..."
		end
		local data = profile.data()
		return if data and data.username then data.username else "No data"
	end,
}
```

## Reactive Graph Errors

Flux isolates failures across the graph so one broken node never corrupts the rest of the frame:

- **Computeds:** If an unprotected Computed throws, Flux caches the error and re-throws it to the caller reading it while keeping graph state consistent. When a dependency read before the error changes, the Computed re-evaluates and heals if the new run succeeds.
- **Effects:** If an [Effect](/guide/concepts/effects) throws during a flush, Flux logs a warning (`[Flux] suppressed effect error:`) and continues flushing all remaining queued effects. If a cleanup registered with `Flux.cleanup` throws, Flux warns and finishes running the remaining cleanups.
- **Runaway Loop Protection:** If a self-triggering Effect runs `100` times in a single flush (re-queuing itself on the 100th run), Flux warns and disposes that offending Effect so the frame never hangs.

## Scope Safety

Calling `:Destroy()` on a [Scope](/guide/concepts/scopes) (or passing items to [`Flux.dispose`](/guide/concepts/scopes#disposing-by-hand-with-flux-dispose)) isolates cleanup errors. Even if one cleanup callback throws, Flux logs a warning and finishes tearing down every remaining instance, connection, and child scope.
