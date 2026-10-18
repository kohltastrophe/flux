---
title: Hydration (Editing)
description: Attaching reactive state and behavior to existing Roblox instances in Flux.
outline: deep
sidebar_position: 2
---

# Hydration

When you build UI layouts visually in Roblox Studio, **`Flux.edit(instance) { ... }`** hydrates pre-existing [`Instances`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance) with reactive property bindings, event listeners, children, and deep selectors.

```luau
local count = Flux.signal(0)
local existingButton = script.Parent.CounterButton

Flux.edit(existingButton) {
	BackgroundColor3 = Color3.fromRGB(45, 45, 50),
	Text = function()
		return `Count: {count()}`
	end,
	Activated = function()
		count(count() + 1)
	end,
}
```

## The `Flux.edit`{lua} Function

`Flux.edit(instance)` returns a function that applies a properties table to `instance` and returns `instance`. Unlike `Flux.new`, `Flux.edit` never applies class [defaults](/guide/roblox/defaults); it only touches the properties, events, and children you specify.

- All bindings and event connections are automatically cleaned up when `instance.Destroying` fires.
- If `Flux.edit` is called inside a [`Flux.scope`](/guide/concepts/scopes), the bindings are also owned by that scope and disconnect when `scope:Destroy()` is called (without destroying `instance` itself).

## Prefix Keys & Special Directives

Both `Flux.edit` and [`Flux.new`](/guide/roblox/creation) support bare `_`-prefixed **prefix keys** (`_Prop`, `_attr_Name`, `__attr_Name`, `_tag_Name`, `__tag_Name`) alongside grouped `__` directive tables (`__ATTR`, `__TAG`, `__EVENT`, `__REF`, `__CLEAN`).

### `_attr_Name` and `__ATTR` (Attributes)

Prefix a key with `_attr_` (or group multiple attributes under `__ATTR`) to assign static values, reactive nodes, getters, or [`Flux.model`](/guide/roblox/creation#flux-model-two-way-binding-in-one-key) two-way bindings to Roblox instance attributes:

```luau
Flux.edit(character) {
	_attr_IsStunned = false,
	_attr_Health = healthNode,
	_attr_Mana = Flux.model(manaNode),

	-- Or grouped in __ATTR:
	__ATTR = {
		Class = "Warrior",
	},
}
```

### `_tag_Name` and `__TAG` (`CollectionService` Tags)

Prefix a tag name with `_tag_` to toggle that tag on or off from a boolean, reactive node, getter function, or [`Flux.model`](/guide/roblox/creation#flux-model-two-way-binding-in-one-key) two-way binding. When a single node holds a dynamic tag name (or an array of tag names), pass it to `__TAG`:

```luau
local isBoss = Flux.signal(true)
local statusTag = Flux.signal("Idle")

Flux.edit(npcModel) {
	_tag_Enemy = true,
	_tag_Boss = isBoss,
	_tag_LowHealth = function()
		return healthNode() < 25
	end,

	-- Dynamic tag names or arrays use __TAG:
	__TAG = { statusTag },
}
```

Tags are reference-counted per instance so reactive tags never clobber static sibling tags, while an explicit initial `_tag_Name = false` on `Flux.edit` strips an unmanaged pre-existing tag.

### `_Prop`, `__attr_Name`, `__tag_Name`, and `__EVENT` (Change Listeners)

Prefix a property name with `_` (or an attribute name with `__attr_` / a tag name with `__tag_`) to connect a `GetPropertyChangedSignal`, `GetAttributeChangedSignal`, or `CollectionService` tag-changed listener called with the new value. Every readable property on the class appears as `_PropertyName` in autocomplete with its exact parameter type:

```luau
Flux.edit(existingTextBox) {
	-- Connects to GetPropertyChangedSignal("Text"); `newText` is typed as `string`:
	_Text = function(newText)
		print("Text changed to:", newText)
	end,

	-- Connects to GetAttributeChangedSignal("IsStunned"):
	__attr_IsStunned = function(stunning)
		print("Stunned:", stunning)
	end,

	-- Connects to CollectionService tag signals for "Focused"; `hasTag` is `boolean`:
	__tag_Focused = function(hasTag)
		print("Focused tag:", hasTag)
	end,

	-- Or grouped under __EVENT:
	__EVENT = {
		BackgroundColor3 = function(color)
			print("Color changed:", color)
		end,
		__ATTR = {
			Score = function(score)
				print("Score changed:", score)
			end,
		},
		__TAG = {
			Highlighted = function(hasTag)
				print("Highlighted tag:", hasTag)
			end,
		},
	},
}
```

> [!TIP]
> To two-way bind a property, attribute, or tag to a signal node, use [`Flux.model(node)`](/guide/roblox/creation#flux-model-two-way-binding-in-one-key) (`Text = Flux.model(textNode)`, `_attr_Score = Flux.model(scoreNode)`, or `_tag_Selected = Flux.model(selectedNode)`). To follow an instance property, attribute, or tag as a read-only node, use [`Flux.property(instance, key)`](/guide/concepts/signals#binding-from-an-instance-property).

### `__REF` (Instance Reference)

Capture the target instance into a writable Node or pass it to a callback. If a `__REF` callback returns a `Cleanable` (a connection, function, instance, or array), Flux ties that cleanup to the instance's lifetime:

```luau
local frameRef = Flux.signal(nil :: Frame?)

Flux.edit(existingFrame) {
	__REF = frameRef,
}
```

### `__CLEAN` (Lifecycle Cleanup)

Attach extra `Cleanable` items (connections, instances, functions, scopes, or arrays) to run when the instance is destroyed (or when the enclosing `Flux.scope` tears down):

```luau
Flux.edit(existingFrame) {
	__CLEAN = {
		RunService.PreRender:Connect(onFrame),
		function()
			print("Frame cleaned up")
		end,
	},
}
```

## Array Elements (Children & Deferred Actions)

Elements at numeric indices inside `Flux.edit` (or `Flux.new`) are processed in order:
1. **`Instance`s, arrays, or child-binding nodes** (`Flux.show`, `Flux.forValue`, `Flux.forIndex`) are parented to the target instance with automatic sequential `LayoutOrder`.
2. **Functions** `(instance) -> ()` are scheduled via `task.defer` to run with the target instance after all properties and children are applied.
3. **`Flux.Find` selectors** locate related instances and apply nested `Flux.edit` tables to them.

## Instance Selectors (`Flux.Find`{lua})

When hydrating a Studio hierarchy, place `Flux.Find` selectors at numeric indices to target children, descendants, or ancestors inline without separate `FindFirstChild` boilerplate:

```luau
local Find = Flux.Find
local isMuted = Flux.signal(false)

Flux.edit(settingsMenu) {
	Visible = true,

	Find.Child "CloseButton" {
		Activated = function()
			settingsMenu.Visible = false
		end,
	},

	Find.Descendant "MuteToggle" {
		BackgroundColor3 = Flux.pick(isMuted, Color3.new(1, 0.3, 0.3), Color3.new(0.2, 0.8, 0.4)),
		Activated = function()
			isMuted(not isMuted())
		end,
	},

	Find.Path "Header.Title" {
		Text = "Audio Settings",
	},

	Find.QueryFirst "UIListLayout" {
		Padding = UDim.new(0, 10),
	},
}
```

### Available Selectors

| Selector | Resolves Via |
| :--- | :--- |
| **`Find.Child(name)`** | `instance:FindFirstChild(name)` |
| **`Find.ChildClass(className)`** | `instance:FindFirstChildOfClass(className)` |
| **`Find.ChildIsA(className)`** | `instance:FindFirstChildWhichIsA(className)` |
| **`Find.Descendant(name)`** | `instance:FindFirstChild(name, true)` |
| **`Find.Ancestor(name)`** | `instance:FindFirstAncestor(name)` |
| **`Find.AncestorClass(className)`** | `instance:FindFirstAncestorOfClass(className)` |
| **`Find.AncestorIsA(className)`** | `instance:FindFirstAncestorWhichIsA(className)` |
| **`Find.Parent()`** | `instance.Parent` |
| **`Find.Path(path)`** | Walks `.`-separated child names (`^` or `Parent` climbs up one level) |
| **`Find.Query(selector)`** | `instance:QueryDescendants(selector)` (applies to all matches) |
| **`Find.QueryFirst(selector)`** | `instance:QueryDescendants(selector)[1]` |
