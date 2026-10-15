---
title: Creation
description: Declaratively building dynamic Roblox UIs and structures with Flux.
outline: deep
sidebar_position: 1
---

# Creation

`Flux.new` builds Roblox [`Instance`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance) hierarchies in a single declarative block, applying per-class [defaults](/guide/roblox/defaults) and wiring reactive bindings, events, children, and directives.

```luau
local count = Flux.signal(0)

local button = Flux.new "TextButton" {
	Name = "CounterButton",
	Size = UDim2.fromOffset(200, 50),
	BackgroundColor3 = Color3.fromRGB(0, 120, 255),
	Text = function()
		return `Clicks: {count()}`
	end,
	Activated = function()
		count(count() + 1)
	end,
}
```

## The `Flux.new`{lua} Function

`Flux.new "ClassName"` returns a typed constructor function that accepts a properties table:

- **Static values** are assigned once at construction.
- **Reactive [Nodes](/guide/concepts/signals)** (`Flux.signal`, `Flux.computed`, `Flux.spring`, etc.) bind directly to the property and update on the frame flush whenever the node changes.
- **Getter functions (`() -> T`)** wrap the property in a tracked reaction that re-evaluates whenever any node read inside it changes.
- **Events** (like `Activated`, `Touched`, or `FocusLost`) connect the assigned function via `:Connect(fn)`.

> [!IMPORTANT] Wrap Interpolated Expressions in a Function
> Passing `Text = count` binds the node directly, whereas `Text = `Clicks: {count}`` evaluates the string **once** at construction time. Wrap string interpolations and comparisons in a getter function so reads happen inside a tracked context:
> ```luau
> -- Evaluated once at construction:
> Text = `Clicks: {count}`,
>
> -- Re-runs whenever `count` changes:
> Text = function() return `Clicks: {count()}` end,
> ```

## Creating Hierarchies (Children)

Place child instances (or nested arrays / [`Flux.show`](/guide/concepts/conditionals) / [`Flux.forValue`](/guide/concepts/mapping) nodes) at **numeric indices** inside the properties table:

```luau
local actionButtons = { SaveButton, LoadButton, QuitButton }

local panel = Flux.new "Frame" {
	Name = "Menu",
	Size = UDim2.fromScale(0.5, 0.5),

	Flux.list({ gap = 6 }),
	Flux.new "TextLabel" { Text = "Main Menu" },
	actionButtons, -- arrays are flattened into children in place
}
```

- **Automatic `LayoutOrder`:** Any [`GuiObject`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject) child whose `LayoutOrder` is still at its default `0` is automatically numbered sequentially (`1, 2, 3, ...`) in array order. Explicit non-zero `LayoutOrder` values are left untouched.
- **`Parent` is assigned last:** If you include `Parent = container` in the table, Flux assigns `Parent` only after all properties, events, and children are configured.

## Prefix Keys and Directives

Both `Flux.new` and [`Flux.edit`](/guide/roblox/hydration) accept bare `_`-prefixed identifier keys right on the properties table (with editor autocomplete for `_attr_`, `_tag_`, `__attr_`, `__tag_`, and every `_Property` on the class), as well as grouped `__` directive tables (double-prefixed so they sort at the top of autocomplete above single-`_` property change listeners):

| Prefix / Key | Purpose | Example |
| :--- | :--- | :--- |
| **`_attr_Name`** / **`__ATTR`** | Sets static, reactive, or [`Flux.model`](#flux-model-two-way-binding-in-one-key) Instance attributes | `_attr_Health = healthNode` |
| **`_tag_Name`** / **`__TAG`** | Adds/removes [`CollectionService`](https://create.roblox.com/docs/en-us/reference/engine/classes/CollectionService) tags (`_tag_Name` toggles a named tag by truthiness; `__TAG` accepts dynamic tag names or arrays) | `_tag_Enemy = isAlive` |
| **`_Prop`** / **`__EVENT`** | Connects a typed `GetPropertyChangedSignal("Prop")` listener receiving the new value | `_Text = function(text) ... end` |
| **`__attr_Name`** / **`__EVENT.__ATTR`** | Connects a `GetAttributeChangedSignal("Name")` listener receiving the new value | `__attr_Health = function(hp) ... end` |
| **`__tag_Name`** / **`__EVENT.__TAG`** | Connects a [`CollectionService`](https://create.roblox.com/docs/en-us/reference/engine/classes/CollectionService) tag-changed listener receiving `hasTag: boolean` | `__tag_Enemy = function(has) ... end` |
| **`__REF`** | Stores the created instance in a Node or passes it to a setup callback | `__REF = frameNode` |
| **`__CLEAN`** | Attaches extra cleanup items to the instance's `Destroying` lifetime | `__CLEAN = { conn }` |

See [Hydration: Prefix Keys & Special Directives](/guide/roblox/hydration#prefix-keys-special-directives) for full examples of each form.

### `Flux.model`{lua}: Two-Way Binding in One Key

When an input property (such as `TextBox.Text`), an attribute (`_attr_Level`), or a tag (`_tag_Selected`) should both **read from** and **write back to** the same signal node, wrap the node in `Flux.model(node)`:

```luau
local username = Flux.signal("")

local input = Flux.new "TextBox" {
	Size = UDim2.fromOffset(200, 40),
	Text = Flux.model(username),
}
```

`Flux.model` sets the property, attribute, or tag from `node` on mount, then listens to `GetPropertyChangedSignal`, `GetAttributeChangedSignal`, or `CollectionService` tag signals to update `node` whenever the instance changes.

When writing a custom [component](/guide/concepts/components) that accepts a two-way bound prop, use `Flux.isModel(value)` to check for a `Flux.model` wrapper and `Flux.modelNode(value)` to extract the underlying `Node<T>` so your component can write back to it:

```luau
local function CustomSlider(props: { value: any })
	local node = if Flux.isModel(props.value) then Flux.modelNode(props.value) else props.value
	-- Read with `Flux.read(node)` and write back with `node(newValue)`
end
```

## Scoped Creation

When `Flux.new` runs inside a [`Flux.scope`](/guide/concepts/scopes), the created instance and all of its bindings belong to that scope and are destroyed when `scope:Destroy()` is called:

```luau
local scope, banner = Flux.scope(function()
	return Flux.new "TextLabel" {
		Text = "Round starting...",
		Parent = playerGui,
	}
end)

scope:Destroy() -- destroys `banner` and all bindings
```
