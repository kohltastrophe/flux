---
title: Tween
description: Creating fixed-duration, reactive animations in Flux.
outline: deep
---

# Tween

**[Springs](/guide/motion/spring)** suit physics-driven interactions, but sometimes you need an animation to take a specific amount of time, or follow a specific easing curve.

Roblox handles this with [`TweenService`](https://create.roblox.com/docs/en-us/reference/engine/classes/TweenService), but imperative `Tween:Play()`{luau} and `Tween:Cancel()`{luau} calls don't mix well with a declarative UI library. Flux provides a reactive tweening primitive that reuses Roblox's easing curves, so you can bind it directly to your UI properties like a standard Signal.

## Basic Usage

You create a reactive tween using `Flux.tween()`{luau}.

The function takes two arguments:

1. **Target**: The value the tween should animate toward.
2. **TweenInfo** _(Optional)_: A standard Roblox [`TweenInfo`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/TweenInfo) object that dictates the duration, easing style, and easing direction. If omitted, it defaults to `0.3` seconds with [`Cubic`](https://create.roblox.com/docs/en-us/reference/engine/enums/EasingStyle) [`InOut`](https://create.roblox.com/docs/en-us/reference/engine/enums/EasingDirection) easing.

The resulting object acts like a standard Flux **Signal**, so it can be bound directly to UI properties.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

-- Create a tween starting at 0, using a 1-second Linear tween
local loadingProgress = Flux.tween(
    0,
    TweenInfo.new(1, Enum.EasingStyle.Linear)
)

local progressBar = new "Frame" {
    BackgroundColor3 = Color3.fromRGB(0, 255, 100),

    -- Bind the tweened value directly to the size
    Size = function()
        return UDim2.fromScale(loadingProgress(), 1)
    end
}

-- Later: Update the target to 1 (100%). It will tween there over 1 second.
loadingProgress(1)
```

## Reactive Targets

Like Springs, Flux Tweens are part of the reactive graph. If you pass an existing Flux [`Signal`](/guide/concepts/signals) or [`Computed`](/guide/concepts/computeds) into the `Flux.tween`{lua} constructor, the tween tracks it.

Whenever that underlying state changes, the tween begins animating toward the new target from its current position.

```luau
local isHovering = Flux(false)

-- The target is a Computed based on hover state
local buttonColor = Flux.tween(
    Flux(function()
        return isHovering() and Color3.fromRGB(80, 80, 80) or Color3.fromRGB(45, 45, 45)
    end),
    TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
)

local myButton = new "TextButton" {
    Size = UDim2.fromOffset(200, 50),

    -- Bind the reactive tween
    BackgroundColor3 = buttonColor,

    -- Mutate the underlying state
    MouseEnter = function() isHovering(true) end,
    MouseLeave = function() isHovering(false) end
}
```

## Reactive TweenInfo

In highly dynamic systems, you might want the animation duration or easing style to change based on the state of the game. Flux supports passing a reactive node for the [`TweenInfo`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/TweenInfo) argument as well.

When the underlying [`TweenInfo`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/TweenInfo) node updates, the change takes effect immediately: the in-flight animation continues from its current position using the new duration and easing parameters.

```luau
local isFastMode = Flux(false)
local targetPosition = Flux(UDim2.fromScale(0, 0))

local dynamicTweenInfo = Flux(function()
    if isFastMode() then
        return TweenInfo.new(0.1, Enum.EasingStyle.Linear)
    else
        return TweenInfo.new(0.5, Enum.EasingStyle.Exponential)
    end
end)

-- The tween tracks `targetPosition` and adapts its speed based on `isFastMode`
local slidingPosition = Flux.tween(targetPosition, dynamicTweenInfo)

-- Updating either node animates `slidingPosition` toward the new goal
isFastMode(true)
targetPosition(UDim2.fromScale(1, 0))
```

## Lifecycle

A tween's [node](/guide/concepts/signals) is a plain signal, so the [scope](/guide/concepts/scopes) it was created in (usually the [component](/guide/concepts/components) that built it) does not own it; the GC reclaims it once unreferenced. The tween's per-frame **engine registration** _is_ tied to that scope: when the scope is destroyed the tween stops animating and unregisters from the engine automatically, so tweens built into your UI need no manual cleanup.

To tear one down early, call `tween:Destroy()`{luau}: it stops the animation, removes it from the engine's stepped set, and disposes the underlying node.

<!--@include: ./snippets/data-types.md-->
