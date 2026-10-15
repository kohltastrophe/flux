---
title: Tween
description: Creating fixed-duration, reactive animations in Flux.
outline: deep
sidebar_position: 2
---

# Tween

`Flux.tween(target, tweenInfo?)`{luau} returns a reactive node that animates toward its target over a fixed duration and easing curve, reusing Roblox's [`TweenInfo`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/TweenInfo) without imperative `Tween:Play()`{luau} / `Tween:Cancel()`{luau} boilerplate.

```luau
local loadingProgress = Flux.tween(0, TweenInfo.new(1, Enum.EasingStyle.Linear))

local progressBar = Flux.new "Frame" {
    BackgroundColor3 = Color3.fromRGB(0, 255, 100),
    Size = function()
        return UDim2.fromScale(loadingProgress(), 1)
    end,
}

-- Smoothly tween toward 1 (100%) over 1 second
loadingProgress(1)
```

## Basic Usage

`Flux.tween`{luau} takes two arguments:

1. **`target`{luau}**: The value (or reactive source) the tween animates toward.
2. **`tweenInfo`{luau}** _(optional)_: A Roblox [`TweenInfo`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/TweenInfo) controlling duration, easing style, direction, repeat count, reverses, and delay. Defaults to `0.3`{luau} seconds with `Cubic`{luau} `InOut`{luau} easing.

The returned node works just like a [Signal](/guide/concepts/signals): read it with `tween()`{luau}, retarget it with `tween(newGoal)`{luau} or `:set(newGoal)`{luau}, and bind it directly to properties.

## Reactive Targets

Pass a [Signal](/guide/concepts/signals), [Computed](/guide/concepts/computeds), or plain function `() -> T`{luau} as `target`{luau}. Whenever the source updates, the tween smoothly redirects from its current in-flight value toward the new goal:

```luau
local isHovering = Flux.signal(false)

local buttonColor = Flux.tween(
    function()
        return if isHovering() then Color3.fromRGB(80, 80, 80) else Color3.fromRGB(45, 45, 45)
    end,
    TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
)

local myButton = Flux.new "TextButton" {
    Size = UDim2.fromOffset(200, 50),
    BackgroundColor3 = buttonColor,
    MouseEnter = function() isHovering(true) end,
    MouseLeave = function() isHovering(false) end,
}
```

## Reactive TweenInfo

`tweenInfo`{luau} can also be a reactive node or function. When it updates, the in-flight animation continues from its current position using the new duration and easing parameters:

```luau
local isFastMode = Flux.signal(false)
local targetPosition = Flux.signal(UDim2.fromScale(0, 0))

local slidingPosition = Flux.tween(targetPosition, function()
    return if isFastMode()
        then TweenInfo.new(0.1, Enum.EasingStyle.Linear)
        else TweenInfo.new(0.5, Enum.EasingStyle.Exponential)
end)
```

## Lifecycle

When created inside a [Scope](/guide/concepts/scopes), a tween's per-frame step registration is cleaned up automatically when the scope is destroyed. To stop and dispose a tween early, call `tween:Destroy()`{luau}.

<!--@include: ./_snippets/data-types.md-->
