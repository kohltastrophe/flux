---
title: Context
description: Passing dependencies down a component tree with dynamically-scoped values.
outline: deep
sidebar_position: 9
---

# Context

`Flux.context(default)` passes shared values (themes, services, or active user state) down a [component](/guide/concepts/components) tree without threading props through every intermediate function.

```luau
local ThemeContext = Flux.context({
	background = Color3.fromRGB(20, 20, 24),
	text = Color3.fromRGB(235, 235, 235),
	accent = Color3.fromRGB(120, 170, 255),
})

local function ThemedButton(label: string)
	local theme = ThemeContext:get()
	return Flux.new "TextButton" {
		BackgroundColor3 = theme.accent,
		TextColor3 = theme.text,
		Text = label,
	}
end

local button = ThemeContext:provide({
	background = Color3.fromRGB(40, 20, 60),
	text = Color3.fromRGB(255, 235, 245),
	accent = Color3.fromRGB(255, 120, 200),
}, function()
	return ThemedButton("Play")
end)
```

## Creating a Context

Call `Flux.context(default)` with a fallback value returned whenever no `provide` is active. The context value is opaque—it can be a plain table, a primitive, a [Signal](/guide/concepts/signals), or a [Store](/guide/concepts/stores).

## Providing and Reading

- **`context:provide(value, fn)`** runs `fn` with this context set to `value`, then restores the previous value when `fn` returns (or throws).
- **`context:get()`** returns the value from the innermost active `provide`, or `context.default` if none is active.

 Every [Computed](/guide/concepts/computeds), [Effect](/guide/concepts/effects), [Scope](/guide/concepts/scopes), property binding, and event handler in `Flux.new` / `Flux.edit` **remembers the context values active where it was created**, so later re-runs continue reading the provided value:

```luau
local Theme = Flux.context("dark")
local count = Flux.signal(0)

local label = Theme:provide("light", function()
	return Flux.new "TextLabel" {
		-- Re-runs when `count` changes and still reads `"light"`
		Text = function()
			return `[{Theme:get()}] Clicks: {count()}`
		end,
	}
end)
```

## Reactive State in Context

A context slot itself is not a reactive node—`provide` sets which value a subtree receives at construction time. When the provided value needs to change dynamically over time, provide a [Signal](/guide/concepts/signals) or [Store](/guide/concepts/stores) as the context value:

```luau
local AccentContext = Flux.context(Flux.signal(Color3.fromRGB(120, 170, 255)))

local function ActionButton()
	local accent = AccentContext:get() -- Node<Color3>
	return Flux.new "TextButton" {
		BackgroundColor3 = accent, -- bound reactively
		Text = "Confirm",
	}
end
```

## Deferred Code

Computeds, Effects, Scopes, and event handlers declared inside `Flux.new` / `Flux.edit` capture the active context automatically.

When you register a callback **outside** Flux—such as a manual `RBXScriptSignal:Connect`, a `task.delay` timer, or a callback handed to a third-party module—wrap it with `Flux.bindContext(fn)` (or [`Flux.withOwner`](/guide/concepts/scopes#capturing-the-active-scope)) so it runs with the context active where it was wrapped:

```luau
local onDelayedOpen = Flux.bindContext(function()
	-- Reads the ThemeContext value that was active when `onDelayedOpen` was created
	local theme = ThemeContext:get()
	openDialogWithTheme(theme)
end)

task.delay(2, onDelayedOpen)
```
