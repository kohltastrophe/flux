---
title: Spring
description: Physics-based, interruptible spring animations in Flux.
outline: deep
sidebar_position: 1
---

# Spring

`Flux.spring(target, frequency?, damping?, initialVelocity?)` returns a reactive node driven by damped harmonic motion. When its target changes mid-flight, a spring preserves its momentum and smoothly redirects toward the new goal instead of snapping.

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

`Flux.spring` takes up to four arguments:

1. **`target`**: The initial value (or reactive source) the spring moves toward.
2. **`frequency`** *(optional, default `1`)*: Speed in cycles per second (values `<= 0` clamp to `1e-4`). Higher values move faster.
3. **`damping`** *(optional, default `1`)*: How the spring settles (values `<= 0` clamp to `1e-4`):
   - **`1` (Critically Damped):** Approaches the target quickly and stops without overshoot.
   - **`< 1` (Underdamped):** Overshoots the target and bounces before settling.
   - **`> 1` (Overdamped):** Eases slowly into the target without bouncing.
4. **`initialVelocity`** *(optional)*: Starting velocity in the target's type (read once via `Flux.raw`, not tracked reactively). Omit to start at rest.

A spring works like a standard [Signal](/guide/concepts/signals). Read it with `spring()` or `:get()`, retarget it with `spring(newGoal)` or `:set(newGoal)`, and bind it directly to Instance properties.

## Reactive Targets

Pass a [Signal](/guide/concepts/signals), [Computed](/guide/concepts/computeds), or plain function `() -> T` as `target` to retarget the spring automatically whenever its dependencies change:

```luau
local isHovering = Flux.signal(false)

local buttonSize = Flux.spring(function()
	return if isHovering() then UDim2.fromScale(1.1, 1.1) else UDim2.fromScale(1, 1)
end, 3, 0.75)

local myButton = Flux.new "TextButton" {
	Size = buttonSize,
	Text = "Hover Me",
	MouseEnter = function()
		isHovering(true)
	end,
	MouseLeave = function()
		isHovering(false)
	end,
}
```

For pointer hover that also drops when an overlay opens above the button or a container scrolls underneath the cursor, pair the spring with [`Flux.Interact.hover`](/guide/utilities/interact#hover). `frequency` and `damping` also accept reactive nodes or functions, so you can retune the spring's physics on the fly.

## Velocity Control: Impulse & Set Velocity

Springs expose two methods to manipulate velocity directly without changing the target:

- **`spring:impulse(delta)`**: Adds `delta` (in units per second) to the current velocity. Multiple impulses accumulate.
- **`spring:setVelocity(velocity)`**: Replaces the current velocity outright.

Both take a value of the spring's datatype and wake a settled spring right away:

```luau
local y = Flux.spring(0, 4, 0.6)

-- Kick upward at 800 px/s, then let the spring settle back to 0
local function onHit()
	y:impulse(-800)
end

-- Cancel in-flight momentum
local function onGrab()
	y:setVelocity(0)
end
```

## Snap & Instant Placement {#snap}

When you need to reposition a spring immediately without a transition (for example, on initial open or while dragging), use `:snap()` or `:setCurrent()`:

- **`spring:snap(value?)`**: Sets both the target and current animated value to `value` (or to the spring's current target when `value` is omitted) and zeroes velocity, putting the spring at rest right away.
- **`spring:setCurrent(value)`**: Sets the current animated value to `value` while preserving the existing target and velocity, waking the spring so it animates from `value` back toward its target.

```luau
local offset = Flux.spring(0, 3, 0.85)

-- Jump directly to 100 at rest (no animation)
offset:snap(100)

-- Displace the current position to 140, then settle directly to its target later
offset:setCurrent(140)
offset:snap()
```

`:impulse()`, `:setVelocity()`, and `:setCurrent()` are spring-only (calling them on a [Tween](/guide/motion/tween) warns and does nothing), whereas `:snap(value?)` works on both Springs and Tweens. Calling any motion method on an already-destroyed node warns and does nothing.

## Lifecycle

When created inside a [Scope](/guide/concepts/scopes) (such as a component), a spring's per-frame step registration cleans up automatically when the scope is destroyed. To stop and dispose a spring early, call `spring:Destroy()`.

> [!CAUTION] A Bound Spring Is Not Owned by Its Instance
> `Flux.new` and `Flux.edit` own a getter function bound to a property (`Position = function() ... end`), whereas a spring passed straight to a property (`Position = Flux.spring(fn)`) only attaches a property binding. Created outside any owner, a spring with a reactive `target`, `frequency`, or `damping` keeps its driving Effect subscribed to those sources after the instance is destroyed. Create the spring inside a [Scope](/guide/concepts/scopes) that tears down with the instance, or pass it to `__CLEAN`:
>
> ```luau
> local _, button = Flux.scope(function(scope)
> 	return Flux.new "TextButton" {
> 		Size = Flux.spring(function()
> 			return if isHovering() then UDim2.fromScale(1.1, 1.1) else UDim2.fromScale(1, 1)
> 		end, 3, 0.75),
> 		__CLEAN = { scope }, -- destroying `button` destroys the scope, which owns the spring
> 	}
> end)
> ```

<!--@include: ./_snippets/data-types.md-->
