---
title: Components
description: Best practices for building reusable UI components in Flux.
outline: deep
---

# Components

As your application grows, you will want to break down complex UI hierarchies into smaller, reusable pieces. In Flux, **Components are just regular Luau functions** that return Roblox instances.

Because Flux does not rely on a Virtual DOM, its component model is fundamentally different from frameworks like React or Roact. If you understand how SolidJS components work, you will feel right at home here.

## The "Run Once" Mental Model

The most critical concept to understand is that **Flux components only run once**.

A component is a factory function. When you call it, it creates Roblox instances, wires up reactive bindings (Computeds, Effects), and returns the generated UI. The component function itself does _not_ re-execute when state changes. Only the specific property bindings (the functions or nodes you assign to properties like [`Text`](https://create.roblox.com/docs/en-us/reference/engine/classes/TextLabel#Text) or [`BackgroundColor3`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiObject#BackgroundColor3)) will re-evaluate.

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

## Handling Props (Static vs. Reactive)

When designing a reusable component, you often don't know if the caller will pass a static value (like `"Submit"`) or a reactive node (like a `Flux` [Value](/guide/concepts/values)). There are two clean ways to handle this.

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

For components with many props where you want to guarantee all values are nodes (so you can always call them as functions), use `Flux.wrap`{lua} at the top of the component. It converts any primitive values to Nodes in-place and leaves existing Nodes untouched.

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

### 3. Manual check with `Flux.isNode`{lua}

For targeted checks on a single prop:

```luau
local function StatusLabel(props)
    return new "TextLabel" {
        Text = function()
            return if Flux.isNode(props.status) then props.status() else props.status
        end,
    }
end
```

## Component Scopes and Lifecycles

If your component creates internal reactive state, asynchronous operations, or requires cleanup logic, manage its memory with a **Scope**.

### Internal Component Scope

Create a scope internally and tie its lifetime to the root instance's `__CLEAN` directive. When Flux destroys the instance, it will destroy the scope, and all the nodes and effects inside it, automatically.

```luau
local function TimerComponent(props)
    -- 1. Create a local scope for this component's memory
    local localScope = Flux.scope()

    -- 2. Internal state tracked by this scope
    local timeElapsed = localScope(0)

    -- 3. Internal effect tracked by this scope
    localScope(function()
        print("Timer is at: " .. timeElapsed)
    end, true)

    return new "TextLabel" {
        Text = function() return timeElapsed .. "s" end,

        -- 4. Destroy the scope when this TextLabel is destroyed
        __CLEAN = {
            function() localScope:Destroy() end,
        },
    }
end
```

### External Scope (Props)

If a parent is managing its own scope, accept it as a prop and create your nodes through it. This allows the parent to clean up the entire tree by destroying its scope.

```luau
local function AvatarCard(props)
    -- props.scope is a Scope object passed from the parent
    local name = props.scope(props.initialName)

    return new "Frame" {
        new "TextLabel" {
            Text = name,
        },
    }
end
```

By adhering to the "Run Once" mental model and leveraging Scopes for memory management, you can build massive, highly performant UI trees out of small, predictable components.
