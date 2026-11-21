---
title: Getting Started
description: Install Flux and build your first reactive Roblox UI.
outline: deep
sidebar_position: 2
---

# Getting Started

Install Flux and build your first reactive UI component in Roblox.

## Installation

### Wally (Recommended)

Add Flux to `[dependencies]` in `wally.toml` and run `wally install`:

```toml
[dependencies]
Flux = "kohltastrophe/flux@0.5.2"
```

Flux installs as a `shared` dependency in `Packages`, available to both client and server scripts.

### GitHub Releases (`.rbxm`)

1. Download the latest `Flux.rbxm` from **[GitHub Releases](https://github.com/kohltastrophe/flux/releases)**.
2. Drag `Flux.rbxm` into Roblox Studio and place the `Flux` module inside [`ReplicatedStorage`](https://create.roblox.com/docs/reference/engine/classes/ReplicatedStorage).

### File Sync (Rojo)

Copy or submodule the repository's `src/` directory into your Rojo tree and `require` it directly.

## Your First App

Create a [`LocalScript`](https://create.roblox.com/docs/reference/engine/classes/LocalScript) in [`StarterPlayerScripts`](https://create.roblox.com/docs/reference/engine/classes/StarterPlayerScripts):

```luau
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

local function CounterApp()
	local count = Flux.signal(0)

	return new "ScreenGui" {
		Name = "FluxCounterApp",
		ResetOnSpawn = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),

		new "TextButton" {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(250, 80),
			BackgroundColor3 = Color3.fromRGB(30, 30, 35),
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 24,

			Text = function()
				return `Clicks: {count()}`
			end,

			Activated = function()
				count(count() + 1)
			end,
		},
	}
end

CounterApp()
```

Press **Play** (`F5`). Clicking the button increments the counter, updating only the button's `Text` property on the next frame.

### How It Works

1. **`Flux.signal(0)`** creates a typed reactive signal (`State<number>`) holding `0`.
2. **`count()`** reads the current value and subscribes the `Text` binding. Calling **`count(count() + 1)`** writes a new value.
3. **`Text = function() ... end`** binds a getter to `Text`. It sets `"Clicks: 0"` immediately when created, then batches future updates once per frame (`PreRender`).
4. **`Activated = function() ... end`** connects the callback to `TextButton.Activated`.

You can also create untyped nodes with `Flux(0)` and use arithmetic or string interpolation directly on the node:

```luau
local count = Flux(0)
-- Inside TextButton:
Text = function() return `Clicks: {count}` end,
Activated = function() count(count + 1) end,
```

See [Signals](/guide/concepts/signals) for when to use typed `Flux.signal` versus terse `Flux(0)`.

## Coming from 0.2.0 {#coming-from-0-2-0}

If you're upgrading an existing project from `0.2.0` to `0.4.0+`, update these renamed or replaced APIs:

| `0.2.0` | `0.4.0+` | Notes |
| :--- | :--- | :--- |
| `_ATTR`, `_TAG`, `_EVENT`, `_REF`, `_CLEAN` | `__ATTR`, `__TAG`, `__EVENT`, `__REF`, `__CLEAN` | Table directives now use a double underscore. `__TAG` takes a tag string/node or array of tags (use `_tag_Name = bool` for boolean toggles). `__EVENT` only takes property/attribute/tag change callbacks (`__EVENT.__ATTR`, `__EVENT.__TAG`); connect `RBXScriptSignal`s at the top level. |
| `Flux.attr`, `Flux.tag`, `Flux.event`, `Flux.ref`, `Flux.onDestroy` | `__ATTR` / `_attr_Name`, `__TAG` / `_tag_Name`, `__EVENT` / `_Prop`, `__REF`, `__CLEAN` | Directive helper functions were removed in favor of `__*` directive tables and [prefix keys](/guide/roblox/hydration#prefix-keys-special-directives). |
| `Flux.Bind.from(node, inst, prop)` / `_EVENT = { Prop = node }` | [`Flux.property(inst, key)`](/guide/concepts/signals#binding-from-an-instance-property) / [`Flux.model(node)`](/guide/roblox/creation#flux-model-two-way-binding-in-one-key) | `Flux.property(inst, key)` (or `Flux(inst, key)`) reads `"Prop"`, `"$Attr"` / `"_attr_Attr"`, and `"#Tag"` / `"_tag_Tag"`. `Flux.listen(node, fn)` still subscribes to a node, firing only on updates after subscribing. |
| `Flux(fn, true)` | [`Flux.effect(fn)`](/guide/concepts/effects) | `Flux()` only constructs signals (`Flux(v)`), computeds (`Flux(fn)`), property nodes (`Flux(inst, key)`), and `RBXScriptSignal` nodes (`Flux(rbxSignal, initial?)`; use [`Flux.fromSignal`](/guide/concepts/signals#bridging-signals) for custom `:Connect()` / `:connect()` tables and userdata). |
| `Flux.wrap(tbl)` | [`Flux.store(tbl)`](/guide/concepts/stores) | `Wrap` was removed; use `Flux.store` for deep reactive table proxies (and [`Flux.split`](/guide/concepts/components#splitting-props-with-flux-split) to partition component props). |
| `ctx()` / `ctx(value, fn)` | [`ctx:get()` / `ctx:provide(value, fn)`](/guide/concepts/context) | `Context` is a frozen table with `:get()` and `:provide()` methods instead of `__call`. |
| `Flux.default` | [`Flux.otherwise`](/guide/concepts/conditionals#switching-between-many-branches) | Catch-all branch key in `Flux.switch`. |
| `Flux.catch(fn, handler)` | `pcall` / `xpcall` | Synchronous `Flux.catch` was removed (wrap imperative calls in [`Flux.untrack`](/guide/concepts/tracking) when needed). [`Flux.safe(tryFn, fallback, equals?)`](/guide/tips/errors) remains for reactive Computed error boundaries. |
| `Flux.clean(item)` | [`Flux.dispose(item)`](/guide/concepts/scopes) | Tears down a single `Cleanable` (pass an array `{ a, b }` for multiple items, or use `Flux.cleanup(item)` to attach to the active owner). |
| `Flux.Store.destroy(proxy)`, `selector:destroy()` | `Flux.Store.Destroy(proxy)`, `selector:Destroy()` | Teardown methods now use PascalCase `:Destroy()`. |
| `Flux.sizeConstraint(min?, max?)` | [`Flux.sizeConstraint({ min, max, ... })`](/guide/utilities/layout#sizeconstraint) | Takes a configuration table instead of two positional `Vector2` arguments. |
| `Flux.viewport`, `Flux.scale`, `Flux.breakpoint`, `Flux.safeArea` | [`Flux.Responsive.*`](/guide/utilities/responsive) | `viewport`, `scale`, and `breakpoint` moved onto `Flux.Responsive` (`scaleFor` -> `scaleOf`, `breakpointFor` -> `breakpointOf`); top-level `Flux.scale(scale?)` now creates a `UIScale` instance. `safeArea` was removed in favor of Roblox `ScreenGui.ScreenInsets`. |
| `Flux.Color.darken`, `desaturate`, `fromTemperature`, `Oklab.fromHCL` / `toHCL` | [`Flux.Color.lighten(c, -amount)`](/guide/motion/color), `saturate(c, -amount)` | Pass negative amounts to `lighten` and `saturate`; `fromTemperature` and `Oklab` HCL helpers were removed (`readable` and `rotateHue` are unchanged). |
| `Flux.strict`, `Flux.Bind.*`, `Flux.Graph.*`, `Flux.Layout.*` | Flat `Flux.*` exports | `Flux.strict` and the `Bind`, `Graph`, and `Layout` sub-namespaces were removed; their members live directly on `Flux`. |

## Next Steps

- **[Signals](/guide/concepts/signals):** Hold and update reactive state.
- **[Computeds](/guide/concepts/computeds):** Derive and cache values from other state.
- **[Effects](/guide/concepts/effects):** Run side effects on frame flushes.
- **[Scopes](/guide/concepts/scopes):** Group instances and reactions under a single `:Destroy()`.
- **[Components](/guide/concepts/components):** Build reusable UI functions and split props with `Flux.split`.
- **[Creation](/guide/roblox/creation):** Explore `Flux.new`, two-way `Flux.model` bindings, and directives.
