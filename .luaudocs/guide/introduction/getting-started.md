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
Flux = "kohltastrophe/flux@0.3.0"
```

Flux installs as a `shared` dependency in `Packages`, available to both client and server scripts.

### GitHub Releases (`.rbxm`)

1. Download the latest `Flux.rbxm` from **[GitHub Releases](https://github.com/kohltastrophe/flux/releases)**.
2. Drag `Flux.rbxm` into Roblox Studio and place the `Flux` module inside [`ReplicatedStorage`](https://create.roblox.com/docs/en-us/reference/engine/classes/ReplicatedStorage).

### File Sync (Rojo)

Copy or submodule the repository's `src/` directory into your Rojo tree and `require` it directly.

## Your First App

Create a [`LocalScript`](https://create.roblox.com/docs/en-us/reference/engine/classes/LocalScript) in [`StarterPlayerScripts`](https://create.roblox.com/docs/en-us/reference/engine/classes/StarterPlayerScripts):

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
2. **`count()`** reads the current value and subscribes the enclosing `Text` binding; **`count(count() + 1)`** writes a new value.
3. **`Text = function() ... end`** binds a reactive getter to `Text`. It applies `"Clicks: 0"` immediately on creation, then batches future updates to the frame (`PreRender`).
4. **`Activated = function() ... end`** connects the function to `TextButton.Activated`.

> [!TIP] Terse Shorthand & Operator Overloading
> You can also create untyped nodes with `Flux(0)` and use arithmetic or string interpolation directly on nodes:
> ```luau
> local count = Flux(0)
> -- Inside TextButton:
> Text = function() return `Clicks: {count}` end,
> Activated = function() count(count + 1) end,
> ```
> See [Signals](/guide/concepts/signals) for when to prefer typed `Flux.signal` vs. terse `Flux(0)`.

## Coming from 0.2.0 {#coming-from-0-2-0}

If you are upgrading an existing project from `0.2.0` to `0.3.0`, update these renamed or consolidated APIs:

| `0.2.0` | `0.3.0` | Notes |
| :--- | :--- | :--- |
| `_ATTR`, `_TAG`, `_EVENT`, `_REF`, `_CLEAN` | `__ATTR`, `__TAG`, `__EVENT`, `__REF`, `__CLEAN` | Table directives now use a double underscore (`__EVENT.__ATTR`, `__EVENT.__TAG`). |
| `Flux.attr`, `Flux.tag`, `Flux.event`, `Flux.ref`, `Flux.onDestroy` | `_attr_Name`, `_tag_Name`, `_Prop`, `__attr_Name`, `__tag_Name` | One-off directive helpers are replaced by inline [prefix keys](/guide/roblox/hydration#prefix-keys-special-directives) and `__*` directive tables. |
| `Flux.listen(inst, prop)` | [`Flux.property(inst, key)`](/guide/concepts/signals#binding-from-an-instance-property) | Also supports `"$Attr"` / `"_attr_Attr"` and `"#Tag"` / `"_tag_Tag"` (or `Flux(inst, key)`). |
| `Flux(fn, true)` | [`Flux.effect(fn)`](/guide/concepts/effects) | `Flux()` only constructs signals (`Flux(v)`), computeds (`Flux(fn)`), and property nodes (`Flux(inst, key)`). |
| `Flux.on(deps, fn)` | `Flux.effect(Flux.on(deps, fn))` | [`Flux.on`](/guide/concepts/effects#explicit-dependencies-with-flux-on) now returns a tracked effect callback rather than a standalone listener. |
| `Flux.wrap` / `Flux.props` | [`Flux.split(props, ...)`](/guide/concepts/components#splitting-props-with-flux-split) | Split custom component props from pass-through instance props; nested tables in `Flux.new` / `Flux.edit` flatten automatically. |
| `Flux.default` | [`Flux.otherwise`](/guide/concepts/conditionals#switching-between-many-branches) | Default branch key in `Flux.switch`. |
| `Flux.safe` + `Flux.catch` | [`Flux.safe(tryFn, catchFn)`](/guide/tips/errors) | Combined into a single error-boundary helper. |
| `Flux.clean(...)` | [`Flux.dispose(...)`](/guide/concepts/scopes) | Immediately tears down any `Cleanable` (use `Flux.cleanup(fn)` to register on the active owner). |
| `Flux.viewport`, `Flux.scale`, `Flux.safeArea` | [`Flux.Responsive.*`](/guide/utilities/responsive) | Accessed via `Flux.Responsive.viewport`, `scale`, `breakpoint`, `displaySize`, `platform`, `input`, etc. |
| `Flux.pointIn`, `Flux.sunk`, `Flux.exclusive` | [`Flux.Interact.*`](/guide/utilities/interact) | Accessed via `Flux.Interact.pointIn`, `sunk`, `covered`, `hover`, `press`, `selected`, and `focused`. |
| `Flux.Color.readable`, `rotateHue` | [`Flux.Color.contrastText`](/guide/motion/color), `spin` | Renamed on the Oklab color utility namespace. |

## Next Steps

- **[Signals](/guide/concepts/signals)** — Hold and update reactive state.
- **[Computeds](/guide/concepts/computeds)** — Derive and cache values from other state.
- **[Effects](/guide/concepts/effects)** — Run side effects on frame flushes.
- **[Scopes](/guide/concepts/scopes)** — Group instances and reactions under a single `:Destroy()`.
- **[Components](/guide/concepts/components)** — Build reusable UI functions and split props with `Flux.split`.
- **[Creation](/guide/roblox/creation)** — Explore `Flux.new`, two-way `Flux.model` bindings, and directives.
