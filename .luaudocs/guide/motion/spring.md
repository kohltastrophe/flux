---
title: Spring
description: Creating fluid, physics-based, and interruptible animations in Flux.
outline: deep
sidebar_position: 1
---

# Spring

`Flux.spring(target, frequency?, damping?, initialVelocity?)`{luau} returns a reactive node driven by damped harmonic motion. When its target changes mid-flight, a spring preserves its momentum and smoothly redirects toward the new goal instead of snapping.

```luau
local xPosition = Flux.spring(0, 2, 0.8)

local ui = Flux.new "Frame" {
    Size = UDim2.fromOffset(100, 100),
    Position = function()
        return UDim2.fromOffset(xPosition(), 0)
    end,
}

-- Smoothly animate toward 200
xPosition(200)
```

## Basic Usage

`Flux.spring`{luau} takes up to four arguments:

1. **`target`{luau}**: The initial value (or reactive source) the spring moves toward.
2. **`frequency`{luau}** _(optional, default `1`{luau})_: Speed in cycles per second. Higher values move faster.
3. **`damping`{luau}** _(optional, default `1`{luau})_: How the spring settles:
   - **`1`{luau} (Critically Damped):** Quickly approaches the target and stops without overshoot.
   - **`< 1`{luau} (Underdamped):** Overshoots the target and bounces before settling.
   - **`> 1`{luau} (Overdamped):** Eases sluggishly into the target without bouncing.
4. **`initialVelocity`{luau}** _(optional)_: Starting velocity in the target's type (for example, a `Vector2`{luau} for a `Vector2`{luau} spring); omit to start at rest.

A spring acts like a standard [Signal](/guide/concepts/signals): read it with `spring()`{luau} or `:get()`{luau}, retarget it with `spring(newGoal)`{luau} or `:set(newGoal)`{luau}, and bind it directly to Instance properties.

## Reactive Targets

Pass a [Signal](/guide/concepts/signals), [Computed](/guide/concepts/computeds), or plain function `() -> T`{luau} as `target`{luau} to retarget the spring automatically whenever its dependencies change:

```luau
local isHovering = Flux.signal(false)

local buttonSize = Flux.spring(function()
    return if isHovering() then UDim2.fromScale(1.1, 1.1) else UDim2.fromScale(1, 1)
end, 3, 0.75)

local myButton = Flux.new "TextButton" {
    Size = buttonSize,
    Text = "Hover Me",
    MouseEnter = function() isHovering(true) end,
    MouseLeave = function() isHovering(false) end,
}
```

> [!NOTE]
> `frequency`{luau} and `damping`{luau} also accept reactive nodes or functions, retuning the spring's physics on the fly.

## Velocity Control: Impulse & Set Velocity

Springs expose two methods to manipulate velocity directly without changing the target:

- **`spring:impulse(delta)`{luau}**: Adds `delta`{luau} (in units per second) to the current velocity. Multiple impulses accumulate.
- **`spring:setVelocity(velocity)`{luau}**: Replaces the current velocity outright.

Both take a value of the spring's datatype and wake a settled spring immediately:

```luau
local y = Flux.spring(0, 4, 0.6)

-- Kick upward at 800 px/s; the spring settles back to 0 on its own
local function onHit()
    y:impulse(-800)
end

-- Cancel in-flight momentum
local function onGrab()
    y:setVelocity(0)
end
```

## Snap & Instant Placement {#snap}

When you need to reposition a spring immediately without a transition (for example, on initial open or while dragging), use `:snap()`{luau} or `:setCurrent()`{luau}:

- **`spring:snap(value)`{luau}**: Sets both the target and current animated value to `value`{luau} and zeroes velocity, putting the spring at rest immediately.
- **`spring:setCurrent(value)`{luau}**: Sets the current animated value to `value`{luau} while preserving the existing target and velocity, waking the spring so it animates from `value`{luau} back toward its target.

```luau
local offset = Flux.spring(0, 3, 0.85)

-- Jump directly to 100 at rest (no animation)
offset:snap(100)

-- Displace the current position to 140; it springs back toward 100
offset:setCurrent(140)
```

> [!NOTE]
> `:impulse()`{luau}, `:setVelocity()`{luau}, `:setCurrent()`{luau}, and `:snap()`{luau} are spring-only. Calling them on a [Tween](/guide/motion/tween) warns and does nothing.

## Lifecycle

When created inside a [Scope](/guide/concepts/scopes) (such as a component), a spring's per-frame step registration is cleaned up automatically when the scope is destroyed. To stop and dispose a spring early, call `spring:Destroy()`{luau}.

<!--@include: ./_snippets/data-types.md-->
