---
title: Components
description: Best practices for building reusable UI components in Flux.
outline: deep
---

# Components

As your application grows, you will want to break down complex UI hierarchies into smaller, reusable pieces. In Flux, **Components are just regular Luau functions** that return Roblox instances.

Because Flux does not rely on a Virtual DOM, its component model differs from libraries like React or Roact. If you understand how SolidJS components work, the model here will be familiar.

## The "Run Once" Mental Model

The most critical concept to understand is that **Flux components only run once**.

A component is a factory function. When you call it, it creates Roblox instances, wires up reactive bindings ([Computeds](/guide/concepts/computeds), [Effects](/guide/concepts/effects)), and returns the generated UI. The component function itself does _not_ re-execute when state changes. Only the specific property bindings (the functions or nodes you assign to properties like [`Text`](https://create.roblox.com/docs/en-us/reference/engine/classes/TextLabel#Text) or [`BackgroundColor3`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject#BackgroundColor3)) will re-evaluate.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

-- This function runs exactly ONCE per button instance created
local function PrimaryButton(props)
    print("Mounting button...") -- prints only once

    return new "TextButton" {
        Size = UDim2.fromOffset(200, 50),
        BackgroundColor3 = Color3.fromRGB(0, 120, 255),

        -- Only this re-evaluates when props.text changes
        Text = props.text,

        Activated = props.onClick,
    }
end
```

## Consuming Components

Because components are just functions, you consume them by calling them within your declarative hierarchy.

```luau
local count = Flux(0)

local ui = new "Frame" {
    Size = UDim2.fromScale(1, 1),

    -- Mount the component by calling it
    PrimaryButton({
        text  = Flux(function() return `Count: {count}` end),
        onClick = function() count(count + 1) end,
    }),
}
```

Interpolating `{count}`{luau} (or writing `count + 1`{luau}) reads the node's current value automatically; see [Signals](/guide/concepts/signals).

## Handling Props (Static vs. Reactive)

When designing a reusable component, you often don't know if the caller will pass a static value (like `"Submit"`{luau}) or a reactive node (like a `Flux` [Signal](/guide/concepts/signals)). There are a few clean ways to handle this.

### 1. Pass nodes directly to property bindings

The simplest approach: accept both static values and nodes as props, and pass them directly to the instance's property. Flux's declarative builder handles both; a static value is assigned once, a node is bound reactively.

```luau
local function StatusLabel(props)
    return new "TextLabel" {
        -- If props.status is a node, it binds reactively.
        -- If it's a static string, it's assigned once.
        Text = props.status,
    }
end

-- Works with a static string:
StatusLabel({ status = "Ready" })

-- Works with a reactive node:
StatusLabel({ status = someFluxNode })
```

### 2. Normalising props with `Flux.wrap`{lua}

For components with many props where you want to guarantee all values are nodes (so you can always call them as functions), use `Flux.wrap`{lua} at the top of the component. It converts any primitive values to Nodes in-place and leaves existing Nodes untouched. It also recurses into nested tables, so a prop like `props.theme = { color = ... }`{luau} gets its inner values wrapped too.

```luau
local function Card(props)
    -- Normalise all props: primitives become Nodes, existing Nodes are unchanged
    Flux.wrap(props)

    return new "Frame" {
        BackgroundColor3 = function()
            return props.color()  -- always safe to call
        end,

        new "TextLabel" {
            Text = function()
                return props.title()  -- always safe to call
            end,
        },
    }
end
```

### 3. Reading node-or-value props with `Flux.read`{lua}

When you need a prop's value inside a larger expression, `Flux.read`{lua} evaluates a node (registering it as a dependency) or passes a plain value through unchanged:

```luau
local function StatusLabel(props)
    return new "TextLabel" {
        Text = function()
            return "Status: " .. Flux.read(props.status)
        end,
    }
end
```

For an explicit check, `Flux.isNode(props.status)`{luau} tells you whether a prop is reactive. See [Tracking](/guide/concepts/tracking) for the full set of read utilities.

## Accepting Children

A reusable container often needs to wrap whatever content the caller passes in. Accept those children as a prop (an array of instances), and place that array at a numeric position in your hierarchy. Flux **flattens arrays into children in place**, so there is no `table.unpack`{luau} and no manual parenting (see [Creating Hierarchies](/guide/roblox/creation#creating-hierarchies-children)).

```luau
local function Panel(props)
    return new "Frame" {
        Size = UDim2.fromOffset(400, 300),
        BackgroundColor3 = Color3.fromRGB(30, 30, 35),

        new "TextLabel" { Text = props.title }, -- a child of your own

        props.children, -- the caller's array, flattened in place
    }
end

Panel({
    title = "Settings",
    children = {
        new "TextLabel" { Text = "Row 1" },
        new "TextLabel" { Text = "Row 2" },
    },
})
```

Each element keeps the automatic [`LayoutOrder`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject#LayoutOrder) numbering Flux gives every child, so they render in array order. When the set of children changes over time, hand that same slot a [`Flux.forValue`](/guide/concepts/mapping) node instead of a static array; it occupies the same position and Flux manages parenting, ordering, and cleanup as the source list changes.

## Component Scopes and Lifecycles

If your component creates internal reactive state, asynchronous operations, or requires cleanup logic, manage its memory with a **Scope**.

### Ownership Flows Implicitly

When a component is called inside a parent's [scope](/guide/concepts/scopes), everything it creates (nodes, effects, instances) is automatically owned by that scope. You never thread a scope through props; destroying the parent tears the whole component tree down with it.

```luau
Flux.scope(function()
    -- Everything AvatarCard builds is owned by this scope
    local card = AvatarCard({ name = "Player1" })
    card.Parent = playerGui
end)
```

### A Self-Contained Component Scope

When a component owns resources whose lifetime should follow its own root instance rather than an outer scope, give it its own scope and tie that scope to the instance with `__CLEAN`. When Flux destroys the instance, it destroys the scope and everything inside it.

```luau
local function TimerComponent(props)
    local _, label = Flux.scope(function(scope)
        -- Internal state and effect (the effect is owned by this scope)
        local timeElapsed = Flux(0)

        Flux(function()
            print("Timer is at: " .. timeElapsed)
        end, true) -- the `true` makes this an Effect (see [Effects](/guide/concepts/effects))

        return new "TextLabel" {
            Text = function() return timeElapsed .. "s" end,

            -- Destroy the scope when this TextLabel is destroyed
            __CLEAN = { scope },
        }
    end)

    return label
end
```

Because the `TextLabel` is built inside the scope, the scope owns it, and `__CLEAN = { scope }`{luau} closes the loop the other way: destroying the `TextLabel` (or any outer scope) tears down the timer's effect too; its `timeElapsed` signal is then left for the GC.

By following the "Run Once" mental model and letting scopes own what your components create, you can build large UI trees out of small, predictable components.
