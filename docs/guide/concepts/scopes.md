---
title: Scopes
description: Managing lifecycles and cleaning up reactive state in Flux.
outline: deep
---

# Scopes

In highly dynamic reactive systems, ensuring that unused state, effects, and UI instances are properly garbage collected is critical to preventing memory leaks. **Scopes** provide an elegant, zero-boilerplate way to manage the lifecycles of groups of reactive objects.

If you are coming from other frameworks, you can think of a Scope as a reactive root (like SolidJS's [`createRoot`](https://docs.solidjs.com/reference/reactive-utilities/create-root)) combined with a cleanup tracker (similar to Maid or Trove patterns common in Roblox development).

## Creating a Scope

Initialise a new scope using `Flux.scope()`{luau}. A Scope acts as a container; any nodes, instances, or effects created through it are automatically recorded in its internal cleanup list.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

local myScope = Flux.scope()
```

## Creating Scoped State and Effects

A Scope is callable; use it exactly like the main `Flux` function to create Values and Effects. The key difference is that everything created via the Scope is tracked for cleanup.

```luau
local myScope = Flux.scope()

-- Create a scoped Value
local count = myScope(0)

-- Create a scoped Effect
myScope(function()
    print("Scoped count is: " .. count)
end, true)

-- When this system is no longer needed:
myScope:Destroy()
-- 'count' and the Effect are cleanly disconnected and freed.
```

## Scoped UI Creation

When building dynamic UI elements that frequently mount and unmount (notifications, inventory slots, floating name tags), a Scope ensures the UI and all its reactive bindings are destroyed together safely.

Create scoped Roblox instances using `scope:new "ClassName"`{luau}. Instances created this way are automatically added to the scope's cleanup list.

```luau
local uiScope = Flux.scope()
local name = uiScope("Guest")

-- Create an instance tied to the scope's lifecycle
local label = uiScope:new "TextLabel" {
    Name = "PlayerLabel",
    Size = UDim2.fromOffset(200, 50),
    Text = Flux(function()
        return "Welcome, " .. name()
    end),
    Parent = playerGui,
}

-- Destroying the scope destroys the label and severs all reactive bindings
uiScope:Destroy()
```

You can also edit existing instances through a scope, ensuring all bound connections are cleaned up with the scope:

```luau
uiScope:edit(existingLabel) {
    BackgroundColor3 = Color3.new(1, 0, 0),
}
```

## Scope Utilities

Scopes expose direct equivalents of all the major Flux utilities. Pass the scope in instead of the global `Flux` function to have everything tracked automatically:

| Global API                      | Scope equivalent                 |
| :------------------------------ | :------------------------------- |
| `Flux(val)`{luau}               | `scope(val)`{luau}               |
| `Flux.new "Class" { }`{luau}    | `scope:new "Class" { }`{luau}    |
| `Flux.edit(inst) { }`{luau}     | `scope:edit(inst) { }`{luau}     |
| `Flux.store(tbl)`{luau}         | `scope:store(tbl)`{luau}         |
| `Flux.async(fn)`{luau}          | `scope:async(fn)`{luau}          |
| `Flux.forValue(list, fn)`{luau} | `scope:forValue(list, fn)`{luau} |
| `Flux.forIndex(list, fn)`{luau} | `scope:forIndex(list, fn)`{luau} |
| `Flux.wrap(tbl)`{luau}          | `scope:wrap(tbl)`{luau}          |

## When to Use Scopes

- **UI components** - Wrap each component in a Scope. Destroy it when the component unmounts.
- **Minigames or rounds** - Create one Scope per round. When the round ends, call `:Destroy()`{luau} to wipe all round-specific UI, state, and effects instantly.
- **Player sessions** - Tie a Scope to `Players.PlayerAdded`{lua}. Destroy it in `Players.PlayerRemoving`{lua}.
- **Modal windows** - Create a Scope when the window opens; destroy it when it closes.

## Connecting a Scope to an Instance Lifetime

A common pattern is to tie a scope's lifetime to a Roblox instance using `__CLEAN`:

```luau
local function Toast(message)
    local toastScope = Flux.scope()
    local alpha = toastScope(1)

    local frame = toastScope:new "Frame" {
        BackgroundTransparency = function() return 1 - alpha() end,
        Size = UDim2.fromOffset(300, 60),

        -- Destroy the scope when the frame is destroyed
        __CLEAN = {
            function() toastScope:Destroy() end,
        },
    }

    -- Animate out and destroy after 3 seconds
    task.delay(3, function()
        alpha(0)
        task.wait(0.4)
        frame:Destroy()
    end)

    return frame
end
```
