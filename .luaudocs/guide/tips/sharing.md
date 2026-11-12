---
title: Sharing State
description: Patterns for sharing reactive state across components and systems in Flux.
outline: deep
sidebar_position: 3
---

# Sharing State

In Flux, **reactivity is independent of the UI tree**. A [Signal](/guide/concepts/signals) or [Store](/guide/concepts/stores) is a standalone value. It doesn't care where it was created or which component reads it.

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

local function CounterControls(props: { count: Flux.State<number> })
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
		CounterDisplay({ count = sharedCount }),
		CounterControls({ count = sharedCount }),
	}
end
```

## 2. Ambient Subtree State (`Flux.context`)

When many components deep in a subtree need the same ambient value (such as a theme, active locale, or modal controller), use [`Flux.context`](/guide/concepts/context) instead of threading props through every intermediate layer:

```luau
local ThemeContext = Flux.context("Dark")

ThemeContext:provide("Light", function()
	-- Any descendant created inside this block (including inside Computeds,
	-- Effects, and event handlers) reads "Light" from ThemeContext:get()
	return MainWindow()
end)
```

## 3. Global State (`ModuleScript`s)

Because Roblox caches [`ModuleScript`](https://create.roblox.com/docs/reference/engine/classes/ModuleScript) return values per Luau VM, global client state is just a `ModuleScript` that returns a Signal or [Store](/guide/concepts/stores):

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

To sync server state into a client Store over a `RemoteEvent`, pass each incoming table snapshot to [`Flux.Store.reconcile(store, snapshot)`](/guide/concepts/stores#reconciling-snapshots) so only changed leaves fire. For reactive signals replicated directly between the server and clients (including per-player state and client-to-server validation), use [`Flux.Sync`](/guide/concepts/sync).

## 4. Scoped Feature State (`Flux.scope`)

When state is shared across a feature (like an inventory window or minigame) that should tear down completely when closed, create the state and UI inside a [Scope](/guide/concepts/scopes):

```luau
local function InventorySystem()
	local scope, ui = Flux.scope(function()
		local selectedItem = Flux.signal(nil :: string?)

		return Flux.new "Frame" {
			Size = UDim2.fromScale(1, 1),
			Sidebar({ selected = selectedItem }),
			ItemGrid({ selected = selectedItem }),
		}
	end)

	return ui, scope -- call scope:Destroy() when closing the feature
end
```

## 5. Subscribing Outside Flux (`Flux.listen` & `Flux.on`)

To subscribe an imperative callback to a `Node` outside the reactive graph, pass a Signal or Computed node to [`Flux.listen`](/guide/concepts/effects#bridging-to-external-systems). Like [`RBXScriptSignal:Connect`](https://create.roblox.com/docs/reference/engine/datatypes/RBXScriptSignal#Connect), it fires on subsequent updates on its own [`task.spawn`](https://create.roblox.com/docs/reference/engine/libraries/task#spawn) thread:

```luau
-- Derive a Node when listening to a Store field (or pass a Flux.signal directly)
local masterVolume = Flux.computed(function()
	return settings.audio.masterVolume
end)

local disconnect = Flux.listen(masterVolume, function(volume)
	masterSoundGroup.Volume = volume
end)

-- Call disconnect() (and masterVolume:Destroy() if unowned) when done
```

For synchronous, scope-owned reactions that also run on the initial flush (or receive `prevVolume`), pass a Node or getter function to [`Flux.on`](/guide/concepts/tracking#flux-on) inside [`Flux.effect`](/guide/concepts/effects):

```luau
local effectNode = Flux.effect(Flux.on(function()
	return settings.audio.masterVolume
end, function(volume, prevVolume)
	masterSoundGroup.Volume = volume
end))
```

## Summary

| Pattern | Best For |
| :--- | :--- |
| **Props** | Passing state from a parent to direct or shallow children |
| **`Flux.context`** | Ambient values shared across a deep UI subtree (themes, locales) |
| **`ModuleScript`s** | Client-wide singletons (player settings, session data, round state) |
| **`Flux.Sync`** | Server-to-client synced state (shared, per-player, or validated writes) |
| **`Flux.scope`** | Multi-component features with a bounded lifetime (windows, minigames) |
| **`Flux.listen`** | Bridging reactive updates out to external or yielding systems |
