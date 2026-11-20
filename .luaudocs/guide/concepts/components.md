---
title: Components
description: Building reusable, strictly typed UI components in Flux.
outline: deep
sidebar_position: 10
---

# Components

In Flux, **components are plain Luau functions** that run **once** to construct Roblox [`Instances`](https://create.roblox.com/docs/reference/engine/classes/Instance) and wire up reactive bindings.

```luau
type ButtonProps = {
	text: Flux.Reactive<string>,
	onClick: (() -> ())?,
}

local function PrimaryButton(props: ButtonProps): TextButton
	return Flux.new "TextButton" {
		Size = UDim2.fromOffset(200, 50),
		BackgroundColor3 = Color3.fromRGB(0, 120, 255),
		Text = props.text,
		Activated = function()
			if props.onClick then
				props.onClick()
			end
		end,
	}
end
```

When state changes, `PrimaryButton` itself doesn't re-run. Only the bound `Text` property updates.

## Consuming Components

Call component functions directly inside a `Flux.new` hierarchy:

```luau
local count = Flux.signal(0)

local screen = Flux.new "Frame" {
	Size = UDim2.fromScale(1, 1),

	PrimaryButton({
		text = function()
			return `Count: {count()}`
		end,
		onClick = function()
			count(count() + 1)
		end,
	}),
}
```

## Handling Props (Static vs. Reactive)

Callers may pass a static value (`"Submit"`), a reactive [Node](/guide/concepts/signals), or a getter function (`() -> string`). Annotate flexible component props with `Flux.Reactive<T>` (which accepts `T | Node<T> | () -> T`).

### 1. Passing Props Directly to Instance Properties

`Flux.new` and `Flux.edit` accept static values, nodes, and getters natively, so you can pass a `Flux.Reactive<T>` prop straight to an Instance property:

```luau
local function StatusLabel(props: { status: Flux.Reactive<string> })
	return Flux.new "TextLabel" {
		Text = props.status, -- static strings assign once, nodes and getters bind reactively
	}
end
```

### 2. Reading Node-or-Value Props with `Flux.read`

When you need to transform a `Flux.Reactive<T>` prop inside a computation, call [`Flux.read(value)`](/guide/concepts/tracking#flux-read). It reads a node or getter with tracking, or returns a plain value as-is:

```luau
local function StatusLabel(props: { status: Flux.Reactive<string> })
	return Flux.new "TextLabel" {
		Text = function()
			return `Status: {string.upper(Flux.read(props.status))}`
		end,
	}
end
```

Use `Flux.isNode(value)` when you explicitly need to check whether a value is a Flux node.

## Splitting Props with `Flux.split`

Reusable components often accept both **component-specific props** (like `label` or `accent`) and **pass-through Instance properties** (like `Size`, `Position`, `LayoutOrder`, or children) in one table.

Declare your component's own prop schema once with `Flux.prop()`, derive the full prop table type with `Flux.Props<ClassName, typeof(OWN)>`, and separate them at runtime with `Flux.split(props, OWN)`:

```luau
local OWN = {
	label = Flux.prop() :: Flux.Reactive<string>,
	accent = Flux.prop() :: Flux.Reactive<Color3>?,
	padding = Flux.prop(8), -- optional for callers, always `number` inside the component
}

type BadgeProps = Flux.Props<"TextLabel", typeof(OWN)>

local function Badge(props: BadgeProps): TextLabel
	local own, rest = Flux.split(props, OWN)

	return Flux.edit(Flux.new "TextLabel" {
		Text = function()
			return `[ {Flux.read(own.label)} ]`
		end,
		TextColor3 = Flux.fallback(own.accent, Color3.fromRGB(120, 170, 255)),
		Flux.padding(own.padding),
	})(rest)
end
```

- **Single source of truth:** `Flux.prop()` marks the key in `OWN`, while the type cast beside it gives `typeof(OWN)` and `own` (`Flux.Pick<BadgeProps, typeof(OWN)>`) their exact `--!strict` property types (keeping required props required). Pass a default value (`Flux.prop(default)`) to make a key optional in `Flux.Props` while guaranteeing a non-`nil` `default` value inside `own` whenever callers omit it or pass `nil` (plain unfrozen table defaults without metatables are deep-cloned on each `Flux.split` call so mutations don't leak across component instances). Annotated key-literal arrays like `local OWN: { "label" | "accent" } = { "label", "accent" }` also preserve exact `Pick` and `Omit` types on a single group (two or more groups widen to `Flux.Partial<T>`).
- **Pass-through forwarding:** `rest` is typed as `Flux.Omit<BadgeProps, typeof(OWN)>` and holds every remaining property, event, numeric child, and `__ATTR` / `__EVENT` / `__TAG` / `__CLEAN` directive without mutating `props`.
- **Composing schemas with `Flux.own`:** Freeze a standalone schema or merge several shared schemas into one with `Flux.own(...)`:

```luau
local BASE_OWN = Flux.own({
	gap = Flux.prop(8),
	label = Flux.prop() :: Flux.Reactive<string>,
})

local SEARCH_OWN = Flux.own(BASE_OWN, {
	placeholder = Flux.prop() :: Flux.Reactive<string>?,
})

type SearchBoxProps = Flux.Props<"TextBox", typeof(SEARCH_OWN)>
```

## Merging Props with `Flux.merge` {#merging-props-with-flux-merge}

Use `Flux.merge(...)` to build a read-only live view across 1 to 4 tables (left-to-right, where the rightmost non-`nil` value wins). It forwards component defaults alongside dynamic props without baking static copies.

```luau
local function Card(props: Flux.Props<"Frame">?)
	local resolved = Flux.merge({
		BackgroundColor3 = Color3.fromRGB(28, 30, 38),
		Size = UDim2.fromOffset(320, 180),
	}, props)

	return Flux.new "Frame"(resolved)
end
```

Indexing `resolved` forwards directly to the rightmost source table defining that key, so reactive getters, nodes, and events stay intact without cloning or eager evaluation. Because `Flux.merge` is shallow per key, rightmost numeric children and directive tables (`__ATTR`, `__TAG`, `__CLEAN`) overwrite earlier ones at the same key; wrap `{ base, rest }` as nested arrays at numeric indices or chain `Flux.edit(base)(rest)` when you want defaults and caller additions to accumulate. In `--!strict`, a non-optional key on any merged table narrows away optionality from earlier tables (`Flux.Merge<A, B>`). `Flux.new` and `Flux.edit` accept `Flux.merge(...)` views directly, or you can call `Flux.split(resolved)` to materialize a plain writable copy when needed.

## Accepting Children

Arrays placed at a numeric index inside `Flux.new` or `Flux.edit` flatten into children automatically while preserving sequential `LayoutOrder`:

```luau
local function Panel(props: { title: Flux.Reactive<string>, children: Flux.Children? })
	return Flux.new "Frame" {
		Size = UDim2.fromOffset(400, 300),
		Flux.list({ gap = 8 }),

		Flux.new "TextLabel" { Text = props.title },
		props.children, -- flattened in place
	}
end
```

## Component Scopes and Lifecycles

When you call a component inside a parent [`Flux.scope`](/guide/concepts/scopes), everything it creates attaches to that parent scope automatically.

When a standalone component creates internal Effects or resources whose lifetime should follow its own root `Instance`, wrap its body in `Flux.scope` and bind the scope to `__CLEAN`:

```luau
local function TimerLabel(): TextLabel
	local _, label = Flux.scope(function(scope)
		local elapsed = Flux.signal(0)

		Flux.cleanup(Flux.Clock.connect("Heartbeat", function(dt)
			elapsed(elapsed() + dt)
		end))

		return Flux.new "TextLabel" {
			Text = function()
				return string.format("%.1fs", elapsed())
			end,
			__CLEAN = { scope },
		}
	end)

	return label
end
```

## `--!strict` Types

Flux exports its core reactive and component types directly on the `Flux` module:

| Type | Meaning |
| :--- | :--- |
| **`Flux.State<T>`** | Writable [Signal](/guide/concepts/signals) or [SyncSignal](/guide/concepts/sync) node (`:set` is checked against `T`) |
| **`Flux.Node<T>`** | Read/lifecycle reactive node (Signals, Computeds, Effects, Scopes, Springs, Tweens) |
| **`Flux.Reactive<T>`** | `T \| Flux.Node<T> \| () -> T` (static value, node, or getter) |
| **`Flux.Unwrap<T>`** | Extracts `V` from `Node<V>`, `State<V>`, `Spring<V>`, `SyncSignal<V>`, or `() -> V` (leaves plain `T` as-is) |
| **`Flux.Props<ClassName, Extra?>`** | `Flux.new(className)` property table merged with `Extra` (your component's own props override conflicting class members) |
| **`Flux.DefaultProp<T>`** | Schema default marker produced by `Flux.prop(default)` (optional in `Props`, non-`nil` `T` in `split`) |
| **`Flux.Merge<Base, Extra>`** | Table merge where fields in `Extra` replace matching keys on `Base` |
| **`Flux.Pick<T, K>` / `Flux.Omit<T, K>` / `Flux.Partial<T>`** | Table projection helpers used by [`Flux.split`](#splitting-props-with-flux-split) |
| **`Flux.Component<P, I?>`** | `(props: P) -> I` (defaults `I` to `Instance`) |
| **`Flux.Portal`** | Portal handle returned by [`Flux.portal`](/guide/roblox/creation#portals-flux-portal) |
| **`Flux.Child` / `Flux.Children`** | Single child item, portal, or nested array accepted at numeric indices in `Flux.new` / `Flux.edit` |
| **`Flux.Cleanable`** | Any value accepted by [`Flux.cleanup`](/guide/concepts/effects#cleanup-with-flux-cleanup) and [`Flux.dispose`](/guide/concepts/scopes#disposing-by-hand-with-flux-dispose) |
| **`Flux.Owner`** | Active scope/context handle returned by [`Flux.getOwner()`](/guide/concepts/scopes#capturing-the-active-scope) |
| **`Flux.Namespace`** | Full type of the `Flux` module table (for dependency injection or plugin helpers) |
