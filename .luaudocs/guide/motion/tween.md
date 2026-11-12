---
title: Tween
description: Creating fixed-duration, reactive animations in Flux.
outline: deep
sidebar_position: 2
---

# Tween

`Flux.tween(target, tweenInfo?)` returns a reactive node that animates toward its target over a fixed duration and easing curve, reusing Roblox's [`TweenInfo`](https://create.roblox.com/docs/reference/engine/datatypes/TweenInfo) without imperative `Tween:Play()` and `Tween:Cancel()` boilerplate.

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

`Flux.tween` takes two arguments:

1. **`target`**: The value (or reactive source) the tween animates toward.
2. **`tweenInfo`** *(optional)*: A Roblox [`TweenInfo`](https://create.roblox.com/docs/reference/engine/datatypes/TweenInfo) controlling duration (`Time`), easing style, direction, repeat count, and `Reverses` (`TweenInfo.DelayTime` is ignored so retargets respond immediately). Defaults to `0.3` seconds with `Cubic` `InOut` easing.

The returned `Flux.Tween<T>` node works like a [Signal](/guide/concepts/signals). Read it with `tween()`, retarget it with `tween(newGoal)` or `:set(newGoal)`, and bind it directly to properties.

## Reactive Targets

Pass a [Signal](/guide/concepts/signals), [Computed](/guide/concepts/computeds), or plain function `() -> T` as `target`. Whenever the source updates, the tween redirects smoothly from its current in-flight value toward the new goal:

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
	MouseEnter = function()
		isHovering(true)
	end,
	MouseLeave = function()
		isHovering(false)
	end,
}
```

For occlusion-aware hover tracking in layered UIs, drive `target` from [`Flux.Interact.hover`](/guide/utilities/interact#hover) instead of raw `MouseEnter` and `MouseLeave` events.

## Reactive TweenInfo

`tweenInfo` can also be a reactive node or function. When it updates, an active animation restarts from its current value over the full new duration and easing parameters (resetting elapsed time and repeat count):

```luau
local isFastMode = Flux.signal(false)
local targetPosition = Flux.signal(UDim2.fromScale(0, 0))

local slidingPosition = Flux.tween(targetPosition, function()
	return if isFastMode()
		then TweenInfo.new(0.1, Enum.EasingStyle.Linear)
		else TweenInfo.new(0.5, Enum.EasingStyle.Exponential)
end)
```

## Snap & Instant Placement {#snap}

Call `tween:snap(value?)` when you need an animated value to jump cleanly without waiting out the curve (such as resetting a bar or canceling a repeating loop):

- **`tween:snap(value)`**: Jumps the current value and goal to `value`, clears active repeats or reversals, and leaves the tween at rest.
- **`tween:snap()`**: Jumps straight to the tween's current goal and settles at rest.

```luau
local progress = Flux.tween(0, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))

progress(1)
progress:snap()  -- jumps directly to 1 at rest
progress:snap(0) -- resets target and current value to 0 immediately
```

## Lifecycle

When created inside a [Scope](/guide/concepts/scopes), a tween's per-frame step registration cleans up automatically when the scope is destroyed. To stop and dispose a tween early, call `tween:Destroy()`.

> [!CAUTION] A Bound Tween Is Not Owned by Its Instance
> `Flux.new` and `Flux.edit` own a getter function bound to a property (`Size = function() ... end`), whereas a tween passed straight to a property (`Size = Flux.tween(fn)`) only attaches a property binding. Created outside any owner, a tween with a reactive target or `tweenInfo` keeps its driving Effect subscribed to those sources after the instance is destroyed. Create the tween inside a [Scope](/guide/concepts/scopes) that tears down with the instance, or pass it to `__CLEAN`:
>
> ```luau
> local width = Flux.tween(function()
> 	return if isOpen() then UDim2.fromOffset(300, 40) else UDim2.fromOffset(0, 40)
> end)
>
> local panel = Flux.new "Frame" {
> 	Size = width,
> 	__CLEAN = { width }, -- destroying `panel` destroys the tween and its Effect
> }
> ```

<!--@include: ./_snippets/data-types.md-->
