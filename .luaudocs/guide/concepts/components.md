---
title: Components
description: Building reusable, strictly-typed UI components in Flux.
outline: deep
sidebar_position: 5
---

# Components

In Flux, **components are plain Luau functions** that run **once** to construct Roblox [`Instances`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance) and wire up reactive bindings.

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
		Activated = props.onClick,
	}
end
```

When state changes, `PrimaryButton` itself never re-executes—only the bound `Text` property updates.

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
		Text = props.status, -- static string assigned once; node or getter bound reactively
	}
end
```

### 2. Reading Node-or-Value Props with `Flux.read`{lua}

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

## Splitting Props with `Flux.split`{lua}

Reusable components often accept both **component-specific props** (like `label` or `variant`) and **pass-through Instance properties** (like `Size`, `Position`, `LayoutOrder`, or children) in a single table.

Combine `Flux.Props<ClassName, Extra>` with `Flux.split(props, keys)` to separate your component's own keys from the rest and forward the remaining table to `Flux.new`:

```luau
type BadgeProps = Flux.Props<"TextLabel", {
	label: Flux.Reactive<string>,
	accent: Flux.Reactive<Color3>?,
}>

local OWN: { "label" | "accent" } = { "label", "accent" }

local function Badge(props: BadgeProps): TextLabel
	local own, rest = Flux.split(props, OWN)

	return Flux.edit(Flux.new "TextLabel" {
		Text = function()
			return `[ {Flux.read(own.label)} ]`
		end,
		TextColor3 = Flux.fallback(own.accent, Color3.fromRGB(120, 170, 255)),
	})(rest)
end
```

- **Typed `Pick` and `Omit`:** With a single typed key group (either an annotated literal array like `local OWN: { "label" | "accent" }` or a schema table), `own` is typed as `Flux.Pick<Props, Keys>` and `rest` as `Flux.Omit<Props, Keys>`, keeping required props required.
- **Multiple groups:** You can pass multiple key groups (`local a, b, rest = Flux.split(props, KEYS_A, KEYS_B)`); each group receives its matching keys and the final return holds everything else (including numeric children and `__ATTR`/`__EVENT`/`__TAG`/`__CLEAN` directives).
- **Non-mutating:** `props` itself is never mutated.

## Accepting Children

Arrays placed at a numeric index inside `Flux.new` or `Flux.edit` are flattened into children automatically, preserving sequential `LayoutOrder`:

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

When a component is called inside a parent [`Flux.scope`](/guide/concepts/scopes), everything it creates attaches to that parent scope automatically.

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
