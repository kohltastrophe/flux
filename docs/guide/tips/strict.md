---
title: Strict mode
description: A development-only graph check that double-runs reactive bodies to surface impure, non-deterministic reactions.
outline: deep
---

# Strict mode

Flux's reactivity rests on one rule: a Computed body is a **pure function of its tracked dependencies**. Read some reactive state, return a value, and Flux guarantees that body re-runs exactly when, and only when, those dependencies change.

A body that quietly breaks that promise (by reading mutable state that isn't tracked, calling `os.clock()`{luau} or `math.random()`{luau}, or mutating something on the side) won't error. It will just produce subtly wrong results: stale UI that never updates, or updates that fire at unpredictable times. These are some of the hardest reactivity bugs to track down, because nothing is obviously broken.

**Strict mode** flushes them into the open. It is a development-only check that **runs every reactive body a second time** each time it evaluates. A pure body double-runs invisibly; it returns the same value and touches nothing else. An impure one gives itself away: a side effect stashed inside a body fires twice, and a body that reads untracked or non-deterministic state returns a _different_ value on its second run. Strict mode does not compare the two runs for you or print a warning; it makes the impurity loud enough to notice (doubled log lines, flickering values, effects that fire twice) so you catch it in development instead of shipping it. If you've used [Vide](https://centau.github.io/vide/), this mirrors its strict mode.

Alongside the double-run, strict mode upgrades two silent hazards into immediate errors: a reactive **cycle** (a body that re-enters a node already evaluating) and **destroying the node that is currently running**. It also runs each body in a way that reports a clean error if it illegally [yields](/guide/concepts/tracking), and runs every [instance binding write checked](#checked-instance-writes) so a failing write reports exactly which instance, property, or attribute rejected which value.

## Enabling strict mode

Strict mode is **off by default** and should stay off in production. Turn it on once, near the top of a development build (it swaps the internal update path, so where you create your nodes doesn't matter):

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

-- Enable in development only
if game:GetService("RunService"):IsStudio() then
    Flux.strict(true)
end
```

`Flux.strict`{luau} doubles as a getter, call it with no argument to read the current state:

```luau
print(Flux.strict()) --> true
```

> [!NOTE] Zero cost when off
> Toggling strict mode swaps the graph's update path between a lean single-run version and the double-run version. When it is off, none of the strict-mode code runs, so leaving the `Flux.strict`{lua} call in your codebase costs nothing in production: there is no need to strip it, just pass `false`{luau} (or never call it).

> [!NOTE] The default follows the optimization level
> Strict's default is keyed to the Luau **optimization level**: off at `-O2`, on below it. Roblox runs at `-O2` in Studio and published games alike, so strict stays off in-engine until you opt in. The exception is the headless [`luau` CLI](/guide/tips/testing) used for unit tests: it runs below `-O2`, so strict is **on** there by default; a stray side effect or additive accumulator in a body will double unless you pass `Flux.strict(false)`{luau}.

## What it does

On each re-evaluation of a Computed or Effect, strict mode runs the body **twice** and keeps the result of the **second** run. Two kinds of impurity become visible:

**A different value on re-run.** If the body returns something different the second time through (with the same tracked inputs), it is non-deterministic: the signature of reading the clock, rolling a random number, or deriving output from untracked mutable state. Because the second run's value is the one Flux propagates, that divergence flows straight into your UI, where you can see it.

**A doubled side effect.** If the body performs a side effect (a `print`{luau}, a log, a table insert, a network call), that effect runs twice. The doubling is the tell that a side effect is living somewhere it shouldn't, or, for a legitimate [Effect](/guide/concepts/effects), simply that strict mode is on.

> [!NOTE]
> Strict mode only re-runs bodies; it never parks or destroys a node over what it observes. A node stays fully usable. The doubling is a signal to fix the body, not a hard failure.

## A worked example

Here is a Computed that looks innocent but reads a plain upvalue counter that Flux has no way to track:

```luau
local count = Flux(0)

-- BAD: `calls` is an ordinary upvalue, not reactive state
local calls = 0
local label = Flux(function()
    calls += 1
    return `{count()} (rendered {calls}x)`
end)
```

With strict mode on, the very first time `label` evaluates, Flux runs the body twice. `calls` is `1` on the first run and `2` on the second, and because the second run wins, `label` reads `0 (rendered 2x)` after a single evaluation, before anything has changed. That doubled counter is the smell: a side effect (`calls += 1`{luau}) is hiding inside a body that is supposed to be a pure derivation.

The fix is to keep the body a pure function of its reactive inputs; move the side effect out:

```luau
local count = Flux(0)

-- GOOD: derived purely from `count`; identical output every run
local label = Flux(function()
    return tostring(count())
end)
```

If you genuinely need to count renders, make the count reactive state of its own, or do it in an [Effect](/guide/concepts/effects). Note that strict mode double-runs Effects too, so a counter inside an Effect still advances twice while strict mode is on; that doubling is expected dev-time noise, not a bug to chase.

> [!CAUTION] Side effects run twice, in Computeds _and_ Effects
> Strict mode double-runs every reactive body, so any side effect inside one (a `print`, a log, a network call) fires twice while strict mode is on. For an accidental side effect hiding in a Computed, that is exactly the point: the doubling is how you find it, so move it out. For a legitimate [Effect](/guide/concepts/effects), the doubling is harmless dev-time noise; turn strict mode off if it gets in the way.

## Accumulators read their own previous value

A Computed can fold its own previous result into a new one by reading the [previous value](/guide/concepts/computeds#reading-the-previous-value) argument. Strict mode feeds the **second** run the result of the **first** run (not the original previous value), so the two runs are not independent:

```luau
local score = Flux(0)

-- Idempotent fold: max(max(prev, s), s) == max(prev, s), so the
-- second run lands on the same value. Unaffected by strict mode.
local highScore = Flux(function(prev)
    return math.max(prev or 0, score())
end)
```

An **idempotent** fold like this running maximum re-runs to the same value and is safe. A fold that is _not_ idempotent (an additive accumulator such as `function(prev) return (prev or 0) + delta() end`{luau}) advances **twice per update** while strict mode is on, because the second run adds `delta()` on top of the first run's result. That is a dev-only artifact: with strict mode off the accumulator advances once as expected. If you rely on an additive accumulator, be aware of the doubling under strict mode (or keep strict mode off for that build).

## Yields and cycles

Reactive bodies must be [synchronous](/guide/concepts/tracking). Strict mode runs each body in a coroutine, so a body that illegally yields (calling `task.wait`{luau}, `:WaitForChild`{luau}, a yielding remote, …) raises a clear `attempt to yield in reactive scope` error instead of corrupting the flush.

Strict mode also turns two latent graph hazards into immediate errors:

- **Reactive cycles.** If updating a node synchronously re-enters a node that is already evaluating, strict mode errors instead of looping, pointing you at the dependency cycle.
- **Destroying the running node.** Destroying the very node whose body is currently executing errors, rather than tearing the graph out from under itself.

Like the double-run, both checks exist only to surface mistakes during development and are off the hot path in production.

## Checked instance writes

When a bound node updates, Flux writes the new value to every property and attribute bound to it. In production those writes run raw: if the engine rejects one (a `nil`{luau} written to a string property, a value of the wrong type, a locked property), the resulting error carries no context about *which* binding failed, and the node's remaining bindings are skipped for that update.

With strict mode on, each write runs individually checked instead:

- A failing write reports the **full instance path, the property or attribute name, and the value** (with its type) that was rejected, so the error names the exact binding to fix.
- One failing write **no longer starves the node's other bindings**; every remaining property, attribute, and children binding still receives the update, and all failures are collected into a single error.

```luau
local text = Flux("hello")
local label = new "TextLabel" { Text = text }

text:set(nil, true)
-- production: "Unable to assign property Text. string expected, got nil" (no instance context)
-- strict:     failed to write nil (nil) to:
--                 Players.you.PlayerGui.ScreenGui.TextLabel.Text: Unable to assign property Text. string expected, got nil
```

Like every strict check, this swaps in a separate write path, so production writes stay entirely unchecked and free.
