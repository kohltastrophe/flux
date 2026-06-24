---
title: Testing
description: Writing deterministic tests for Flux state, components, and systems.
outline: deep
---

# Testing

Flux is built to be testable: components are plain functions, state lives in ordinary objects rather than a hidden component tree, and the reactive core has no Roblox dependencies. This page covers the patterns that keep tests deterministic.

## Deterministic Effects with `Flux.flush()`{luau}

Effects and property bindings are batched and run once per `Heartbeat`. Inside a test you don't want to wait a frame; call `Flux.flush()`{luau} to run everything pending synchronously:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

local count = Flux(0)
local label = new "TextLabel" {
    Text = function()
        return "Count: " .. count -- `.. count` reads the signal's current value (see [Signals](/guide/concepts/signals))
    end,
}

assert(label.Text == "Count: 0") -- the initial binding value is applied synchronously, no flush needed

count(5)
Flux.flush() -- run pending effects and property updates now

assert(label.Text == "Count: 5")
```

## Isolating Tests with Scopes

Create everything in a test through a [Scope](/guide/concepts/scopes) and destroy it in teardown, so no state or instances leak between cases:

```luau
local function testCounter()
    local scope, ui = Flux.scope(function()
        local count = Flux(0)
        local label = new "TextLabel" {
            Text = function()
                return "Count: " .. count
            end,
        }
        return { count = count, label = label }
    end)

    ui.count(3)
    Flux.flush()
    assert(ui.label.Text == "Count: 3")

    scope:Destroy() -- tears down the binding and the label; the count signal is left for the GC
end
```

## Headless Testing (No Roblox)

The whole library, including the root `Flux` module, runs in the vanilla [Luau CLI](https://github.com/luau-lang/luau/releases) (0.640+ for require-by-string). Pure state logic can be tested on your machine or in CI with no Studio and no Roblox place.

Three caveats:

- There is no `Heartbeat` headless, so effects only run when you call `Graph.flush()`{luau} yourself (and motion only steps when you call `Flux.Motion.step()`{luau}).
- Roblox datatypes don't exist headless: `number` springs and tweens work fully, but animating a `UDim2`/`Vector3`/etc. needs the real engine.
- [Strict mode](/guide/tips/strict) is **on** by default headless (the CLI runs below `-O2`), so every reactive body runs **twice**. That catches impure logic, but it also means a side effect inside a body (a `table.insert` you assert on, say) fires twice. Call `Flux.strict(false)`{luau} for a deterministic single run, or assert on a node's value rather than how many times an effect fired.

`Graph` is the dependency-free core that `Flux()`{luau} wraps. `Graph.new(v)`{luau} is a Signal, `Graph.new(fn)`{luau} a Computed, `Graph.new(fn, true)`{luau} an Effect, and `:get()`{luau}/`:set()`{luau} are the explicit forms of the call sugar.

```luau
-- spec.luau (run with: luau spec.luau)
local Graph = require("./src/Graph")

Graph.strict(false) -- headless defaults to strict-on (double-runs bodies); off here for a single, deterministic run

local count = Graph.new(1)
local doubled = Graph.new(function()
    return count:get() * 2
end)

assert(doubled:get() == 2)
count:set(5)
assert(doubled:get() == 10)

local seen = {}
local effect = Graph.new(function()
    table.insert(seen, count:get())
end, true) -- the `true` makes this an Effect (see [Effects](/guide/concepts/effects))

Graph.flush()
assert(#seen == 1 and seen[1] == 5)
```

Flux's own spec, [`test/spec.luau`](https://github.com/kohltastrophe/flux/blob/main/test/spec.luau), runs exactly this way and doubles as a reference for the graph's guaranteed semantics: laziness, memoization, diamond updates, effect batching, error recovery, and cycle containment.

## Full-Engine Tests in CI

For tests that need real instances (component output, hydration, motion), build a test place with [Rojo](https://rojo.space/) and execute the spec in the cloud with the [Open Cloud Luau Execution API](https://create.roblox.com/docs/cloud/guides/luau-execution), with no Studio session required. Flux's own [CI workflow](https://github.com/kohltastrophe/flux/blob/main/.github/workflows/ci.yml) does exactly this with the same `test/spec.luau` that runs headless: the suite detects its runtime, skipping Roblox-only tests under the CLI and running everything (instances, hydration, motion datatypes) in the cloud. `rojo build` produces a place file, a script uploads it, runs the spec task, and fails the build on any failed assertion.
