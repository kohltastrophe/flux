---
title: Conditional rendering
description: Mounting subtrees and selecting values reactively with show, switch, presence, pick, and fallback.
outline: deep
sidebar_position: 6
---

# Conditional rendering

Because Flux [components](/guide/concepts/components) run once, structural conditionals use dedicated helpers that mount and unmount branches in their own child [Scopes](/guide/concepts/scopes), while value-level conditionals derive nodes without mounting subtrees.

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

- **Keyed on truthiness:** Changing between two truthy values (e.g. `{ name = "Ada" }` → `{ name = "Grace" }`) keeps the mounted branch alive without rebuilding its Instances.
- **Live `value` accessor:** The truthy branch function receives a `value` getter (`() -> T`) that reads the current truthy condition reactively inside bindings.
- **Branch scope:** Every branch runs inside its own child [Scope](/guide/concepts/scopes); when the condition flips, the outgoing branch's instances, effects, and cleanups are destroyed automatically.

### Remounting on Identity Change {#keyed-show}

Use `Flux.showKeyed(source, component, fallback?)` when you want the branch to **tear down and rebuild** on every change of `source` (not just truthy/falsy transitions)—useful for resetting per-item local state like an input draft:

```luau
local selectedUser = Flux.signal(firstUser)

local editor = Flux.showKeyed(selectedUser, function(user)
	local draft = Flux.signal(user().name) -- fresh signal on every user switch
	return Flux.new "TextBox" { Text = Flux.model(draft) }
end)
```

## Switching Between Many Branches

`Flux.switch(source)(map)` keys on `source`'s value and mounts the matching factory from `map`:

```luau
local activeTab = Flux.signal("home")

local view = Flux.switch(activeTab)({
	home = HomePanel,
	settings = SettingsPanel,
	profile = ProfilePanel,
})
```

### A Catch-All Branch

Use `[Flux.otherwise]` in the branch table to provide a fallback factory when `source` matches no explicit key:

```luau
local view = Flux.switch(activeTab)({
	home = HomePanel,
	settings = SettingsPanel,
	[Flux.otherwise] = function(value)
		return Flux.new "TextLabel" {
			Text = function()
				return `Unknown tab: {value()}`
			end,
		}
	end,
})
```

Switching between two different unmatched keys reuses the single `Flux.otherwise` mount and updates its `value()` accessor in place.

## Animating Exits with `presence`{lua}

`Flux.show` and `Flux.switch` destroy an outgoing branch immediately when its condition turns falsy. To play an exit [spring](/guide/motion/spring) or [tween](/guide/motion/tween) before unmounting, use `Flux.presence(source, child)`:

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
- Calling `done()` finishes the exit and destroys the branch scope (and if `source` becomes truthy again before `done()` is called, `exiting()` flips back to `false` and the same mount stays alive).

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

All three arguments may be plain values, nodes, or getters; only the chosen branch is read.

## Defaulting a `nil` Value

Luau's `value or default` idiom treats `false` as falsy, which breaks boolean props like `enabled = false`. `Flux.fallback(value, default)` derives a node that returns `value` whenever it is non-`nil` (including `false`) and falls back to `default` only on `nil`:

```luau
local function Toggle(props: { enabled: Flux.Reactive<boolean>? })
	local isEnabled = Flux.fallback(props.enabled, true)
	-- Passing `enabled = false` keeps `false` instead of defaulting to `true`
end
```
