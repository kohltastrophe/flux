---
title: Springs
description: Creating fluid, physics-based, and interruptible animations in Flux.
outline: deep
---

# Springs

While traditional Tweens are great for fixed-duration animations, modern user interfaces often rely on **Springs** to create fluid, responsive, and natural motion.

Unlike a Tween, a Spring is driven by physics. If the user interrupts an animation halfway through (for example, by moving their mouse off a button before it finishes enlarging), a Spring will smoothly redirect its velocity toward the new target without any jarring snaps or abrupt stops.

Flux provides highly optimized, reactive springs that natively understand Roblox data types.

## Basic Usage

You can create a Spring by calling `Flux.spring()`{luau}.

The function takes three arguments:

1. **Target**: The value the spring should move toward.
2. **Frequency** _(Optional, default 1)_: The speed of the spring.
3. **Damping** _(Optional, default 1)_: The bounciness of the spring.

The resulting Spring acts exactly like a standard Flux [**Value**](/guide/concepts/values). You can bind it directly to UI properties.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

-- Create a spring that starts at X: 0
local xPosition = Flux.spring(0, 2, 0.8)

local ui = new "Frame" {
    Size = UDim2.fromOffset(100, 100),

    -- Bind the spring to the property
    Position = function()
        return UDim2.fromOffset(xPosition(), 0)
    end
}

-- Later: Update the spring's target to 200. It will smoothly animate there.
xPosition(200)
```

## Reactive Targets

The true power of Flux Springs is that they are **fully integrated into the reactive graph**.

Instead of passing a static initial value, you can pass an existing Flux [`Value`](/guide/concepts/values) (or a [`Computed`](/guide/concepts/computeds)) directly into the `Flux.spring`{lua} constructor. When you do this, the Spring automatically tracks that state. Whenever the underlying state changes, the Spring automatically retargets itself!

```luau
local isHovering = Flux(false)

-- The spring's target is driven by a computed value based on `isHovering`
local buttonScale = Flux.spring(
    Flux(function()
        return isHovering() and UDim2.fromScale(1.1, 1.1) or UDim2.fromScale(1, 1)
    end),
    3,    -- Frequency (Speed)
    0.75  -- Damping (Slight bounce)
)

local myButton = new "TextButton" {
    Size = buttonScale, -- Bind the spring directly
    Text = "Hover Me",

    __EVENT = {
        MouseEnter = function() isHovering(true) end,
        MouseLeave = function() isHovering(false) end
    }
}
```

_Note: You can also pass reactive Nodes for the `frequency` and `damping` arguments if you want to dynamically adjust the physics of the animation at runtime!_

## Tuning the Physics

Springs are controlled by two simple physical properties:

- **Frequency:** Determines how fast the spring moves. Higher values mean faster motion. A frequency of `1` means the spring completes roughly one full cycle of its motion in one second.
- **Damping:** Determines how the spring settles at its target.
- **`1` (Critically Damped):** The default. The spring will quickly approach the target and smoothly stop exactly on it without any overshoot or bounce.
- **`< 1` (Underdamped):** The spring will overshoot the target and bounce back and forth before settling. Lower values create more violent, longer-lasting bounces.
- **`> 1` (Overdamped):** The spring will move sluggishly and take a longer time to ease into the target.

## Supported Data Types

The Flux Engine natively interpolates almost all standard Roblox UI and 3D data types seamlessly. You do not need to split out the X, Y, and Z coordinates.

Supported types include:

- [`number`](https://create.roblox.com/docs/en-us/luau/numbers)
- [`UDim`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/UDim) & [`UDim2`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/UDim2)
- [`Vector2`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector2), [`Vector3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector3), [`Vector2int16`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector2int16), [`Vector3int16`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector3int16)
- [`Color3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Color3)
- [`CFrame`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/CFrame)
- [`NumberRange`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/NumberRange), [`NumberSequenceKeypoint`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/NumberSequenceKeypoint), [`ColorSequenceKeypoint`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/ColorSequenceKeypoint)
- [`Rect`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Rect), [`Ray`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Ray), [`PhysicalProperties`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/PhysicalProperties), [`DateTime`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/DateTime)

### 🎨 Oklab Color Interpolation

When you animate a [`Color3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Color3) value using `Flux.spring`{lua} (or `Flux.tween`{lua}), Flux doesn't use standard RGB linear interpolation, which often results in muddy or grayish middle colors.

Instead, Flux automatically converts your colors into the **Oklab perceptual color space** under the hood. This ensures that color transitions are vibrant, naturally blended, and visually accurate to how the human eye perceives light.
