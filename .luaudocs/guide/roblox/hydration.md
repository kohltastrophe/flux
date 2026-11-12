---
title: Hydration
description: Attaching reactive state and behavior to existing Roblox instances in Flux.
outline: deep
sidebar_position: 2
---

# Hydration

When you build UI layouts visually in Roblox Studio, **`Flux.edit(instance) { ... }`** hydrates existing [`Instances`](https://create.roblox.com/docs/reference/engine/classes/Instance) with reactive property bindings, event listeners, children, and deep selectors.

```luau
local count = Flux.signal(0)
local existingButton = hudFrame:WaitForChild("CounterButton") :: TextButton

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

## The `Flux.edit` Function

`Flux.edit(instance)` returns a function that applies a properties table to `instance` and returns `instance`. Unlike `Flux.new`, `Flux.edit` never applies class [defaults](/guide/roblox/defaults). It only touches the properties, events, and children you specify.

- All bindings and event connections clean up automatically when `instance.Destroying` fires.
- If you call `Flux.edit` inside a [`Flux.scope`](/guide/concepts/scopes), that scope also owns the bindings and disconnects them when `scope:Destroy()` runs (without destroying `instance` itself).

## Prefix Keys & Special Directives

Both `Flux.edit` and [`Flux.new`](/guide/roblox/creation) support grouped `__` directive tables (`__ATTR`, `__TAG`, `__EVENT`, `__REF`, `__CLEAN`), which type-check under `--!strict`, alongside bare `_`-prefixed **prefix keys** (`_Prop` in `--!strict`, plus `_attr_Name`, `_tag_Name`, `__attr_Name`, and `__tag_Name` in `--!nonstrict` or cast tables).

### `__ATTR` and `_attr_Name` (Attributes)

Group attributes under `__ATTR` (or prefix a key with `_attr_` in `--!nonstrict` mode) to assign static values, reactive nodes, getters, or [`Flux.model`](/guide/roblox/creation#flux-model-two-way-binding-in-one-key) two-way bindings to Roblox instance attributes:

```luau
Flux.edit(character) {
	__ATTR = {
		IsStunned = false,
		Health = healthNode,
		Mana = Flux.model(manaNode),
		Class = "Warrior",
	},
}

-- In --!nonstrict files (or cast tables), _attr_Name works directly on the table:
-- _attr_Health = healthNode,
```

### `__TAG` and `_tag_Name` (`CollectionService` Tags)

Pass a dynamic tag name (or an array of static/reactive tag names) to `__TAG` under `--!strict`. In `--!nonstrict` files, prefix a tag name with `_tag_` to toggle it from a boolean, node, getter, or [`Flux.model`](/guide/roblox/creation#flux-model-two-way-binding-in-one-key) binding:

```luau
local statusTag = Flux.signal("Idle")
local lowHealthTag = function(): string?
	return if healthNode() < 25 then "LowHealth" else nil
end

Flux.edit(npcModel) {
	__TAG = { "Enemy", statusTag, lowHealthTag },
}
```

```luau
--!nonstrict
local isBoss = Flux.signal(true)

Flux.edit(npcModel) {
	_tag_Enemy = true,
	_tag_Boss = isBoss,
	_tag_LowHealth = function()
		return healthNode() < 25
	end,
}
```

Tags are reference-counted per instance so reactive tags never clobber static sibling tags. Setting an explicit initial `_tag_Name = false` (or falsy node/getter) on mount strips an unmanaged pre-existing tag on that instance.

### `_Prop`, `__EVENT`, `__attr_Name`, and `__tag_Name` (Change Listeners)

Prefix any readable property on the class with `_` (or group property, attribute, and tag listeners under `__EVENT`) to connect a `GetPropertyChangedSignal`, `GetAttributeChangedSignal`, or [`CollectionService`](https://create.roblox.com/docs/reference/engine/classes/CollectionService) tag-changed listener called with the new value on **subsequent changes** (not on mount). Every readable property appears as `_PropertyName` in `--!strict` autocomplete with its exact parameter type:

```luau
Flux.edit(existingTextBox) {
	-- Connects to GetPropertyChangedSignal("Text") (`newText` is typed as `string`):
	_Text = function(newText)
		print("Text changed to:", newText)
	end,

	-- Property, attribute, and tag listeners grouped under __EVENT (--!strict):
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

-- In --!nonstrict files, __attr_Name and __tag_Name also work as bare keys:
-- __attr_IsStunned = function(stunning) print("Stunned:", stunning) end,
-- __tag_Focused = function(hasTag) print("Focused tag:", hasTag) end,
```

`__EVENT` only accepts change callbacks; passing a `Node` or `RBXScriptSignal` inside `__EVENT` throws an error. Connect `RBXScriptSignal` events (`Activated`, `FocusLost`, etc.) directly at the top level of the table. To two-way bind a property, attribute, or tag to a signal node, use [`Flux.model(node)`](/guide/roblox/creation#flux-model-two-way-binding-in-one-key) (`Text = Flux.model(textNode)`, `__ATTR = { Score = Flux.model(scoreNode) }`, or `_tag_Selected = Flux.model(selectedNode)`). To follow an instance property, attribute, or tag as a read-only node, use [`Flux.property(instance, key)`](/guide/concepts/signals#binding-from-an-instance-property).

### `__REF` (Instance Reference)

Capture the target instance into a writable Node or pass it to a callback. Passing a signal node writes the instance on mount and leaves the node's value untouched on destroy. If a `__REF` callback returns a `Cleanable` (a connection, function, instance, or array), Flux ties that cleanup to the instance's lifetime:

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

Elements at numeric indices inside `Flux.edit` (or `Flux.new`) run in order:
1. **`Instance`s, arrays, or child-binding nodes** (`Flux.show`, `Flux.switch`, `Flux.forValue`, `Flux.forKey`, `Flux.forIndex`) are parented to the target instance with automatic sequential `LayoutOrder` for unpinned `GuiObject`s.
2. **Nested property or directive tables** flatten into the enclosing `Flux.edit` / `Flux.new` table (outer keys win when both set the same property, while `__ATTR`, `__TAG`, `__EVENT`, `__REF`, and `__CLEAN` compose).
3. **Functions** `(instance) -> ()` schedule via `Flux.Clock.defer` to run with the target instance after `Parent` is set.
4. **`Flux.Find` selectors** locate related instances and apply nested `Flux.edit` tables to them.

## Instance Selectors (`Flux.Find`)

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

Class-typed selectors (`ChildClass`, `ChildIsA`, `AncestorClass`, `AncestorIsA`) preserve strict `EditProperties<ClassName>` checking on their property table, while name, path, and query selectors accept any property table. When a single-target selector resolves to `nil`, Flux logs a warning (`Find.Query` silently skips when `0` descendants match).
