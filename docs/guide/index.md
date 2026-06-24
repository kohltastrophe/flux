---
title: What is Flux?
description: An introduction to the Flux library for Roblox and Luau.
outline: deep
---

# What is Flux?

Flux is a declarative Luau library for creating user interfaces. It runs on fine-grained lazy reactions, is strictly typed for accurate IntelliSense, and keeps the syntax terse enough that interfaces read almost like plain Luau.

Traditional UI development carries a lot of boilerplate, and Virtual DOM libraries like React-Luau add the overhead of diffing (rebuilding a mirror of the UI and comparing it against the previous one). Flux takes a different approach: you describe _what_ your UI should look like given your state, and Flux handles the _how_.

Flux runs on a graph algorithm adapted from [Reactively](https://github.com/milomg/reactively), a fine-grained reactivity algorithm that tracks which pieces of state each part of your UI reads, tuned for Luau. It also draws design inspiration from [SolidJS](https://www.solidjs.com/), [Vue](https://vuejs.org/), and earlier Roblox libraries like [Vide](https://github.com/centau/vide) and [Fusion](https://github.com/dphfox/Fusion).

## Core Philosophy

Flux is built on four principles:

### 1. Aggressively Lazy

Flux evaluates absolutely nothing until a value is explicitly observed. There is no topological sort, no dirty-checking pass, and no Virtual DOM diff running ahead of time. When state changes, Flux walks only the exact bindings that the change strictly requires and recomputes nothing else, so there is no over-fetching, no premature rendering, and no wasted CPU cycles. Updates are also **glitch-free**: a node never recomputes from a half-updated graph, so observers only ever see consistent values.

### 2. Fine-Grained Reactivity (No Virtual DOM)

Flux does not use a Virtual DOM. When you update a piece of state, it doesn't re-render a component tree or diff a virtual representation against live Roblox [`Instances`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance). Instead, state updates flow **directly** to the exact property bindings that depend on them. If a player's health changes, only the [`Size`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject#Size) of the health bar updates. Everything else stays untouched. Each piece of reactive state (a Signal you set, a Computed you derive, an Effect that runs side effects) is a **node** in this graph.

### 3. "Run-Once" Components

In many UI frameworks, components are functions that re-execute on every state change. In Flux, **components run exactly once.** They exist to construct your Roblox [`Instances`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance) and wire up the reactive graph. Once the UI is built, the factory function is done, leaving behind targeted property updates.

### 4. Declarative, Native UI

Flux builds on the Roblox Instance hierarchy. Using `Flux.new`{lua} and `Flux.edit`{lua}, you can build hierarchies of UI elements (or physical parts) in a single, readable block of code, then bind reactive nodes directly to properties. Operator overloading means reactive expressions read like plain Luau math.

## Batteries Included

Lazy reactivity is the engine. On top of it, Flux ships the rest of what you need to build interfaces, all strictly typed:

- **Reactive primitives** - [`Flux.signal`](/guide/concepts/signals), [`Flux.computed`](/guide/concepts/computeds), and [`Flux.effect`](/guide/concepts/effects), plus [stores](/guide/concepts/stores) and [context](/guide/concepts/context) for shared state, and [`Flux.wrap`](/guide/concepts/wrapping) to turn plain tables into reactive ones.
- **Declarative instances** - [`Flux.new`](/guide/roblox/creation) to build and [`Flux.edit`](/guide/roblox/hydration) to hydrate existing Instances, with scoped lifecycles and cleanup.
- **Lifecycle & cleanup** - [`Flux.scope`](/guide/concepts/scopes) tracks every node, instance, and effect it creates and tears them all down with a single `Destroy`, including nested child scopes.
- **Control flow** - [`Flux.show`](/guide/concepts/conditionals) and [`Flux.switch`](/guide/concepts/conditionals) for conditional rendering, [`Flux.forValue` / `Flux.forIndex`](/guide/concepts/mapping) for keyed mapping, and [`Flux.selector`](/guide/concepts/selectors) for O(1) selection in large lists.
- **Motion** - physics [springs](/guide/motion/spring), [tweens](/guide/motion/tween), and perceptual [color](/guide/motion/color) interpolation, all stepped once per frame.
- **Responsive & layout** - [`viewport`, `scale`, and `breakpoint`](/guide/utilities/responsive) helpers alongside [`padding`, `list`, `grid`, and `flex`](/guide/utilities/layout).
- **Async & safety** - [`Flux.async`](/guide/concepts/async) tasks, [error boundaries](/guide/tips/errors), and a [`strict` mode](/guide/tips/strict) that catches impure computations in development.
- **Sensible defaults** - [`Flux.new`](/guide/roblox/creation) applies a few default properties (anchored Parts, borderless GUI, `LayoutOrder` sorting), all customizable and disableable.
- **Strict types** - built for `--!strict` mode with real IntelliSense, relevant errors, and autocomplete that knows the exact properties of whichever Instance class you are building.

## Example

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

-- 1. A reactive Signal
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

Here, `{count}`{luau} in the string and `count + 1`{luau} are similar to `:get()`{luau}. Interpolation and operators read the node's current value for you. See [Signals](/guide/concepts/signals) for how this works.

## Is Flux Right for My Project?

Flux fits projects that want a reactive library without giving up the speed of native Roblox instances. It scales from small, localized UI components to server-wide state management.

See **[Getting Started](/guide/getting-started)** to install Flux and build your first reactive app.
