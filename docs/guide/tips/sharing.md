---
title: Sharing State
description: Patterns for sharing reactive state across components and systems in Flux.
outline: deep
---

# Sharing State

If you are coming from UI frameworks like Roact or React, you might be accustomed to state being tightly coupled to a component tree. In those frameworks, sharing state often requires Context providers, third-party libraries, or prop-drilling through many nested layers.

In Flux, **reactivity is completely independent of the UI tree**. A `Flux` Value or Store is just an isolated object. It doesn't care where it was created or which component is reading it. This makes sharing state straightforward.

## Lifting State Up (Props)

The simplest way to share state between sibling components is to create it in their common parent and pass it down. Because Flux components run exactly once, passing a reactive node is as cheap and fast as passing a table reference.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

-- Reads shared state
local function CounterDisplay(props)
    return new "TextLabel" {
        Size = UDim2.fromOffset(200, 50),
        Text = function()
            return "Count: " .. props.count
        end,
    }
end

-- Mutates shared state
local function CounterControls(props)
    return new "TextButton" {
        Size = UDim2.fromOffset(200, 50),
        Text = "Increment",
        Activated = function()
            props.count(props.count + 1)
        end,
    }
end

-- The parent component creates and owns the state
local function App()
    local sharedCount = Flux(0)

    return new "Frame" {
        Size = UDim2.fromScale(1, 1),

        CounterDisplay({ count = sharedCount }),
        CounterControls({ count = sharedCount }),
    }
end
```

## Global State (ModuleScripts)

In web development, you need a Context API to prevent global variables from leaking between server renders. In Roblox, the client is a single-user environment, and [`ModuleScripts`](https://create.roblox.com/docs/en-us/reference/engine/classes/ModuleScript) act as strictly-cached singletons.

**Global State in Flux is just a ModuleScript.**

Create a `Flux` Value or Store inside a ModuleScript and return it. Any script that [`requires`](https://create.roblox.com/docs/en-us/reference/engine/globals/LuaGlobals#require) this module shares the exact same reactive graph.

**State/PlayerSettings.luau**

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

-- A deeply reactive global settings store
local settings = Flux.store({
    audio = {
        masterVolume = 0.5,
        musicMuted   = false,
    },
    ui = {
        theme = "Dark",
    },
})

return settings
```

**UI/SettingsMenu.luau**

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

local settings = require(ReplicatedStorage.State.PlayerSettings)

local function MuteButton()
    return new "TextButton" {
        Text = function()
            return settings.audio.musicMuted and "Unmute" or "Mute"
        end,
        Activated = function()
            -- This mutation automatically updates any other UI or audio system
            -- that reads `settings.audio.musicMuted`
            settings.audio.musicMuted = not settings.audio.musicMuted
        end,
    }
end
```

## Scoped Shared State

Sometimes you need state shared among many components, but not truly _global_. For example, a complex `Inventory` system with multiple UI files that share underlying data, but that data should be wiped from memory when the inventory closes.

Create a **Scope** at the root of the system, create the shared state within it, and pass it down to the components that need it.

```luau
local function InventorySystem()
    -- 1. Create a localised memory scope for the entire system
    local inventoryScope = Flux.scope()

    -- 2. Create shared state tied entirely to this scope
    local selectedItem = inventoryScope(nil)

    local ui = new "Frame" {
        Size = UDim2.fromScale(1, 1),

        -- Pass shared state to sub-components
        Sidebar({ selected = selectedItem }),
        ItemGrid({ selected = selectedItem, scope = inventoryScope }),
    }

    -- Return both so the caller can control the lifetime
    return ui, inventoryScope
end

local invUI, invScope = InventorySystem()

-- When the player closes the inventory, wipe the entire shared state ecosystem
invScope:Destroy()
```

## Subscribing Externally (`Flux.listen`{lua})

Outside of the reactive graph (e.g., in a non-Flux system that needs to react to changes), use `Flux.listen`{lua} to subscribe a callback to a node. It returns a disconnect function.

```luau
local volume = Flux(0.5)

local disconnect = Flux.listen(volume, function(newVolume)
    SoundService.AmbientReverb = newVolume > 0.8 and "BigHall" or "NoReverb"
end)

-- Later, when no longer needed:
disconnect()
```

## Summary

Flux's separation of the reactive graph from the component hierarchy means you don't need complex state management libraries.

| Pattern                 | Use when                                                             |
| :---------------------- | :------------------------------------------------------------------- |
| **Props**               | Local sharing between immediate parent and children                  |
| **ModuleScripts**       | Truly global state (settings, player data, round state)              |
| **Scoped shared state** | Temporary systems that need a clean shutdown (minigames, UI windows) |
| **`Flux.listen`{lua}**  | Bridging into non-Flux systems                                       |
