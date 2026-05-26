---
title: What is Flux?
description: An introduction to the Flux reactive framework for Roblox and Luau.
outline: deep
---

# What is Flux?

Flux is a declarative, fine-grained reactive UI framework built natively for Luau and the Roblox engine.

If you have ever felt restricted by the boilerplate of traditional UI development, or bogged down by the performance overhead of Virtual DOM diffing in frameworks like React-Luau, Flux offers a completely different paradigm. It lets you build complex, highly dynamic user interfaces and game systems by simply describing _how_ your UI should look given your state; Flux handles all the wiring.

At its core, Flux is powered by a **modified Reactively graph algorithm** tuned for Luau's execution environment, taking design inspiration from [SolidJS](https://www.solidjs.com/), [Vue](https://vuejs.org/), and the Roblox ecosystem's own pioneers.

## Core Philosophy

Flux is built on three foundational principles:

### 1. Fine-Grained Reactivity (No Virtual DOM)

Flux does not use a Virtual DOM. When you update a piece of state, it doesn't re-render a component tree or diff a virtual representation against live Roblox [`Instances`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance). Instead, state updates flow **directly** to the exact property bindings that depend on them. If a player's health changes, only the [`Size`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject#Size) of the health bar updates. Everything else is completely untouched.

### 2. "Run-Once" Components

In traditional reactive frameworks, components are functions that re-execute on every state change. In Flux, **components run exactly once.** They exist solely to construct your Roblox [`Instances`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance) and wire up the reactive graph. Once the UI is built, the factory function is done; leaving behind only lightning-fast, targeted property updates.

### 3. Declarative, Native UI

Flux embraces the Roblox Instance hierarchy. Using `Flux.new`{lua} and `Flux.edit`{lua}, you can build complex hierarchies of UI elements (or physical parts) in a single, readable block of code, then bind reactive nodes directly to properties. Operator overloading means reactive expressions read like plain Luau math.

## Key Features

- **4-State Graph Algorithm** - A modified Reactively push/pull algorithm with `CLEAN`, `CHECK`, `DIRTY`, and `BUSY` states ensures zero redundant recomputation, glitch-free evaluation, and instant cycle detection.
- **Operator Overloading** - All arithmetic, comparison, concatenation, and unary operators work directly on reactive nodes. `count * 2`{lua} just works, no `:get()`{luau} required.
- **Async Resources** - `Flux.async`{lua} wraps yielding operations (DataStore, HTTP) in non-blocking reactive containers with built-in `.data`, `.loading`, and `.error` nodes and automatic race condition handling.
- **Reactive Stores** - `Flux.store`{lua} wraps a plain Luau table in a transparent deep-reactive proxy. Reads and writes look identical to standard table access.
- **Declarative Selectors** - `Flux.Find`{lua} lets you hydrate existing Studio-placed Instance trees with reactive bindings using inline selectors, no restructuring required.
- **Motion** - `Flux.spring`{lua} and `Flux.tween`{lua} return full reactive nodes that animate toward a target every Heartbeat.
- **First-Class Scopes** - `Flux.scope()`{luau} provides zero-boilerplate lifetime management. Create a scope; destroy it once to clean up every node, effect, and instance inside it simultaneously.
- **Bulletproof Types** - Built from the ground up for `--!strict` mode with real IntelliSense, relevant errors, and per-instance property autocomplete.

## A Quick Glance

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

-- 1. Reactive state
local count = Flux(0)

-- 2. Reactive store for nested data
local stats = Flux.store({ kills = 0, deaths = 0 })

-- 3. Declarative UI with reactive bindings
local function CounterButton()
    return new "TextButton" {
        Size = UDim2.fromOffset(200, 50),
        BackgroundColor3 = Color3.fromRGB(0, 120, 255),

        -- Operator overloading: count reads naturally in expressions
        Text = function()
            return `Clicks: {count} | K/D: {stats.kills}/{stats.deaths}`
        end,

        Activated = function()
            count(count + 1)
            stats.kills += 1
        end,
    }
end
```

## Is Flux Right for My Project?

If you are building high-performance systems and want the expressiveness of a modern reactive framework without sacrificing the raw speed of native Roblox instances, Flux is designed exactly for you. It scales from tiny, localised UI components to massive, server-wide state management architectures.

Ready to dive in? See **[Getting Started](/guide/getting-started)** to install Flux and build your first reactive app.
