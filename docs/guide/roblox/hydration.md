---
title: Hydration (Editing)
description: Attaching reactive state and behavior to existing Roblox instances in Flux.
outline: deep
---

# Hydration

In traditional web development, "hydration" is the process of attaching event listeners and reactive state to static HTML that was already rendered by the server.

In Roblox development, you often build UI layouts visually in Roblox Studio. Instead of recreating these hierarchies entirely in code with `Flux.new`{lua}, you can use **`Flux.edit`{lua}** to "hydrate" existing instances. This applies reactive properties, event connections, and lifecycle management to pre-existing [`Instances`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance) with zero boilerplate.

## The `Flux.edit`{lua} Function

`Flux.edit`{lua} is a curried function. Call it with an instance (and an optional scope) to receive a constructor function, then call that constructor with your properties table.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

local count = Flux(0)
local existingButton = script.Parent.CounterButton

-- Hydrate the static instance with reactive state and events
Flux.edit(existingButton) {
    -- Static properties are assigned immediately
    BackgroundColor3 = Color3.fromRGB(45, 45, 45),

    -- Reactive nodes update the property automatically
    Text = function()
        return "Count: " .. count
    end,

    -- Signals are automatically connected
    Activated = function()
        count(count + 1)
    end,
}
```

> [!NOTE] Curried syntax reminder:
> `Flux.edit(instance) { props }`{luau} is equivalent to `Flux.edit(instance)({ props })`{luau}
>
> This is standard Luau syntax sugar for passing a table to a function, identical to how `Flux.new`{lua} works.

To attach a scope for lifecycle management, pass it as the second argument:

```luau
local myScope = Flux.scope()
Flux.edit(existingButton, myScope) {
    Text = someNode,
}
```

## Special Directives

To handle Roblox's unique instance architecture efficiently, `Flux.edit`{lua} supports several reserved keys within the properties table.

### `__ATTR` (Attributes)

Roblox Attributes allow you to tag instances with custom metadata. Use the `__ATTR` table to set attributes or bind them to reactive nodes.

```luau
Flux.edit(playerCharacter) {
    __ATTR = {
        IsStunned = true,            -- static assignment
        Health    = reactiveHealthNode, -- binds the attribute to update with the node
    },
}
```

### `__EVENT` (Two-Way Binding & Listeners)

While standard [`RBXScriptSignals`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/RBXScriptSignal) (like [`Activated`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiButton#Activated) or [`Touched`](https://create.roblox.com/docs/en-us/reference/engine/classes/BasePart#Touched)) can be connected directly as top-level properties, the `__EVENT` table is used for two-way data binding and [`GetPropertyChangedSignal(property)`{luau}](https://create.roblox.com/docs/en-us/reference/engine/classes/Object#GetPropertyChangedSignal) listeners.

- Assigning a **reactive node** to a property key makes the node receive the instance's property value whenever it changes (binding _from_ the instance _into_ the node).
- Assigning a **function** to a property key connects `GetPropertyChangedSignal(property)`{luau}.
- Assigning a **node or function** inside `__EVENT.__ATTR`{luau} does the same for attributes.

```luau
local textInputNode = Flux("")

Flux.edit(existingTextBox) {
    __EVENT = {
        -- Updates 'textInputNode' whenever the TextBox's Text property changes
        Text = textInputNode,

        -- Listen to a specific property change
        BackgroundColor3 = function()
            print("Color changed!")
        end,

        -- Attribute change listeners
        __ATTR = {
            IsStunned = function(newValue)
                print("Stun state changed:", newValue)
            end,
        },
    },
}
```

### `__CLEAN` (Lifecycle Cleanup)

`Flux.edit`{lua} automatically cleans up its own reactive bindings and event connections when the instance is destroyed. If you have additional external connections or objects that should be tied to the same lifecycle, add them to the `__CLEAN` table.

Flux will append its own cleanup items to the table you provide and flush the entire table when the instance's [`Destroying`](https://create.roblox.com/docs/en-us/reference/engine/classes/Instance#Destroying) event fires.

```luau
local RunService = game:GetService("RunService")

local myConnections = {}
table.insert(myConnections, RunService.RenderStepped:Connect(function()
    -- Custom per-frame logic
end))

Flux.edit(existingFrame) {
    BackgroundColor3 = Color3.new(0, 0, 0),

    Activated = function()
        print("Clicked!")
    end,

    -- Flux will clean up everything in this table when the frame is destroyed
    __CLEAN = myConnections,
}

-- When existingFrame:Destroy() is called:
-- 1. The 'Activated' connection is disconnected.
-- 2. The custom 'RenderStepped' connection is also safely disconnected.
```

> [!NOTE]
> If you are editing inside a `Scope`, the `__CLEAN` table is also registered to that scope's master cleanup list, ensuring safe destruction even if the scope is wiped before the instance is manually destroyed.

### `__REF` (Reference)

Sometimes you need a direct reference to the instance you are hydrating. Pass a callback function or a reactive node to `__REF`.

```luau
local myFrameNode = Flux(nil)

Flux.edit(existingFrame) {
    -- Assigns the instance directly to the reactive node
    __REF = myFrameNode,

    -- OR use a callback:
    -- __REF = function(inst)
    --     print("Hydrated:", inst.Name)
    -- end,
}
```

## Array Elements (Children & Actions)

The array portion of the properties table (elements with numeric indices) serves two purposes.

### 1. Parenting Children

Any Roblox `Instance` placed at a numeric index will automatically have its `Parent` set to the edited instance.

> [!NOTE]
> If the child is a `GuiObject` and its `LayoutOrder` is `0`, Flux automatically assigns it to the element's numeric index, saving you from setting `LayoutOrder` on every child manually.

### 2. Deferred Actions

A **function** at a numeric index is deferred via [`task.defer`{lua}](https://create.roblox.com/docs/reference/engine/libraries/task#defer) and receives the hydrated instance as its argument. Use this for initialisation logic that should run after the current thread finishes applying properties.

```luau
Flux.edit(existingContainer) {
    -- 1. This new instance will be parented to existingContainer
    Flux.new "TextLabel" { Text = "Child Label" },

    -- 2. This function is deferred; runs after all properties are applied
    function(inst)
        print("Finished hydrating " .. inst.Name)
    end,
}
```

## Instance Selectors (`Flux.Find`{lua})

When hydrating a complex, pre-built UI hierarchy, calling `Flux.edit`{lua} individually on every child creates verbose, hard-to-maintain code.

`Flux.Find`{lua} provides a suite of **Selectors** for inline deep queries. Place a selector in the array portion of your `Flux.edit`{lua} table to find a descendant and apply a nested `Flux.edit`{lua} to it, all in one declarative block.

The properties passed to a selector are treated exactly like a standard `Flux.edit`{lua} block; you can use reactive nodes, `__EVENT`, or even nest selectors inside selectors.

### Available Selectors

| Selector                              | Finds                                        |
| :------------------------------------ | :------------------------------------------- |
| `Find.Child(name)`{luau}              | `FindFirstChild(name)`{luau}                 |
| `Find.ChildClass(className)`{luau}    | `FindFirstChildOfClass(className)`{luau}     |
| `Find.ChildIsA(className)`{luau}      | `FindFirstChildWhichIsA(className)`{luau}    |
| `Find.Descendant(name)`{luau}         | `FindFirstDescendant(name)`{luau}            |
| `Find.Ancestor(name)`{luau}           | `FindFirstAncestor(name)`{luau}              |
| `Find.AncestorClass(className)`{luau} | `FindFirstAncestorOfClass(className)`{luau}  |
| `Find.AncestorIsA(className)`{luau}   | `FindFirstAncestorWhichIsA(className)`{luau} |
| `Find.Parent()`{luau}                 | `Instance.Parent`{lua}                       |
| `Find.Query(query)`{luau}             | `QueryDescendants(query)`{luau}              |
| `Find.QueryFirst(query)`{luau}        | `QueryDescendants(query)[1]`{luau}           |

```luau
local Find = Flux.Find
local existingMenu = script.Parent.SettingsMenu

local isMuted = Flux(false)

Flux.edit(existingMenu) {
    -- Top-level properties
    Visible = true,

    -- Selectors in the array portion
    Find.Child "CloseButton" {
        Activated = function()
            existingMenu.Visible = false
        end,
    },

    Find.Descendant "MuteToggle" {
        BackgroundColor3 = function()
            return isMuted() and Color3.new(1, 0, 0) or Color3.new(0, 1, 0)
        end,

        Activated = function()
            isMuted(not isMuted())
        end,
    },

    Find.QueryFirst "UIListLayout" {
        Padding = UDim.new(0, 10),
    },
}
```

## Memory Management

`Flux.edit`{lua} automatically connects to the instance's `Destroying` signal. When the instance is destroyed, Flux instantly disconnects all signals, severs reactive bindings, and clears associated memory; no manual cleanup required.

If you need to clean up _before_ the instance is destroyed (e.g., when a scope is wiped), pass the scope as the second argument to `Flux.edit`{lua} and let the scope handle it.
