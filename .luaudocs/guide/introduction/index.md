---
title: Overview
description: An introduction to the Flux library for Roblox and Luau.
outline: deep
sidebar_position: 1
---

# Overview

Flux is a reactive UI library for Luau. State updates batch once per frame, and only the [`Instance`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance) properties that actually change get touched.

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

### 1. Lazy & Frame-Batched

Dormant computations sleep with zero subscriptions until something observes them. When bound to the UI or an [Effect](/guide/concepts/effects), updates batch once per frame (`RunService.PreRender` on the client, `Heartbeat` on the server) and run in dependency order before effects fire. If a computed value produces the same result, downstream bindings don't wake up.

### 2. Direct Property Updates

Flux doesn't build or diff a virtual DOM tree. State changes flow straight to the property bindings that read them. When a player's health changes, only the health bar's [`Size`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject#Size) updates.

### 3. Run-Once Components

Components in Flux are plain Luau functions that **run once** to create [`Instances`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance) and attach reactive bindings. After mounting, the component function never runs again. Only the individual property bindings re-run when their dependencies change.

### 4. Strictly Typed UI

[`Flux.new`](/guide/roblox/creation) and [`Flux.edit`](/guide/roblox/hydration) build and wire up Roblox instances in one table with `--!strict` autocomplete for properties, events, and children. Reactive nodes also overload `__call` and standard operators (`count + 1`, `` `Clicks: {count}` ``), so expressions stay short.

## Batteries Included

- **Reactive State:** Track values with [`Flux.signal`](/guide/concepts/signals), [`Flux.computed`](/guide/concepts/computeds), [`Flux.effect`](/guide/concepts/effects), and nested [`Flux.store`](/guide/concepts/stores) proxies.
- **Networked State:** Replicate server-authoritative and per-player signals to clients with [`Flux.Sync`](/guide/concepts/sync).
- **Declarative Instances:** Build trees with [`Flux.new`](/guide/roblox/creation) or wire up existing templates with [`Flux.edit`](/guide/roblox/hydration).
- **Scoped Cleanup:** Wrap a tree in [`Flux.scope`](/guide/concepts/scopes) to tear down all of its instances and reactions with a single `:Destroy()` call.
- **Control Flow & Lists:** Render conditional branches with [`Flux.show`](/guide/concepts/conditionals) and [`Flux.switch`](/guide/concepts/conditionals#switching-between-many-branches), or map dynamic lists with [`Flux.forValue`](/guide/concepts/mapping).
- **Built-in Motion:** Animate any state with physics [springs](/guide/motion/spring), [tweens](/guide/motion/tween), or perceptual [color](/guide/motion/color) blending.
- **UI Utilities:** Read screen [breakpoints](/guide/utilities/responsive), track [pointer and gamepad interactions](/guide/utilities/interact), and drop in terse [layout constraints](/guide/utilities/layout).
- **Async & Testing:** Run cancellable [`Flux.async`](/guide/concepts/async) tasks, catch failures with [`Flux.safe`](/guide/tips/errors), and step a virtual [`Flux.Clock`](/guide/tips/testing) in tests.

See **[Getting Started](/guide/introduction/getting-started)** to install Flux and build your first component.
