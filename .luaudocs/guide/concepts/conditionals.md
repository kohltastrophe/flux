---
title: Conditional Rendering
description: Mounting subtrees and selecting values reactively with show, switch, presence, pick, and fallback.
outline: deep
sidebar_position: 11
---

# Conditional Rendering

Because Flux [components](/guide/concepts/components) run once, structural conditionals use dedicated helpers that mount and unmount branches in their own child [Scopes](/guide/concepts/scopes). Value-level conditionals derive nodes without mounting subtrees.

| Helper | Purpose | Mounts a branch Scope? |
| :--- | :--- | :--- |
| **`Flux.show(cond, truthy, falsy?)`** | Mounts one of two subtrees based on truthiness | Yes |
| **`Flux.showKeyed(source, truthy, falsy?)`** | Remounts the subtree whenever `source`'s identity changes | Yes |
| **`Flux.switch(source)(map)`** | Mounts the subtree matching `source`'s current value | Yes |
| **`Flux.presence(source, child)`** | Keeps a branch mounted while its exit animation finishes | Yes |
| **`Flux.pick(cond, whenTrue, whenFalse?)`** | Reactive ternary between two values | No |
| **`Flux.fallback(value, default)`** | Uses `default` only when `value` is `nil` (preserves `false`) | No |

## Showing One of Two Branches

`Flux.show(condition, component, fallback?)` evaluates `condition` (a Node, getter, or value) and mounts `component` while truthy or `fallback` while falsy:

```luau
local loggedIn = Flux.signal(false)

local screen = Flux.new "Frame" {
	Size = UDim2.fromScale(1, 1),

	Flux.show(
		loggedIn,
		function()
			return Flux.new "TextLabel" { Text = "Welcome back!" }
		end,
		function()
			return Flux.new "TextButton" { Text = "Log in" }
		end
	),
}
```

- **Keyed on truthiness:** Changing between two truthy values (for example, `{ name = "Ada" }` to `{ name = "Grace" }`) keeps the mounted branch alive without rebuilding its Instances.
- **Live `value` accessor:** `component` receives `value: () -> Truthy<Flux.Unwrap<S>>` (narrowing out `nil` and `false` under `--!strict`), and `fallback` receives `value: () -> Flux.Unwrap<S>`, reading `condition`'s current value reactively inside bindings.
- **Branch scope:** Every branch runs inside its own child [Scope](/guide/concepts/scopes). When the condition flips, the outgoing branch's instances, effects, and cleanups are destroyed automatically.

### Remounting on Identity Change {#keyed-show}

Use `Flux.showKeyed(source, component, fallback?)` when you want the branch to **tear down and rebuild** on every identity change of `source` (including `false` <-> `nil` transitions on `fallback`, not only truthy/falsy flips). This resets per-item local state like an input draft whenever `source` switches:

```luau
local selectedUser = Flux.signal(firstUser)

local editor = Flux.showKeyed(selectedUser, function(user)
	local draft = Flux.signal(user().name) -- fresh signal on every user switch
	return Flux.new "TextBox" { Text = Flux.model(draft) }
end)
```

## Switching Between Many Branches

`Flux.switch(source)(map)` keys on `source`'s value and mounts the matching `(value: () -> S) -> T` factory from `map`. Wrap components that expect a `props` table (or `0` arguments) in `function() return Panel(...) end` so `switch`'s `value` getter isn't forwarded as `props`:

```luau
local activeTab = Flux.signal("home")

local view = Flux.switch(activeTab)({
	home = function(): GuiObject
		return HomePanel()
	end,
	settings = function(): GuiObject
		return SettingsPanel()
	end,
	profile = function(): GuiObject
		return ProfilePanel()
	end,
})
```

### A Catch-All Branch

Use `[Flux.otherwise]` in the branch table to provide a fallback factory when `source` matches no explicit key. Under `--!strict`, annotate the branch return type as `GuiObject` when branches return different classes:

```luau
local view = Flux.switch(activeTab)({
	home = function(): GuiObject
		return HomePanel()
	end,
	settings = function(): GuiObject
		return SettingsPanel()
	end,
	[Flux.otherwise] = function(value): GuiObject
		return Flux.new "TextLabel" {
			Text = function()
				return `Unknown tab: {value()}`
			end,
		}
	end,
})
```

Switching between two different unmatched keys reuses the single `Flux.otherwise` mount and updates its `value()` accessor in place.

## Animating Exits with `presence`

`Flux.show` and `Flux.switch` destroy an outgoing branch right away when its condition turns falsy. To play an exit [spring](/guide/motion/spring) or [tween](/guide/motion/tween) before unmounting, use `Flux.presence(source, child)`:

```luau
local open = Flux.signal(true)

local modal = Flux.presence(open, function(exiting, done)
	local alpha = Flux.tween(function()
		return if exiting() then 1 else 0
	end, TweenInfo.new(0.2))

	-- Unmount once the fade-out reaches 1
	Flux.effect(function()
		if exiting() and alpha() >= 0.99 then
			done()
		end
	end)

	return Flux.new "Frame" {
		BackgroundTransparency = alpha,
		Size = UDim2.fromOffset(300, 200),
	}
end)
```

- While `source` is truthy, `child(exiting, done)` mounts with `exiting()` set to `false`.
- When `source` turns falsy, the branch **stays mounted** and `exiting()` flips to `true`.
- Calling `done()` finishes the exit and destroys the branch scope. If `source` turns truthy again before `done()` runs, `exiting()` flips back to `false` and the same mount stays alive.

## Picking Between Values

When you only need to choose between two **values** (colors, sizes, strings) rather than mounting Instance subtrees, use `Flux.pick(condition, whenTrue, whenFalse?)`. It returns a lightweight Computed node without creating branch scopes:

```luau
local active = Flux.signal(false)

local bgColor = Flux.pick(
	active,
	Color3.fromRGB(0, 120, 255),
	Color3.fromRGB(40, 40, 45)
)
```

All three arguments can be plain values, nodes, or getters. Only the chosen branch is read.

## Defaulting a `nil` Value

Luau's `value or default` idiom treats `false` as falsy, which breaks boolean props like `enabled = false`. `Flux.fallback(value, default)` derives a node that returns `value` whenever it's non-`nil` (including `false`) and falls back to `default` only on `nil`:

```luau
local function Toggle(props: { enabled: Flux.Reactive<boolean>? })
	local isEnabled = Flux.fallback(props.enabled, true)
	-- Passing `enabled = false` keeps `false` instead of defaulting to `true`
end
```
