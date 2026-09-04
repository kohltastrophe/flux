---
title: Interact
description: Exclusive state groups and pointer hit-testing for menus, tooltips, and hover. One open menu, one hovered control, no bookkeeping.
outline: deep
sidebar_position: 3
---

# Interact

Interactive UI keeps transient state the rest of the tree must agree on: only one dropdown open, one control hovered, one dialog modal. Writing that coordination by hand means every menu knows how to close every other menu. Flux's interact helpers replace the bookkeeping with an **exclusive group** (a container guaranteeing at most one active boolean [node](/guide/concepts/signals)) plus two pointer predicates, `pointIn`{lua} and `sunk`{lua}, for hit-testing against real [`GuiObject`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject)s. (They are also available under the `Flux.Interact`{lua} namespace.)

## Exclusive groups

`Flux.exclusive()`{lua} creates a group. Members are ordinary boolean nodes (a menu's `Visible`{luau} state, a control's `hovering`{luau} state), and the group guarantees activating one deactivates whichever was active before:

```luau
local floating = Flux.exclusive() -- one group per concern, made once

floating:toggle(dropdown.Visible)    -- flip on click; opening closes any open menu
floating:activate(contextMenu.Visible) -- open explicitly (closes the dropdown)
floating:deactivate(contextMenu.Visible) -- close explicitly
floating:clear()                     -- close the active one, whichever it is
```

The semantics, precisely:

- **`activate(state)`{luau}** sets `state` to `true`{luau} and sets the previously active member to `false`{luau} (if different). Both writes land before the next flush, so effects only ever observe the settled result.
- **`deactivate(state)`{luau}** sets `state` to `false`{luau}, releasing the active slot when `state` holds it. Deactivating a member that is not active still sets it `false`{luau}, so handlers can call it unconditionally.
- **`toggle(state)`{luau}** activates when inactive, deactivates when active. The read is untracked, so toggling inside an [effect](/guide/concepts/effects) never subscribes it.
- **`clear()`{luau}** deactivates the active member, if any: the outside-click dismiss that doesn't need to know which menu is open.

Groups hold plain state, not subscriptions: members need no cleanup, and a node can freely belong to several groups.

> [!TIP]
> One group per *concern*, not per menu. A `floating`{luau} group shared by every dropdown, context menu, and select gives the "opening one closes the rest" behavior across your whole UI for free.

## `pointIn`

Whether a point lies within a `GuiObject`'s absolute bounds (inclusive). Coordinates are inset-relative, so [`InputObject.Position`](https://create.roblox.com/docs/en-us/reference/engine/classes/InputObject#Position) and `AbsolutePosition`{luau} line up:

```luau
-- Dismiss an open menu when a press lands outside it and its anchor:
if
    not Flux.pointIn(input.Position.X, input.Position.Y, menu)
    and not Flux.pointIn(input.Position.X, input.Position.Y, anchor)
then
    floating:clear()
end
```

`pointIn`{lua} reads only `AbsolutePosition`{luau}/`AbsoluteSize`{luau}: it ignores rotation and does not consider occlusion. For "is something else on top", use [`sunk`](#sunk).

## `sunk`

Whether input at a point would be claimed by an `Active`{luau} gui (or [`GuiButton`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiButton)) rendered **above** `object`. Hover states built from `InputChanged`{luau} alone stay lit when a floating menu covers the control; `sunk`{lua} is the missing test:

```luau
local hover = Flux.exclusive()
local hovering = Flux(false)

-- in the control's InputChanged handler (MouseMovement / Touch):
if Flux.sunk(input.Position.X, input.Position.Y, control) then
    hover:deactivate(hovering)
else
    hover:activate(hovering)
end

-- in InputEnded:
hover:deactivate(hovering)
```

> [!NOTE]
> `sunk`{lua} walks [`GetGuiObjectsAtPosition`](https://create.roblox.com/docs/en-us/reference/engine/classes/BasePlayerGui#GetGuiObjectsAtPosition) on the object's ancestor `BasePlayerGui`{luau}. Outside one (a plugin dock, a `SurfaceGui`{luau} in workspace) nothing can claim the point, so it yields `false`{luau}. `pointIn`{lua} and exclusive groups run anywhere, including headless Luau; `sunk`{lua} needs the engine.
