---
title: What is Flux?
description: An introduction to the Flux library for Roblox and Luau.
outline: deep
sidebar_position: 1
---

# What is Flux?

Flux is a declarative Luau library for building user interfaces. It pairs fine-grained, glitch-free reactivity with strict Luau typing and terse syntax, so interfaces read like plain Luau and update native Roblox [`Instances`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance) directly.

```luau
local count = Flux.signal(0)
local stats = Flux.store({ kills = 0, deaths = 0 })

local function CounterButton()
	return Flux.new "TextButton" {
		Size = UDim2.fromOffset(200, 50),
		BackgroundColor3 = Color3.fromRGB(0, 120, 255),
		Text = function()
			return `Clicks: {count()} | K/D: {stats.kills}/{stats.deaths}`
		end,
		Activated = function()
			count(count() + 1)
			stats.kills += 1
		end,
	}
end
```

## Core Principles

### 1. Work-Minimal & Glitch-Free

Dormant computations sleep with zero subscriptions until something observes them. Once bound to the UI or an [Effect](/guide/concepts/effects), updates batch to the frame (`RunService.PreRender` on the client, `Heartbeat` on the server) and settle in dependency order before effects run. If a derived value recomputes to the same result, propagation stops right there: no downstream bindings wake up, and no observer ever sees a half-updated graph.

### 2. Fine-Grained Reactivity (No Virtual DOM)

Flux does not build or diff a virtual component tree. State changes flow directly to the exact property bindings that read them: when a player's health changes, only the [`Size`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject#Size) of the health bar updates.

### 3. Run-Once Components

Components in Flux are plain Luau functions that **run once** to construct [`Instances`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance) and wire up reactive bindings. Once mounted, the component function never re-executes; only individual property bindings re-evaluate when their dependencies change.

### 4. Declarative, Strictly Typed UI

[`Flux.new`](/guide/roblox/creation) and [`Flux.edit`](/guide/roblox/hydration) build and hydrate Roblox instance hierarchies in a single block with full `--!strict` autocomplete for every property, event, and child. Reactive nodes also support `__call` and operator overloading (`count + 1`, `` `Clicks: {count}` ``), so reactive expressions stay compact.

## Batteries Included

- **Reactive primitives** - [`Flux.signal`](/guide/concepts/signals), [`Flux.computed`](/guide/concepts/computeds), and [`Flux.effect`](/guide/concepts/effects), plus [stores](/guide/concepts/stores) and [context](/guide/concepts/context) for shared state, and [`Flux.split`](/guide/concepts/components#splitting-props-with-flux-split) for typed component props.
- **Declarative instances** - [`Flux.new`](/guide/roblox/creation) to build and [`Flux.edit`](/guide/roblox/hydration) to hydrate existing Instances, with two-way [`Flux.model`](/guide/roblox/creation#flux-model-two-way-binding-in-one-key) bindings, [`Flux.Find`](/guide/roblox/hydration#instance-selectors-flux-find) selectors, and customizable [defaults](/guide/roblox/defaults).
- **Lifecycle & cleanup** - [`Flux.scope`](/guide/concepts/scopes) tracks every node, instance, and effect created inside it and tears them down with a single `:Destroy()`.
- **Control flow** - [`Flux.show`](/guide/concepts/conditionals), [`Flux.switch`](/guide/concepts/conditionals#switching-between-many-branches), and exit-animated [`Flux.presence`](/guide/concepts/conditionals#animating-exits-with-presence) for conditional subtrees, [`Flux.forValue` / `Flux.forIndex`](/guide/concepts/mapping) for keyed lists, and [`Flux.selector`](/guide/concepts/selectors) for O(1) list selection.
- **Motion** - physics [springs](/guide/motion/spring), [tweens](/guide/motion/tween), and perceptual [color](/guide/motion/color) manipulation in Oklab, stepped automatically every frame.
- **Responsive, layout & input** - [`Flux.Responsive`](/guide/utilities/responsive) screen and accessibility nodes, [`Flux.Interact`](/guide/utilities/interact) (`hover`, `press`, `selected`, `focused`), and terse [layout helpers](/guide/utilities/layout) (`padding`, `corner`, `stroke`, `list`, `grid`, `flex`).
- **Async, safety & testing** - [`Flux.async`](/guide/concepts/async) tasks, [`Flux.safe`](/guide/tips/errors) error boundaries, and [`Flux.Clock`](/guide/tips/testing) for deterministic virtual-time testing in Studio and headless CI.

See **[Getting Started](/guide/introduction/getting-started)** to install Flux and build your first component.
