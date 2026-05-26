---
title: Getting Started
description: Install Flux and build your first reactive Roblox UI.
outline: deep
---

# Getting Started

Welcome to Flux! This guide will walk you through installing the framework and building your very first declarative, reactive UI component in Roblox.

If you haven't yet read about the core philosophy of the framework, we highly recommend checking out the [What is Flux?](/guide/) page first to familiarise yourself with how Flux differs from traditional Luau UI libraries.

## Installation

Flux is designed to be easily dropped into any Roblox project. You can grab the latest stable release directly from GitHub.

### GitHub Releases (Recommended)

The simplest way to install Flux is to download the pre-compiled Roblox Model file.

1. Navigate to the **[Flux GitHub Releases](https://github.com/kohltastrophe/flux/releases)** page.
2. Download the latest `Flux.rbxm` file from the Assets section.
3. Drag and drop the `.rbxm` file directly into your Roblox Studio viewport.
4. Place the `Flux` module inside [`ReplicatedStorage`](https://create.roblox.com/docs/en-us/reference/engine/classes/ReplicatedStorage) so it can be accessed by both the client and the server.

> [!NOTE]
> If your project uses Wally or standard Rojo file-syncing, you can also clone the repository source directly into your `src` directory.

## Your First App

Let's build a classic counter application to see Flux in action. We are going to create a piece of reactive state, bind it to a [`TextButton`](https://create.roblox.com/docs/en-us/reference/engine/classes/TextButton), and mount the resulting UI to the local player's screen.

Create a new [`LocalScript`](https://create.roblox.com/docs/en-us/reference/engine/classes/LocalScript) inside [`StarterPlayerScripts`](https://create.roblox.com/docs/en-us/reference/engine/classes/StarterPlayerScripts) and paste the following code:

```luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Require the library
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

-- 1. Define your component
local function CounterApp()
    -- Create a piece of reactive state (a Value) initialised to 0
    local count = Flux(0)

    -- Declaratively build the UI hierarchy
    return new "ScreenGui" {
        Name = "FluxCounterApp",
        ResetOnSpawn = false,
        Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),

        new "TextButton" {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(250, 80),
            BackgroundColor3 = Color3.fromRGB(30, 30, 35),
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextSize = 24,

            -- Bind the Text property to an implicit computation on our reactive state.
            -- Operator overloading means count reads naturally in expressions.
            Text = function()
                return `Clicks: {count}`
            end,

            -- Mutate the state when the button is clicked.
            -- count + 1 reads count reactively via __add, then passes the result to count().
            Activated = function()
                count(count + 1)
            end,
        },
    }
end

-- 2. Call the component function once to generate and mount the instances
CounterApp()
```

### What just happened?

1. **`Flux(0)`{luau}** - We created a reactive Value. This holds our state, initialised to `0`.
2. **`function() return ... end`{luau}** - We created an implicit **computation** (memo). It runs lazily and only recalculates when `count` changes.
3. **`Text = function() return ... end`{luau}** - We bound the computation directly to the `Text` property. Whenever `count` updates, only this label re-evaluates.
4. **`count(count + 1)`{luau}** - `count + 1`{luau} uses operator overloading to read `count` reactively and add `1`; then `count(...)`{luau} calls the node to set its new value.
5. **`Parent = Players.LocalPlayer:WaitForChild("PlayerGui")`{luau}** - Setting `Parent` inside the declarative table mounts the UI as part of construction, keeping everything in one place.

**You've successfully installed Flux and created a reactive interface!**

## Next Steps

- **[Values](/guide/concepts/values)** - Learn about the fundamental building block of reactivity.
- **[Computeds](/guide/concepts/computeds)** - Discover how to derive and memoize state.
- **[Effects](/guide/concepts/effects)** - Run side effects in response to state changes.
- **[Creation](/guide/roblox/creation)** - Explore the full declarative instance builder.
