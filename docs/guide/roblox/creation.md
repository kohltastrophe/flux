---
title: Creation
description: Declaratively building dynamic Roblox UIs and structures with Flux.
outline: deep
---

# Creation

Standard Roblox development requires you to create instances, assign properties, and connect events sequentially across many lines. Flux lets you build complex hierarchies in a single, readable, declarative block using `Flux.new`{lua}.

This declarative syntax is the cornerstone of reactive UI components in Flux, the Luau equivalent of JSX.

## The `Flux.new`{lua} Function

Call `Flux.new "ClassName"`{luau} to obtain a constructor function, then pass it a properties table:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

-- Create a static TextButton
local staticButton = new "TextButton" {
    Name = "MyButton",
    Size = UDim2.fromOffset(200, 50),
    Text = "Click Me!",
    BackgroundColor3 = Color3.fromRGB(0, 120, 255),
}
```

> Luau's syntax sugar allows you to omit parentheses when calling with a string or table literal, so `new "TextButton" { }`{luau} is idiomatic Flux style.

## Reactive Properties

The true power of `Flux.new`{lua} is its understanding of Flux reactive nodes. You can pass:

- **A reactive node directly** - Flux binds it to the property; the property updates whenever the node changes.
- **A function** - Flux wraps it in an implicit computation and binds the result.
- **A static value** - assigned once at creation time.

```luau
local count = Flux(0)

-- Build a computation once and share it across multiple bindings
local countText = Flux(function()
    return "Count: " .. count
end)

local reactiveButton = new "TextButton" {
    Size = UDim2.fromOffset(200, 50),

    -- Pass a node directly (preferred when the same derived value is used elsewhere)
    Text = countText,

    -- Or use an inline function for a one-off binding
    BackgroundColor3 = function()
        return count > 10 and Color3.new(1, 0, 0) or Color3.new(0, 1, 0)
    end,
}
```

## Creating Hierarchies (Children)

Nest `Flux.new`{lua} calls to build complex UI trees. Any `Flux.new`{lua} instance placed at a **numeric index** in the properties table is automatically parented to the enclosing instance.

```luau
local inventoryFrame = new "Frame" {
    Name = "Inventory",
    Size = UDim2.fromScale(0.5, 0.5),
    BackgroundColor3 = Color3.new(0.2, 0.2, 0.2),

    -- Array elements are treated as children; LayoutOrder is assigned automatically
    new "UIListLayout" {
        Padding = UDim.new(0, 5),
    },

    new "TextLabel" {
        Text = "Item 1",
        Size = UDim2.new(1, 0, 0, 30),
    },

    new "TextLabel" {
        Text = "Item 2",
        Size = UDim2.new(1, 0, 0, 30),
    },
}
```

> **Performance tip:** If a [`GuiObject`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject) child has [`LayoutOrder`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject#LayoutOrder) at its default of `0`, Flux automatically assigns it to match its numeric array index. This keeps ordered lists trivial to build without manually numbering every item.

## Events and Directives

`Flux.new`{lua} supports the same special directives as `Flux.edit`{lua}.

| Key                            | Behaviour                                                                                                                                                         |
| :----------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Signal name (e.g. `Activated`) | Calls [`:Connect(fn)`{luau}](https://create.roblox.com/docs/en-us/reference/engine/datatypes/RBXScriptSignal#Connect) automatically                               |
| `__EVENT`                      | Two-way bindings and [`:GetPropertyChangedSignal`{luau}](https://create.roblox.com/docs/en-us/reference/engine/classes/Object#GetPropertyChangedSignal) listeners |
| `__ATTR`                       | Static or reactive custom Instance Attributes                                                                                                                     |
| `__CLEAN`                      | Additional cleanup items tied to the instance's lifetime                                                                                                          |
| `__REF`                        | Capture a reference to the created instance                                                                                                                       |

```luau
local inputState = Flux("")
local boxRef = Flux(nil)

local myTextBox = new "TextBox" {
    Size = UDim2.fromOffset(200, 50),

    -- Two-way binding: 'inputState' stays in sync with what the user types
    __EVENT = {
        Text = inputState,
    },

    -- Capture a reference to this TextBox via a reactive node
    __REF = boxRef,

    -- Connect a standard signal
    FocusLost = function(enterPressed)
        print("User typed: " .. inputState())
    end,
}

-- boxRef() now holds the TextBox instance
```

## Reactive Children (`Flux.forValue`{lua} / `Flux.forIndex`{lua})

To render a dynamic list of children, use `Flux.forValue`{lua} or `Flux.forIndex`{lua}. When placed at a numeric index, the resulting effect node is treated as a **children binder**; Flux manages parenting, ordering, and cleanup automatically as the source list changes.

```luau
local items = Flux({ "Sword", "Shield", "Potion" })

local itemList = new "Frame" {
    Size = UDim2.fromScale(1, 1),

    new "UIListLayout" {},

    -- Efficiently renders one TextLabel per item; updates on changes
    Flux.forIndex(items, function(index, itemNode)
        return new "TextLabel" {
            Text = itemNode,  -- reactive node, updates in place
            Size = UDim2.new(1, 0, 0, 30),
        }
    end),
}
```

## Scoped Creation

For UI that mounts and unmounts frequently (notifications, inventory slots, player name tags), create instances through a **Scope** to prevent memory leaks. Instances created via `scope:new`{luau} are automatically added to the scope's cleanup list.

```luau
local myScope = Flux.scope()

-- Create an instance tied to myScope's lifecycle
local transientLabel = myScope:new "TextLabel" {
    Text = "I will be cleaned up safely.",
    Parent = playerGui,
}

-- Destroying the scope destroys the label and all of its reactive bindings
myScope:Destroy()
```

See [Scopes](/guide/concepts/scopes) for the full lifecycle management guide.
