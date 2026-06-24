---
title: Hydration (Editing)
description: Attaching reactive state and behavior to existing Roblox instances in Flux.
outline: deep
---

# Hydration

In traditional web development, "hydration" is the process of attaching event listeners and reactive state to static HTML that was already rendered by the server.

In Roblox development, you often build UI layouts visually in Roblox Studio. Instead of recreating these hierarchies entirely in code with `Flux.new`{lua}, you can use **`Flux.edit`{lua}** to "hydrate" existing instances. This applies reactive properties, event connections, and lifecycle management to pre-existing [`Instances`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance).

## The `Flux.edit`{lua} Function

`Flux.edit`{lua} is a curried function. Call it with an instance to receive a constructor function, then call that constructor with your properties table.

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

    -- Events are automatically connected
    Activated = function()
        count(count + 1)
    end,
}
```

> [!NOTE]
> The `".." count`{luau} concatenation reads the node's current value automatically; arithmetic and concatenation operators and string interpolation all do. Comparison operators are the exception; `count > 10`{luau} errors, so read the value first with `count()`{luau}. See [Signals](/guide/concepts/signals#operator-overloading).

> [!NOTE] Curried syntax reminder:
> `Flux.edit(instance) { props }`{luau} is equivalent to `Flux.edit(instance)({ props })`{luau}
>
> This is standard Luau syntax sugar for passing a table to a function, identical to how `Flux.new`{lua} works.

For lifecycle management, call `Flux.edit`{lua} inside a [`Flux.scope`](/guide/concepts/scopes); the bindings it applies are owned by that scope and disconnected when it is destroyed:

```luau
local scope = Flux.scope(function()
    Flux.edit(existingButton) {
        Text = someNode,
    }
end)

-- Later: disconnect every binding applied above
scope:Destroy()
```

## Special Directives

To handle Roblox's unique instance architecture efficiently, `Flux.edit`{lua} supports several reserved keys within the properties table.

### `__ATTR`{luau} (Attributes)

Roblox Attributes allow you to tag instances with custom metadata. Use the `__ATTR` table to set attributes or bind them to reactive nodes.

```luau
Flux.edit(playerCharacter) {
    __ATTR = {
        IsStunned = true,            -- static assignment
        Health    = reactiveHealthNode, -- binds the attribute to update with the node
    },
}
```

### `__EVENT`{luau} (Two-Way Binding & Listeners)

While standard [`RBXScriptSignals`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/RBXScriptSignal) (like [`Activated`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiButton#Activated) or [`Touched`](https://create.roblox.com/docs/en-us/reference/engine/classes/BasePart#Touched)) can be connected directly as top-level properties, the `__EVENT` table is used for two-way data binding and [`GetPropertyChangedSignal(property)`{luau}](https://create.roblox.com/docs/en-us/reference/engine/classes/Object#GetPropertyChangedSignal) listeners.

- Assigning a **reactive node** to a property key makes the node receive the instance's property value whenever it changes (binding _from_ the instance _into_ the node).
- Assigning a **function** to a property key checks the named member: if it is itself an [`RBXScriptSignal`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/RBXScriptSignal), the function is connected to that event directly; otherwise it falls back to `GetPropertyChangedSignal(property)`{luau}.
- Assigning a **node or function** inside `__EVENT.__ATTR`{luau} does the same for attributes (a function connects to `GetAttributeChangedSignal(attribute)`{luau}).

> [!TIP]
> To create a brand-new node mirroring a property without editing the instance, call `Flux(instance, "Property")`{luau} directly. See [Binding from an Instance Property](/guide/concepts/signals#binding-from-an-instance-property).

For a true round-trip, drive the property from the node at the top level _and_ feed it back into the node inside `__EVENT`. The node then both updates the instance and tracks the user's edits:

```luau
local textInputNode = Flux("")

Flux.edit(existingTextBox) {
    -- node -> instance: writing to the node updates the TextBox's Text
    Text = textInputNode,

    __EVENT = {
        -- instance -> node: updates 'textInputNode' whenever the TextBox's Text changes
        Text = textInputNode,

        -- This member is not a signal, so it falls back to GetPropertyChangedSignal
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

### `__CLEAN`{luau} (Lifecycle Cleanup)

`Flux.edit`{lua} automatically cleans up its own reactive bindings and event connections when the instance is destroyed. If you have additional external connections or objects that should be tied to the same lifecycle, add them to the `__CLEAN` table.

Everything in the table (connections, instances, functions, scopes, or nested arrays of these) is cleaned up when the instance's [`Destroying`](https://create.roblox.com/docs/en-us/reference/engine/classes/Instance#Destroying) event fires. Flux copies the table internally, so your original table is never mutated. That also means items added to your table _after_ the `Flux.edit`{lua} call are not tracked; register everything before editing, or use a [Scope](/guide/concepts/scopes) for late additions.

When a selector matches multiple instances, each match receives its own copy of the `__CLEAN` items, and they run once per destroyed match, so make cleanup functions idempotent if the selector can match more than one instance.

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

-- When existingFrame is destroyed:
-- 1. The 'Activated' connection is disconnected.
-- 2. The custom 'RenderStepped' connection is also safely disconnected.
```

> [!NOTE]
> If you are editing inside a `Scope`, the `__CLEAN` table is also registered to that scope's master cleanup list, ensuring safe destruction even if the scope is wiped before the instance is manually destroyed.

### `__REF`{luau} (Reference)

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

A callback `__REF`{luau} may also **return** a cleanup value (a function, connection, instance, or array of them) which Flux ties to the instance's lifetime and runs on `Destroying`, exactly like `__CLEAN`. This lets a ref co-locate its own setup and teardown.

## Array Elements (Children & Actions)

The array portion of the properties table (elements with numeric indices) serves two purposes.

### 1. Parenting Children

Any Roblox `Instance` placed at a numeric index will automatically have its `Parent` set to the edited instance.

> [!NOTE]
> If the child is a `GuiObject` and its `LayoutOrder` is `0`, Flux automatically assigns it to the element's numeric index, saving you from setting `LayoutOrder` on every child manually.

### 2. Deferred Actions

A **function** at a numeric index is deferred via [`task.defer`{luau}](https://create.roblox.com/docs/reference/engine/libraries/task#defer) and receives the hydrated instance as its argument. Use this for initialisation logic that should run after the current thread finishes applying properties.

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

`Flux.Find`{lua} provides a set of **Selectors** for inline deep queries. Place a selector in the array portion of your `Flux.edit`{lua} table to find a descendant and apply a nested `Flux.edit`{lua} to it, all in one declarative block.

The properties passed to a selector are treated like a standard `Flux.edit`{lua} block; you can use reactive nodes, `__EVENT`, or nest selectors inside selectors.

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

> [!NOTE]
> `Find.Parent`{lua} curries like the other selectors; it ignores its query argument. Call it with empty parens and then apply the properties: `Find.Parent() { ... }`{luau}.

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

`Flux.edit`{lua} connects to the instance's `Destroying` event. When the instance is destroyed, Flux disconnects all event connections, severs reactive bindings, and clears associated memory. No manual cleanup is required.

If you need to clean up _before_ the instance is destroyed (e.g., when a scope is wiped), call `Flux.edit(instance) { ... }`{luau} inside a [`Flux.scope`](/guide/concepts/scopes){luau}. The bindings are owned by that scope and are disconnected when it is destroyed.
