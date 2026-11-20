---
title: Interact
description: Reactive interaction state (hover, press, selected, focused) and pointer occlusion hit-testing for GuiObjects.
outline: deep
sidebar_position: 3
---

# Interact

`Flux.Interact` provides read-only boolean [nodes](/guide/concepts/signals) for common UI interaction states (`hover`, `press`, `selected`, `focused`) along with pointer hit-test predicates (`pointIn`, `sunk`, `covered`).

```luau
local button = Flux.new "TextButton" {
	Size = UDim2.fromOffset(180, 44),
	Text = "Play",
}

local hovered = Flux.Interact.hover(button)
local pressed = Flux.Interact.press(button)

Flux.edit(button) {
	BackgroundColor3 = function()
		if pressed() then
			return Color3.fromRGB(40, 90, 200)
		elseif hovered() then
			return Color3.fromRGB(70, 130, 255)
		end
		return Color3.fromRGB(55, 110, 230)
	end,
}
```

Every state node starts listening right away and cleans up automatically when the node, its owning [Scope](/guide/concepts/scopes), or `object` is destroyed, settling to `false`.

Occlusion hit-testing (`hover`, `sunk`, and `covered`) resolves the enclosing 2D screen-space [`BasePlayerGui`](https://create.roblox.com/docs/reference/engine/classes/BasePlayerGui) (`PlayerGui` / `StarterGui`) or Studio [`PluginGui`](https://create.roblox.com/docs/reference/engine/classes/PluginGui) (`DockWidgetPluginGui`). Inside plugin docks, `hover` queries widget-local coordinates via `PluginGui:GetRelativeMousePosition()` isolated from the main viewport (`SurfaceGui` and `BillboardGui` containers in 3D `Workspace` are not supported).

## `hover` {#hover}

`Flux.Interact.hover(object, options?)` returns a `Node<boolean>` that is `true` while a mouse pointer or touch contact is inside `object` with no input-claiming GUI drawn above it (checked via [`sunk`](#sunk)).

Because `hover` re-checks occlusion every frame while the pointer is inside `object`:
- A floating menu or modal opening on top of `object` drops the hover state right away.
- Scrolling `object` out from under a stationary pointer drops the hover state.
- Closing an obstructing overlay over a stationary pointer restores the hover state.

```luau
local hovered = Flux.Interact.hover(button)

-- Container hover: stay hovered even when the pointer is over a child button inside `row`
local rowHovered = Flux.Interact.hover(row, { within = true })
```

Pass `{ within = true }` when tracking a container (such as a card, list row, or panel) so child buttons inside `object` don't count as covering it (see [`covered`](#covered)).

## `press` {#press}

`Flux.Interact.press(object)` returns a `Node<boolean>` that is `true` while `object` is actively held down:

- **Pointer / Touch:** Starts on `MouseButton1` or `Touch` inside `object` (unless covered by an input-sinking GUI above it) and stays `true` until that specific input ends *anywhere* on screen, so dragging slightly off a button never leaves it stuck.
- **Gamepad / Keyboard:** Starts when `ButtonA`, `Return`, or `KeypadEnter` is pressed while `object` is [`GuiService.SelectedObject`](https://create.roblox.com/docs/reference/engine/classes/GuiService#SelectedObject) (and no `TextBox` has focus).
- **Focus & Menu Release:** Opening the Roblox escape menu (`GuiService.MenuIsOpen`) releases active 2D/3D presses immediately while leaving presses inside isolated `PluginGui` docks active. Active `PluginGui` presses release on `UserInputService.InputEnded`, `WindowFocusReleased` (on either `PluginGui` or `UserInputService`), or when the held input's `UserInputState` changes to `End` or `Cancel`.

```luau
local pressed = Flux.Interact.press(button)
```

## `selected` {#selected}

`Flux.Interact.selected(object)` returns a `Node<boolean>` tracking whether `object` is currently highlighted by gamepad or keyboard UI navigation ([`GuiService.SelectedObject`](https://create.roblox.com/docs/reference/engine/classes/GuiService#SelectedObject)):

```luau
local isSelected = Flux.Interact.selected(button)
```

## `focused` {#focused}

`Flux.Interact.focused(textBox)` returns a `Node<boolean>` tracking whether `textBox` currently has keyboard focus (`TextBox:IsFocused()`, `Focused`, and `FocusLost`):

```luau
local isFocused = Flux.Interact.focused(searchInput)
```

## Hit-Testing Predicates

### `pointIn` {#pointin}

`Flux.Interact.pointIn(x, y, object)` returns `true` if the top-bar-inset-relative GUI coordinate `(x, y)` (such as `input.Position.X, input.Position.Y` rather than raw `UserInputService:GetMouseLocation()`) lies within `object`'s `AbsolutePosition` and `AbsoluteSize` bounds (inclusive, ignoring rotation):

```luau
if not Flux.Interact.pointIn(input.Position.X, input.Position.Y, dropdownMenu) then
	isOpen(false)
end
```

### `sunk` {#sunk}

`Flux.Interact.sunk(x, y, object, token?)` returns `true` if input at the GUI-relative coordinate `(x, y)` would be claimed by an `Active` or input-sinking `GuiObject` rendered **above** `object` inside the same `BasePlayerGui` or `PluginGui` (or if the Roblox escape menu is open). `sunk` checks occlusion only and does not check [`pointIn`](#pointin). Pass `input` as `token` to memoize the underlying `GetGuiObjectsAtPosition` query across multiple controls on the same input event:

```luau
if not Flux.Interact.sunk(input.Position.X, input.Position.Y, control, input) then
	-- Topmost interactive control at this point
end
```

### `covered` {#covered}

`Flux.Interact.covered(x, y, object, token?)` works like [`sunk`](#sunk), except descendants of `object` don't count as covering it. Use `covered` on containers (rows, cards, draggable panels) that hold their own buttons:

```luau
if not Flux.Interact.covered(input.Position.X, input.Position.Y, cardFrame, input) then
	-- Nothing outside `cardFrame` is covering this point
end
```
