---
title: Creation
description: Declaratively building dynamic Roblox UIs and structures with Flux.
outline: deep
sidebar_position: 1
---

# Creation

`Flux.new` builds Roblox [`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) hierarchies in one declarative block. It applies per-class [defaults](/guide/roblox/defaults) and wires up reactive bindings, events, children, and directives.

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

## The `Flux.new` Function

`Flux.new "ClassName"` returns a typed constructor function that accepts a properties table:

- **Static values** assign once at construction.
- **Reactive [Nodes](/guide/concepts/signals)** (`Flux.signal`, `Flux.computed`, `Flux.spring`, etc.) bind directly to the property and update on the frame flush whenever the node changes.
- **Getter functions (`() -> T`)** wrap the property in a tracked reaction that re-evaluates whenever any node read inside it changes.
- **Events** (like `Activated`, `Touched`, or `FocusLost`) connect the assigned function via `:Connect(fn)`.

> [!IMPORTANT] Wrap Interpolated Expressions in a Function
> Passing `Text = count` binds the node directly, whereas ``Text = `Clicks: {count}` `` evaluates the string **once** at construction time. Wrap string interpolations and comparisons in a getter function so reads happen inside a tracked context:
> ```luau
> -- Evaluated once at construction:
> Text = `Clicks: {count}`,
>
> -- Re-runs whenever `count` changes:
> Text = function() return `Clicks: {count()}` end,
> ```

## Creating Hierarchies (Children)

Place child instances (or nested arrays, [`Flux.show`](/guide/concepts/conditionals), [`Flux.forValue`](/guide/concepts/mapping), or [`Flux.forKey`](/guide/concepts/mapping#flux-forkey-keyed-by-function) nodes) at **numeric indices** inside the properties table:

```luau
local actionButtons = { SaveButton, LoadButton, QuitButton }

local panel = Flux.new "Frame" {
	Name = "Menu",
	Size = UDim2.fromScale(0.5, 0.5),

	Flux.list({ gap = 6 }),
	Flux.new "TextLabel" { Text = "Main Menu" },
	actionButtons, -- arrays flatten into children in place
}
```

- **Automatic `LayoutOrder`:** Unpinned [`GuiObject`](https://create.roblox.com/docs/reference/engine/classes/GuiObject) children and reactive child-node slots get numbered sequentially (`1, 2, 3, ...`) in array order, skipping non-`GuiObject` modifiers like `UICorner` or `UIListLayout`. Any explicit `LayoutOrder` in the child's table (including `LayoutOrder = 0`) stays pinned at that value.
- **Configuration order and `Parent`:** `Flux.new` applies class [defaults](/guide/roblox/defaults), properties and prefix keys, `__ATTR` / `__TAG` / `__EVENT`, array children / `Find` / flattened tables, `__REF` (`Parent` is still `nil` here), and top-level `RBXScriptSignal` connections before assigning `Parent` (which also accepts reactive nodes or getters). Numeric `(instance) -> ()` init callbacks run via `Flux.Clock.defer` after `Parent` is set.

## Prefix Keys and Directives

Both `Flux.new` and [`Flux.edit`](/guide/roblox/hydration) accept bare `_`-prefixed identifier keys right on the properties table alongside grouped `__` directive tables (double-prefixed so they sort at the top of autocomplete above single-`_` property change listeners):

| Prefix / Key | Purpose | Example |
| :--- | :--- | :--- |
| **`_attr_Name`** / **`__ATTR`** | Sets static, reactive, or [`Flux.model`](#flux-model-two-way-binding-in-one-key) Instance attributes | `__ATTR = { Health = healthNode }` |
| **`_tag_Name`** / **`__TAG`** | Adds/removes [`CollectionService`](https://create.roblox.com/docs/reference/engine/classes/CollectionService) tags (`_tag_Name` toggles a named tag by truthiness, while `__TAG` accepts dynamic tag names or arrays) | `__TAG = { "Enemy" }` |
| **`_Prop`** / **`__EVENT`** | Connects a typed `GetPropertyChangedSignal("Prop")` listener receiving the new value | `_Text = function(text) ... end` |
| **`__attr_Name`** / **`__EVENT.__ATTR`** | Connects a `GetAttributeChangedSignal("Name")` listener receiving the new value | `__EVENT = { __ATTR = { Health = fn } }` |
| **`__tag_Name`** / **`__EVENT.__TAG`** | Connects a [`CollectionService`](https://create.roblox.com/docs/reference/engine/classes/CollectionService) tag-changed listener receiving `hasTag: boolean` | `__EVENT = { __TAG = { Enemy = fn } }` |
| **`__REF`** | Stores the created instance in a Node or passes it to a setup callback | `__REF = frameNode` |
| **`__CLEAN`** | Attaches extra cleanup items to the instance's `Destroying` lifetime | `__CLEAN = { conn }` |

> [!NOTE] Prefix Keys in `--!strict` Mode
> Property tables are sealed so Luau flags misspelled property names (`Nmae = "Hi"`). Every readable class property is pre-generated as `_PropertyName` for `--!strict` autocomplete, while open-ended `_attr_Name`, `_tag_Name`, `__attr_Name`, and `__tag_Name` suffixes require `--!nonstrict` (or an unannotated/cast table) because Luau has no template-literal key types. Use `__ATTR`, `__TAG`, and `__EVENT` in `--!strict` files.

See [Hydration: Prefix Keys & Special Directives](/guide/roblox/hydration#prefix-keys-special-directives) for full examples of each form.

### `Flux.model`: Two-Way Binding in One Key

When an input property (such as `TextBox.Text`), an attribute (`__ATTR` or `_attr_Level`), or a tag (`_tag_Selected`) should both **read from** and **write back to** the same signal node, wrap the node in `Flux.model(node)`:

```luau
local username = Flux.signal("")

local input = Flux.new "TextBox" {
	Size = UDim2.fromOffset(200, 40),
	Text = Flux.model(username),
}
```

`Flux.model` sets the property, attribute, or tag from `node` on mount, then listens to `GetPropertyChangedSignal`, `GetAttributeChangedSignal`, or `CollectionService` tag signals to update `node` whenever the instance changes. `CollectionService` tag signals fire while the instance is parented under `game` (`AncestryChanged` resyncs on parenting), and `__TAG` takes dynamic tag names rather than `Flux.model`.

When writing a custom [component](/guide/concepts/components) that accepts a two-way bound prop, type the prop as `Flux.Reactive<T>` (since `Flux.model(node)` has static type `T`). Use `Flux.isModel(value)` and `Flux.modelNode(value)` at runtime to extract the underlying `Node` when the caller opted into two-way binding:

```luau
local function CustomSlider(props: { value: Flux.Reactive<number> })
	local writable = Flux.modelNode(props.value)
	local source: any = writable or props.value
	-- Read with `Flux.read(source)` and write back with `if writable then writable(newValue) end`
end
```

## Scoped Creation

When `Flux.new` runs inside a [`Flux.scope`](/guide/concepts/scopes), that scope owns the created instance and all of its bindings, destroying them when `scope:Destroy()` runs:

```luau
local scope, banner = Flux.scope(function()
	return Flux.new "TextLabel" {
		Text = "Round starting...",
		Parent = playerGui,
	}
end)

scope:Destroy() -- destroys `banner` and all bindings
```

## Mounting a Root (`Flux.mount`) {#mounting-a-root-flux-mount}

Use `Flux.mount(fn, target?)` to mount a top-level component tree inside its own root [Scope](/guide/concepts/scopes). It returns an idempotent `unmount` function.

```luau
local unmount = Flux.mount(function()
	return Flux.new "TextLabel" {
		Text = "HUD Ready",
		Size = UDim2.fromOffset(200, 40),
	}
end, playerGui)

-- Later (when leaving the screen or shutting down a plugin):
unmount()
```

Unlike setting `Parent = target` directly, `Flux.mount` never destroys `target` when `unmount()` runs; it destroys the mounted children, reactive nodes, and child scopes while leaving `target` intact. If `target` is destroyed externally, the mounted root tears down automatically. When you omit `target`, any top-level instances returned by `fn` stay attached via their own `Parent` properties, and any returned [`Flux.portal`](#portals-flux-portal) handles mount into their targets.

## Portals (`Flux.portal`) {#portals-flux-portal}

Use `Flux.portal(target, children)` to project tooltips, modals, or HUD overlays into an external `Instance` such as a top-level `ScreenGui`. The portal keeps its reactive lifetime attached to the component or scope that created it instead of transferring ownership to `target`.

```luau
local showModal = Flux.signal(false)

local settingsRow = Flux.new "Frame" {
	Flux.show(showModal, function()
		return Flux.portal(overlayGui, {
			Flux.new "Frame" { Name = "ConfirmDialog", Size = UDim2.fromOffset(320, 180) },
		})
	end),
}
```

`target` accepts either a static `Instance` or a `Flux.Reactive<Instance?>` node or getter; switching `target` moves mounted children into the new container cleanly without destroying `target`. When the portal host or enclosing scope tears down (or when `target` resolves to `nil`), mounted children are unparented automatically.
