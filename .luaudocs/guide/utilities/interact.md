---
title: Interact
description: Reactive interaction state (hover, press, selected, focused) and pointer occlusion hit-testing for GuiObjects.
outline: deep
sidebar_position: 3
---

# Interact

`Flux.Interact`{luau} provides read-only boolean [nodes](/guide/concepts/signals) for common UI interaction states (`hover`{luau}, `press`{luau}, `selected`{luau}, `focused`{luau}) along with pointer hit-test predicates (`pointIn`{luau}, `sunk`{luau}, `covered`{luau}).

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

Every state node starts listening immediately and cleans up automatically when the node, its owning [Scope](/guide/concepts/scopes), or `object`{luau} is destroyed, settling to `false`{luau}.

## `hover` {#hover}

`Flux.Interact.hover(object, options?)`{luau} returns a `Node<boolean>`{luau} that is `true`{luau} while a mouse pointer or touch contact is inside `object`{luau} with no input-claiming GUI drawn above it (checked via [`sunk`](#sunk)).

Because `hover`{luau} re-checks occlusion every frame while the pointer is inside `object`{luau}:
- A floating menu or modal opening on top of `object`{luau} immediately drops the hover state.
- Scrolling `object`{luau} out from under a stationary pointer drops the hover state.
- Closing an obstructing overlay over a stationary pointer restores the hover state.

```luau
local hovered = Flux.Interact.hover(button)

-- Container hover: stay hovered even when the pointer is over a child button inside `row`
local rowHovered = Flux.Interact.hover(row, { within = true })
```

Pass `{ within = true }`{luau} when tracking a container (such as a card, list row, or panel) so child buttons inside `object`{luau} do not count as covering it (see [`covered`](#covered)).

## `press` {#press}

`Flux.Interact.press(object)`{luau} returns a `Node<boolean>`{luau} that is `true`{luau} while `object`{luau} is actively held down:

- **Pointer / Touch:** Starts on `MouseButton1`{luau} or `Touch`{luau} inside `object`{luau} (unless covered by an input-sinking GUI above it) and remains `true`{luau} until that specific input ends *anywhere* on screen, so dragging slightly off a button never leaves it stuck.
- **Gamepad / Keyboard:** Starts when `ButtonA`{luau}, `Return`{luau}, or `KeypadEnter`{luau} is pressed while `object`{luau} is [`GuiService.SelectedObject`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiService#SelectedObject) (and no `TextBox`{luau} has focus).
- Opening the Roblox escape menu (`GuiService.MenuIsOpen`{luau}) releases any active press immediately.

```luau
local pressed = Flux.Interact.press(button)
```

## `selected` {#selected}

`Flux.Interact.selected(object)`{luau} returns a `Node<boolean>`{luau} tracking whether `object`{luau} is currently highlighted by gamepad or keyboard UI navigation ([`GuiService.SelectedObject`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiService#SelectedObject)):

```luau
local isSelected = Flux.Interact.selected(button)
```

## `focused` {#focused}

`Flux.Interact.focused(textBox)`{luau} returns a `Node<boolean>`{luau} tracking whether `textBox`{luau} currently has keyboard focus (`TextBox:IsFocused()`{luau}, `Focused`{luau}, and `FocusLost`{luau}):

```luau
local isFocused = Flux.Interact.focused(searchInput)
```

## Hit-Testing Predicates

### `pointIn` {#pointin}

`Flux.Interact.pointIn(x, y, object)`{luau} returns `true`{luau} if the inset-relative coordinate `(x, y)`{luau} lies within `object`{luau}'s `AbsolutePosition`{luau} and `AbsoluteSize`{luau} bounds (inclusive, ignoring rotation):

```luau
if not Flux.Interact.pointIn(input.Position.X, input.Position.Y, dropdownMenu) then
    isOpen(false)
end
```

### `sunk` {#sunk}

`Flux.Interact.sunk(x, y, object, token?)`{luau} returns `true`{luau} if input at `(x, y)`{luau} would be claimed by an `Active`{luau} or input-sinking `GuiObject`{luau} rendered **above** `object`{luau} (or if the Roblox escape menu is open). Pass `input`{luau} as `token`{luau} to memoize the underlying `GetGuiObjectsAtPosition`{luau} query across multiple controls on the same input event:

```luau
if not Flux.Interact.sunk(input.Position.X, input.Position.Y, control, input) then
    -- Topmost interactive control at this point
end
```

### `covered` {#covered}

`Flux.Interact.covered(x, y, object, token?)`{luau} is identical to [`sunk`](#sunk), except descendants of `object`{luau} do not count as covering it. Use `covered`{luau} on containers (rows, cards, draggable panels) that contain their own buttons:

```luau
if not Flux.Interact.covered(input.Position.X, input.Position.Y, cardFrame, input) then
    -- Nothing outside `cardFrame` is covering this point
end
```
