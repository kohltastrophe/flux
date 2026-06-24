---
title: Sharing State
description: Patterns for sharing reactive state across components and systems in Flux.
outline: deep
---

# Sharing State

If you are coming from UI libraries like Roact or React, you might be accustomed to state being tightly coupled to a component tree. In those libraries, sharing state often requires Context providers, third-party libraries, or prop-drilling through many nested layers.

In Flux, **reactivity is completely independent of the UI tree**. A Signal or Store is just an isolated object. It doesn't care where it was created or which component is reading it. This makes sharing state straightforward.

## Lifting State Up (Props)

The simplest way to share state between sibling components is to create it in their common parent and pass it down. Because Flux components run exactly once, passing a reactive node is as cheap and fast as passing a table reference. Operators and string concatenation read a node's current value automatically (see [Signals](/guide/concepts/signals)), so `"Count: " .. props.count`{luau} just works inside a Computed.

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

Props are ideal when the consumer is a direct child or a shallow descendant. Once you find yourself threading the same node through many intermediate layers that don't use it themselves (_prop-drilling_), reach for Context instead.

## Injecting Down the Tree (`Flux.context`)

When the components that need a value are buried deep beneath the one that owns it, threading the node through every layer becomes noise. [`Flux.context`](/guide/concepts/context) injects a value at a parent and lets any descendant read it directly, with no intermediate plumbing.

Reach for it when a value is _ambient_ to a whole subtree (a theme, the active player, a service handle) rather than the concern of one specific child. Provide it once at the root of that subtree, and every component built underneath can read it.

> [!IMPORTANT]
> Read context **synchronously, at construction**: capture it into a local and close over it. A deferred reader (an effect, an `async`/map body, or a binding that re-runs) reads only the default, because `provide` has popped by then. To keep the injected value reactive, make it a [Signal](/guide/concepts/signals) or [Store](/guide/concepts/stores). See [The Run-Once Caveat](/guide/concepts/context#the-run-once-caveat) for the full rules.

## Global State (ModuleScripts)

In Roblox, the client is a single-user environment, and [`ModuleScripts`](https://create.roblox.com/docs/en-us/reference/engine/classes/ModuleScript) act as strictly-cached singletons. That makes them the simplest home for truly global state.

**Global State in Flux is just a ModuleScript.**

Create a Signal or Store inside a ModuleScript and return it. Any script that [`requires`](https://create.roblox.com/docs/en-us/reference/engine/globals/LuaGlobals#require) this module shares the exact same reactive graph.

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

A ModuleScript singleton is shared only **within one Luau VM**; the server and each client hold their own independent copy, not a networked one. Keep global state on whichever side owns it; to bridge the two, replicate over a RemoteEvent and fold each snapshot into the receiving Store with [`Flux.Store.reconcile`](/guide/concepts/stores#reconciling-snapshots) instead of rebuilding it, so only the nodes whose leaves actually changed will fire.

## Scoped Shared State

Sometimes state should be shared among many components but not truly _global_: a complex `Inventory` system whose UI files share underlying data that should be wiped from memory when the inventory closes.

A [Scope](/guide/concepts/scopes) gives you that boundary: create the shared state inside a scope at the root of the system, pass it down, and a single `:Destroy()`{luau} tears the whole ecosystem down. See [Scopes](/guide/concepts/scopes) for the lifecycle API.

```luau
local function InventorySystem()
    -- 1. Create a localized memory scope for the entire system
    local scope, ui = Flux.scope(function()
        -- 2. Shared state, owned by this scope
        local selectedItem = Flux(nil)

        -- The root is built inside the scope, so Destroy frees the whole UI
        return new "Frame" {
            Size = UDim2.fromScale(1, 1),

            -- Pass shared state to sub-components
            Sidebar({ selected = selectedItem }),
            ItemGrid({ selected = selectedItem }),
        }
    end)

    -- Return both so the caller can control the lifetime
    return ui, scope
end

local invUI, invScope = InventorySystem()

-- When the player closes the inventory, wipe the entire shared state ecosystem
invScope:Destroy()
```

## Subscribing Externally (`Flux.listen`{lua})

When a system _outside_ the reactive graph needs to react to a node (a non-Flux module, a service wrapper), subscribe a plain callback with [`Flux.listen`](/guide/concepts/effects); it returns a disconnect function. It's the imperative counterpart to an Effect, so its mechanics and the Effect-vs-listen trade-off live with [Effects](/guide/concepts/effects).

## Summary

Flux's separation of the reactive graph from the component hierarchy means you don't need complex state management libraries.

| Pattern                 | Use when                                                             |
| :---------------------- | :------------------------------------------------------------------- |
| **Props**               | Local sharing between an immediate parent and shallow descendants    |
| **Context**             | Injecting an ambient value into a deep subtree without prop-drilling |
| **ModuleScripts**       | Truly global state (settings, player data, round state)              |
| **Scoped shared state** | Temporary systems that need a clean shutdown (minigames, UI windows) |
| **`Flux.listen`{lua}**  | Bridging _out_ to non-Flux systems                                   |
