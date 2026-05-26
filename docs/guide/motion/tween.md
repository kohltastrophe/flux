---
title: Tweens
description: Creating fixed-duration, reactive animations in Flux.
outline: deep
---

# Tweens

While **Springs** are perfect for fluid, physics-driven interactions, sometimes you need an animation to take exactly a specific amount of time, or follow a highly specific easing curve.

Traditional Roblox development relies on [`TweenService`](https://create.roblox.com/docs/en-us/reference/engine/classes/TweenService) to handle this. However, imperative `Tween:Play()`{luau} and `Tween:Cancel()`{luau} calls don't mix well with a declarative UI framework. Flux provides a completely reactive wrapper around tweens, allowing you to bind them directly to your UI properties just like standard Values.

## Basic Usage

You create a reactive tween using `Flux.tween()`{luau}.

The function takes two arguments:

1. **Target**: The value the tween should animate toward.
2. **TweenInfo** _(Optional)_: A standard Roblox [`TweenInfo`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/TweenInfo) object that dictates the duration, easing style, and easing direction. If omitted, it defaults to `0.3` seconds with [`Cubic`](https://create.roblox.com/docs/en-us/reference/engine/enums/EasingStyle) [`InOut`](https://create.roblox.com/docs/en-us/reference/engine/enums/EasingDirection) easing.

The resulting object acts exactly like a standard Flux **Value**, meaning it can be bound directly to UI properties.

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

Just like Springs, the true power of Flux Tweens comes from the reactive graph. If you pass an existing Flux [`Value`](/guide/concepts/values) or [`Computed`](/guide/concepts/computeds) into the `Flux.tween`{lua} constructor, the tween will automatically track it.

Whenever that underlying state changes, the tween instantly calculates the difference and begins animating toward the new target from its current position.

```luau
local isHovering = Flux(false)

-- The target is a Computed Node based on hover state
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
    __EVENT = {
        MouseEnter = function() isHovering(true) end,
        MouseLeave = function() isHovering(false) end
    }
}
```

## Reactive TweenInfo

In highly dynamic systems, you might want the animation duration or easing style to change based on the state of the game. Flux supports passing a reactive Node for the [`TweenInfo`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/TweenInfo) argument as well.

If the underlying [`TweenInfo`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/TweenInfo) node updates, the tween will immediately adopt the new duration and easing parameters for all future target updates.

```luau
local isFastMode = Flux(false)

local dynamicTweenInfo = Flux(function()
    if isFastMode() then
        return TweenInfo.new(0.1, Enum.EasingStyle.Linear)
    else
        return TweenInfo.new(0.5, Enum.EasingStyle.Exponential)
    end
end)

-- The tween will adapt its speed based on `isFastMode`
local slidingPosition = Flux.tween(targetPositionNode, dynamicTweenInfo)
```

## Supported Data Types

Under the hood, Flux handles the complex math required to interpolate properties automatically. You can safely tween almost any standard Roblox data type without manually splitting axes or calculating alphas.

Supported types include:

- [`number`](https://create.roblox.com/docs/en-us/luau/numbers)
- [`UDim`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/UDim) & [`UDim2`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/UDim2)
- [`Vector2`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector2), [`Vector3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector3), [`Vector2int16`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector2int16), [`Vector3int16`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector3int16)
- [`Color3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Color3)
- [`CFrame`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/CFrame)
- [`NumberRange`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/NumberRange), [`NumberSequenceKeypoint`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/NumberSequenceKeypoint), [`ColorSequenceKeypoint`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/ColorSequenceKeypoint)
- [`Rect`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Rect), [`Ray`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Ray), [`PhysicalProperties`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/PhysicalProperties), [`DateTime`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/DateTime)

### 🎨 Oklab Color Interpolation

Just like Springs, when you tween a [`Color3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Color3) value, Flux automatically bypasses standard linear RGB interpolation. It converts your colors into the **Oklab perceptual color space** during the animation. This prevents the "muddy" or "gray" intermediate colors that normally happen when tweening between contrasting hues in Roblox, resulting in vibrant, visually pleasing transitions.
