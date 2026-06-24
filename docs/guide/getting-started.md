---
title: Getting Started
description: Install Flux and build your first reactive Roblox UI.
outline: deep
---

# Getting Started

This guide walks you through installing Flux and building your first declarative, reactive UI component in Roblox.

If you haven't read about how Flux works yet, start with the [What is Flux?](/guide/) page to see how it differs from traditional Luau UI libraries.

## Installation

Flux drops into any Roblox project. Pick whichever method fits your workflow; all three give you the same module.

### Wally (Recommended)

[Wally](https://wally.run/) is the Luau package manager. Add Flux to the `[dependencies]` section of your `wally.toml`, then run `wally install`:

```toml
[dependencies]
Flux = "kohltastrophe/flux@0.1.0"
```

Pinning an exact version keeps builds reproducible; bump it when you want updates. The package lives at **[wally.run/package/kohltastrophe/flux](https://wally.run/package/kohltastrophe/flux)** and installs as a `shared` dependency, so both the client and the server can require it from your `Packages` folder.

### GitHub Releases (`.rbxm`)

No toolchain? Download the pre-built `Flux.rbxm` model instead:

1. Navigate to the **[Flux GitHub Releases](https://github.com/kohltastrophe/flux/releases)** page.
2. Download the latest `Flux.rbxm` file from the Assets section.
3. Drag and drop the `.rbxm` file directly into your Roblox Studio viewport.
4. Place the `Flux` module inside [`ReplicatedStorage`](https://create.roblox.com/docs/en-us/reference/engine/classes/ReplicatedStorage) so both the client and the server can access it.

### File Sync

Prefer to vendor the source? Copy the repository's `src/` directory into your project (e.g. under your Rojo source tree) and require it from there.

## Your First App

Let's build a counter to see Flux in action. We'll create a piece of reactive state, bind it to a [`TextButton`](https://create.roblox.com/docs/en-us/reference/engine/classes/TextButton), and mount the result to the local player's screen.

Create a new [`LocalScript`](https://create.roblox.com/docs/en-us/reference/engine/classes/LocalScript) inside [`StarterPlayerScripts`](https://create.roblox.com/docs/en-us/reference/engine/classes/StarterPlayerScripts) and paste the following code:

```luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Require the library
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

-- 1. Define your component
local function CounterApp()
    -- Create a piece of reactive state (a Signal) initialized to 0
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

            -- Bind the Text property to an implicit Computed on our reactive state.
            -- Interpolating {count} reads its current value automatically.
            Text = function()
                return `Clicks: {count}`
            end,

            -- Mutate the state when the button is clicked.
            -- count + 1 reads the current value; count(...) sets the result.
            Activated = function()
                count(count + 1)
            end,
        },
    }
end

-- 2. Call the component function once to generate and mount the instances
CounterApp()
```

Press **Play** (or `F5`) and a button appears centered on screen, reading `Clicks: 0`. Each click bumps the number, and only the button's text re-evaluates, nothing else.

### What just happened?

1. **`Flux(0)`{luau}** - We created a reactive Signal. This holds our state, initialized to `0`.
2. **`function() return ... end`{luau}** - We created an implicit **Computed**. It runs lazily (only when something needs its result) and only recalculates when `count` changes.
3. **`Text = function() return ... end`{luau}** - We bound the Computed directly to the `Text` property. Whenever `count` updates, only this label re-evaluates.
4. **`count(count + 1)`{luau}** - `count + 1`{luau} uses operator overloading to read `count`'s current value and add `1`; then `count(...)`{luau} calls the node to set its new value.
5. **`Parent = Players.LocalPlayer:WaitForChild("PlayerGui")`{luau}** - Setting `Parent` inside the declarative table mounts the UI as part of construction, keeping everything in one place.

**You've installed Flux and built a reactive interface.**

## Next Steps

- **[Signals](/guide/concepts/signals)** - Learn about the fundamental building block of reactivity.
- **[Computeds](/guide/concepts/computeds)** - Discover how to derive and memoize state.
- **[Effects](/guide/concepts/effects)** - Run side effects in response to state changes.
- **[Scopes](/guide/concepts/scopes)** - Group nodes, instances, and effects under one lifecycle and tear them all down with a single `:Destroy()`{luau}.
- **[Creation](/guide/roblox/creation)** - Explore the full declarative instance builder.
- **[Responsive](/guide/utilities/responsive)** - Scale, breakpoint, and safe-area values for UI that adapts to any screen.
- **[Layout](/guide/utilities/layout)** - Terse helpers for padding, constraints, and layouts.
