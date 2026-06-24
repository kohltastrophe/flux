---
title: Spring
description: Creating fluid, physics-based, and interruptible animations in Flux.
outline: deep
---

# Spring

Tweens run for a fixed duration. **Springs** are driven by physics, which makes them a good fit for interactive motion.

If the user interrupts a spring animation halfway through (for example, by moving their mouse off a button before it finishes enlarging), the spring redirects its velocity toward the new target instead of snapping.

Flux springs are reactive and understand Roblox data types directly.

## Basic Usage

You can create a Spring by calling `Flux.spring()`{luau}.

The function takes three arguments:

1. **Target**: The value the spring should move toward.
2. **Frequency** _(Optional, default 1)_: How fast the spring moves.
3. **Damping** _(Optional, default 1)_: How the spring settles. `1` = no bounce (critically damped); lower = bouncier.

The resulting Spring acts exactly like a standard Flux [**Signal**](/guide/concepts/signals). You can bind it directly to UI properties.

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

Flux springs are part of the reactive graph.

Instead of passing a static initial value, you can pass an existing Flux [`Signal`](/guide/concepts/signals) (or a [`Computed`](/guide/concepts/computeds)) directly into the `Flux.spring`{lua} constructor. The spring then tracks that state, and retargets itself whenever the underlying state changes.

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

    MouseEnter = function() isHovering(true) end,
    MouseLeave = function() isHovering(false) end,
}
```

> [!NOTE]
> You can also pass [nodes](/guide/concepts/signals) for `frequency`{luau} and `damping`{luau}, retuning the spring's physics at runtime; it re-reads them whenever they change.

## Velocity Control: Impulse & Set Velocity

A spring carries **velocity**, not just a position, which is what lets it redirect mid-flight. Usually that velocity is managed for you, but sometimes you want to inject it directly: a knockback on hit, a flick gesture, a card that gets "thrown". Springs expose two methods for this:

- **`spring:impulse(delta)`{luau}**: _adds_ `delta` to the current velocity, in value-units per second. For a spring driving an offset in pixels, `-800` means 800 pixels per second upward. Impulses accumulate.
- **`spring:setVelocity(v)`{luau}**: _replaces_ the current velocity outright.

Both take a value of the spring's own datatype, and both re-wake a spring that had already settled, so it animates again from wherever it is.

```luau
local y = Flux.spring(0, 4, 0.6)

local ui = new "Frame" {
    Position = function()
        return UDim2.fromOffset(0, y())
    end,
}

-- Kick it upward; it springs back to its target (0) on its own
local function onHit()
    y:impulse(-800)
end

-- Cancel any in-flight momentum; the spring eases back to its target from a standstill
local function onGrab()
    y:setVelocity(0)
end
```

Because impulse and set-velocity touch only the velocity, they compose naturally with a [reactive target](#reactive-targets): a later target change still retargets the spring, and the injected velocity carries through the physics.

> [!NOTE]
> These methods are spring-only. Calling them on a [Tween](/guide/motion/tween) (which has no physical velocity) warns and does nothing.

## Tuning the Physics

Springs are controlled by two physical properties:

- **Frequency:** Determines how fast the spring moves. Higher values mean faster motion. A frequency of `1` means the spring completes roughly one full cycle of its motion in one second.
- **Damping:** Determines how the spring settles at its target.
  - **`1` (Critically Damped):** The default. The spring will quickly approach the target and smoothly stop exactly on it without any overshoot or bounce.
  - **`< 1` (Underdamped):** The spring will overshoot the target and bounce back and forth before settling. Lower values create more violent, longer-lasting bounces.
  - **`> 1` (Overdamped):** The spring will move sluggishly and take a longer time to ease into the target.

## Lifecycle

A spring's [node](/guide/concepts/signals) is a plain signal, so the [scope](/guide/concepts/scopes) it was created in (usually the [component](/guide/concepts/components) that built it) does not own it; the GC reclaims it once unreferenced. The spring's per-frame **engine registration** _is_ tied to that scope, though: when the scope is destroyed the spring stops animating and unregisters from the engine automatically, so springs built into your UI need no manual cleanup.

To tear one down early, call `spring:Destroy()`{luau}: it stops the animation, removes it from the engine's stepped set, and disposes the underlying node.

<!--@include: ./snippets/data-types.md-->
