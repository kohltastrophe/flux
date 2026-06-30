---
title: Creation
description: Declaratively building dynamic Roblox UIs and structures with Flux.
outline: deep
---

# Creation

Standard Roblox development requires you to create instances, assign properties, and connect events sequentially across many lines. Flux lets you build complex hierarchies in a single, readable, declarative block using `Flux.new`{lua}.

This declarative syntax is how you build reactive UI components in Flux, the Luau equivalent of JSX.

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

> [!NOTE]
> `Flux.new`{lua} applies a small set of modern default property overrides before your properties are assigned: Parts are anchored, GUI objects have no borders, layouts sort by `LayoutOrder`. See [Defaults](/guide/roblox/defaults) for the full list and how to disable or customize it.

## Reactive Properties

What makes `Flux.new`{lua} useful is its handling of Flux reactive **nodes** (the umbrella term for a [Signal](/guide/concepts/signals), a [Computed](/guide/concepts/computeds), or an [Effect](/guide/concepts/effects)). You can pass:

- **A node directly** - Flux binds it to the property; the property updates whenever the node changes.
- **A function** - Flux wraps it in a computation that re-runs (and updates the property) whenever any node it reads changes.
- **A static value** - assigned once at creation time.

```luau
local count = Flux(0)

-- A Computed: derives a new value once and shares it across multiple bindings
local countText = Flux(function()
    return "Count: " .. count
end)

local reactiveButton = new "TextButton" {
    Size = UDim2.fromOffset(200, 50),

    -- Pass a node directly (preferred when the same derived value is used elsewhere)
    Text = countText,

    -- Or use an inline function for a one-off binding
    BackgroundColor3 = function()
        return count() > 10 and Color3.new(1, 0, 0) or Color3.new(0, 1, 0)
    end,
}
```

> Arithmetic and concatenation operators (`+`, `-`, `..`, …) read a node operand's current value automatically, so `"Count: " .. count`{luau} works without calling the node. Comparison operators are the exception: `count > 10`{luau} would compare a number against the node table and error, so you must read the value first with `count() > 10`{luau} (comparisons only work transparently between two nodes). See [Signals](/guide/concepts/signals) for how this works.

> [!IMPORTANT] Bare values are read once; reactive text needs a function
> `Text = count`{luau} binds the node directly, so the property tracks it. But the moment you combine a node with a **literal** outside a reactive context (`Text = "Clicks: " .. count`{luau} or the interpolation `Text = `Clicks: {count}``{luau}), Luau evaluates the expression **once** at construction time and hands Flux a plain, frozen string. There is no node left to bind. Wrap it in a `function`{luau} so the read happens inside a tracked computation:
>
> ```luau
> -- ✗ evaluated once: "Clicks: 0" forever
> Text = `Clicks: {count}`,
>
> -- ✓ re-runs whenever `count` changes
> Text = function() return `Clicks: {count}` end,
> ```

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

> **Performance tip:** If a [`GuiObject`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject) child has [`LayoutOrder`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject#LayoutOrder) at its default of `0`, Flux automatically assigns it to match its numeric array index. This keeps ordered lists easy to build without manually numbering every item.

A plain **array** placed at a numeric index is flattened into children, so you can splice in a pre-built list without unpacking it. Each element is parented in order (reactive [`Flux.show`](/guide/concepts/conditionals) / [`Flux.forValue`](/guide/concepts/mapping) nodes included) with the same automatic `LayoutOrder`:

```luau
local buttons = { SaveButton, LoadButton, QuitButton } -- an array of Instances

local menu = new "Frame" {
    new "UIListLayout" {},

    Header,           -- a single child
    buttons,          -- the whole array, flattened in place (no table.unpack needed)
}
```

> [!NOTE]
> The `Parent` property mounts the instance into the tree, and Flux assigns it **last** (after every child and property), so the instance only enters the tree once it is fully built (Roblox's performance best practice, handled for you). Like any property, `Parent` also accepts a node, so you can reparent an instance reactively.

## Events and Directives

`Flux.new`{lua} supports the same special directives as `Flux.edit`{lua}.

| Key                           | Behaviour                                                                                                                                                         |
| :---------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Event name (e.g. `Activated`) | Calls [`:Connect(fn)`{luau}](https://create.roblox.com/docs/en-us/reference/engine/datatypes/RBXScriptSignal#Connect) automatically                               |
| `_EVENT`                      | Two-way bindings and [`:GetPropertyChangedSignal`{luau}](https://create.roblox.com/docs/en-us/reference/engine/classes/Object#GetPropertyChangedSignal) listeners |
| `_ATTR`                       | Static or reactive custom Instance Attributes                                                                                                                     |
| `_CLEAN`                      | Additional cleanup items tied to the instance's lifetime                                                                                                          |
| `_REF`                        | Capture a reference to the created instance                                                                                                                       |

```luau
local inputState = Flux("")
local boxRef = Flux(nil)

local myTextBox = new "TextBox" {
    Size = UDim2.fromOffset(200, 50),

    -- Two-way binding: assign the node to the property AND list it under _EVENT.
    -- Top-level drives Text from the node; _EVENT writes the node back when the
    -- user types, so the two stay in sync in both directions.
    Text = inputState,
    _EVENT = {
        Text = inputState,
    },

    -- Capture a reference to this TextBox via a reactive node
    _REF = boxRef,

    -- Connect a plain event with a bare top-level key
    FocusLost = function(enterPressed)
        if enterPressed then
            print("User submitted: " .. inputState())
        end
    end,
}

-- boxRef() now holds the TextBox instance
```

### `Flux.model`{lua}: two-way binding in one key

When a property both drives and is driven by the same node, `Flux.model`{lua} collapses the assign-plus-`_EVENT` pair into a single entry. It binds the node to the property **and** writes the node back whenever the instance changes:

```luau
local inputState = Flux("")

local myTextBox = new "TextBox" {
    Size = UDim2.fromOffset(200, 50),

    -- Equivalent to `Text = inputState` plus `_EVENT = { Text = inputState }`
    Text = Flux.model(inputState),
}
```

The node's authored value wins on mount (the instance is set from the node first, then the binding-back is wired up). `Flux.model`{lua} works on any property that fires a changed signal, and inside `_ATTR`{luau} for two-way attribute binding (`_ATTR = { Score = Flux.model(scoreNode) }`{luau}).

## Reactive Children (`Flux.forValue`{lua} / `Flux.forIndex`{lua})

To render a dynamic list of children, use `Flux.forValue`{luau} or `Flux.forIndex`{luau}. When placed at a numeric index, the resulting computed node is treated as a **children binder**; Flux manages parenting, ordering, and cleanup automatically as the source list changes.

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

For UI that mounts and unmounts frequently (notifications, inventory slots, player name tags), build instances inside a **Scope** to prevent memory leaks. Anything `Flux.new`{lua} creates while a scope is active is owned by it and destroyed together.

```luau
local scope, transientLabel = Flux.scope(function()
    -- Created inside the scope, so the scope owns it
    return new "TextLabel" {
        Text = "I will be cleaned up safely.",
        Parent = playerGui,
    }
end)

-- Destroying the scope destroys the label and all of its reactive bindings
scope:Destroy()
```

See [Scopes](/guide/concepts/scopes) for the full lifecycle management guide.
