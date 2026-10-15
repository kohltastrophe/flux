---
title: Sharing State
description: Patterns for sharing reactive state across components and systems in Flux.
outline: deep
sidebar_position: 3
---

# Sharing State

In Flux, **reactivity is independent of the UI tree**. A [Signal](/guide/concepts/signals) or [Store](/guide/concepts/stores) is a standalone value—it does not care where it was created or which component reads it.

## 1. Lifting State Up (Props)

To share state between sibling components, create the Signal in their parent and pass it down as a prop:

```luau
local function CounterDisplay(props: { count: Flux.Node<number> })
    return Flux.new "TextLabel" {
        Size = UDim2.fromOffset(200, 50),
        Text = function()
            return `Count: {props.count()}`
        end,
    }
end

local function CounterControls(props: { count: Flux.Node<number> })
    return Flux.new "TextButton" {
        Size = UDim2.fromOffset(200, 50),
        Text = "Increment",
        Activated = function()
            props.count(props.count() + 1)
        end,
    }
end

local function App()
    local sharedCount = Flux.signal(0)

    return Flux.new "Frame" {
        Size = UDim2.fromScale(1, 1),
        CounterDisplay { count = sharedCount },
        CounterControls { count = sharedCount },
    }
end
```

## 2. Ambient Subtree State (`Flux.context`{luau})

When many components deep in a subtree need the same ambient value (such as a theme, active locale, or modal controller), use [`Flux.context`](/guide/concepts/context) instead of threading props through every intermediate layer:

```luau
local ThemeContext = Flux.context("Dark")

ThemeContext:provide("Light", function()
    -- Any descendant created inside this block (including inside Computeds,
    -- Effects, and event handlers) reads "Light" from ThemeContext:consume()
    return MainWindow()
end)
```

## 3. Global State (`ModuleScript`{luau}s)

Because Roblox caches [`ModuleScript`](https://create.roblox.com/docs/en-us/reference/engine/classes/ModuleScript) return values per Luau VM, global client state is simply a `ModuleScript`{luau} that returns a Signal or [Store](/guide/concepts/stores):

**`State/PlayerSettings.luau`**
```luau
local Flux = require(ReplicatedStorage.Flux)

return Flux.store({
    audio = {
        masterVolume = 0.5,
        musicMuted = false,
    },
    ui = {
        theme = "Dark",
    },
})
```

**`UI/MuteButton.luau`**
```luau
local Flux = require(ReplicatedStorage.Flux)
local settings = require(ReplicatedStorage.State.PlayerSettings)

local function MuteButton()
    return Flux.new "TextButton" {
        Text = function()
            return if settings.audio.musicMuted then "Unmute" else "Mute"
        end,
        Activated = function()
            settings.audio.musicMuted = not settings.audio.musicMuted
        end,
    }
end
```

To sync server state into a client Store over a `RemoteEvent`{luau}, pass each incoming table snapshot to [`Flux.Store.reconcile(store, snapshot)`](/guide/concepts/stores#reconciling-snapshots) so only changed leaves fire.

## 4. Scoped Feature State (`Flux.scope`{luau})

When state is shared across a feature (like an inventory window or minigame) that should be completely torn down when closed, create the state and UI inside a [Scope](/guide/concepts/scopes):

```luau
local function InventorySystem()
    local scope, ui = Flux.scope(function()
        local selectedItem = Flux.signal(nil :: string?)

        return Flux.new "Frame" {
            Size = UDim2.fromScale(1, 1),
            Sidebar { selected = selectedItem },
            ItemGrid { selected = selectedItem },
        }
    end)

    return ui, scope -- call scope:Destroy() when closing the feature
end
```

## 5. Subscribing Outside Flux (`Flux.effect`{luau} + `Flux.on`{luau})

To bridge a reactive node out to non-Flux imperative code with explicit dependency tracking, wrap [`Flux.on`](/guide/concepts/effects#bridging-to-external-systems-with-flux-on) in [`Flux.effect`](/guide/concepts/effects):

```luau
local effectNode = Flux.effect(Flux.on(settings.audio.masterVolume, function(volume, prevVolume)
    SoundService.RespectFilteringEnabled = true
    masterSoundGroup.Volume = volume
end))

-- Call effectNode:Destroy() when you want to stop listening
```

## Summary

| Pattern               | Best For                                                               |
| :-------------------- | :--------------------------------------------------------------------- |
| **Props**             | Passing state from a parent to direct or shallow children              |
| **`Flux.context`**    | Ambient values shared across a deep UI subtree (themes, locales)       |
| **`ModuleScript`s**   | Client-wide singletons (player settings, session data, round state)    |
| **`Flux.scope`**      | Multi-component features with a bounded lifetime (windows, minigames)  |
| **`Flux.effect` + `Flux.on`** | Bridging reactive changes out to external imperative systems   |
