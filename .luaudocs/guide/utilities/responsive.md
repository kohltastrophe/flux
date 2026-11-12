---
title: Responsive
description: Shared reactive nodes for viewport size, UI scale, breakpoints, device platform, active input mode, and player accessibility preferences.
outline: deep
sidebar_position: 1
---

# Responsive

`Flux.Responsive` exposes the screen, input device, and player accessibility settings as shared reactive [nodes](/guide/concepts/signals), ready to read or bind directly with zero setup:

```luau
Flux.new "ScreenGui" {
	Parent = playerGui,

	Flux.new "Frame" {
		Size = UDim2.fromOffset(800, 600),
		Flux.new "UIScale" { Scale = Flux.Responsive.scale },
	},
}
```

All nodes listen live on the Roblox client and in **Studio edit mode** (so UI storybooks and Studio plugins react as you resize panes or switch input devices). On the server and in headless Luau, they hold static defaults (`1920×1080`, `"desktop"`, `"Medium"` display/text size, `"pc"`, `"keyboard"`, `reducedMotion = false`, and `preferredTransparency = 1`).

For safe areas (the Roblox topbar, device notches, and rounded corners), configure Roblox's built-in [`ScreenGui.ScreenInsets`](https://create.roblox.com/docs/reference/engine/classes/ScreenGui#ScreenInsets) (`CoreUISafeInsets` or `DeviceSafeInsets`) and `ScreenGui.SafeAreaCompatibility`.

## Screen & Layout Nodes

### Viewport {#viewport}

`Flux.Responsive.viewport` (`Node<Vector2>`) tracks `workspace.CurrentCamera.ViewportSize` live on the client and in Studio edit mode (defaulting to `1920×1080` on the server or headless CLI):

```luau
local isPortrait = Flux.computed(function()
	local vp = Flux.Responsive.viewport()
	return vp.Y > vp.X
end)
```

### Scale {#scale}

`Flux.Responsive.scale` (`Node<number>`) computes a UI scale factor from `viewport` where `1.0` matches `config.reference` (`1920×1080` by default, using `"min"` fit mode so UI never overflows):

```luau
Flux.new "UIScale" { Scale = Flux.Responsive.scale }
```

### Breakpoint {#breakpoint}

`Flux.Responsive.breakpoint` (`Node<"phone" | "tablet" | "desktop">`) classifies the viewport width (`< 600` phone, `< 1024` tablet, `>= 1024` desktop by default). Pair it with [`Flux.switch`](/guide/concepts/conditionals#switching-between-many-branches) to swap layouts by screen width:

```luau
Flux.switch(Flux.Responsive.breakpoint)({
	phone = function(): GuiObject
		return CompactLayout()
	end,
	tablet = function(): GuiObject
		return CompactLayout()
	end,
	desktop = function(): GuiObject
		return WideLayout()
	end,
})
```

### Display Size {#display-size}

`Flux.Responsive.displaySize` (`Node<"Small" | "Medium" | "Large">`) mirrors [`GuiService.ViewportDisplaySize`](https://create.roblox.com/docs/reference/engine/classes/GuiService#ViewportDisplaySize), indicating physical screen size (`"Small"` for phones and handhelds, `"Medium"` for monitors and laptops, `"Large"` for TVs and ten-foot interfaces).

## Device & Input Nodes

### Platform {#platform}

`Flux.Responsive.platform` (`Node<"pc" | "mobile" | "console" | "vr">`) reflects the active device class on the client and in Studio edit mode, updating live if the player connects a keyboard and mouse or enters VR (`"pc"` on the server or headless CLI):

```luau
Flux.new "TextButton" {
	Size = function()
		return if Flux.Responsive.platform() == "pc"
			then UDim2.fromOffset(160, 36)
			else UDim2.fromOffset(200, 48)
	end,
}
```

### Input {#input}

`Flux.Responsive.input` (`Node<"keyboard" | "touch" | "gamepad">`) tracks `UserInputService.PreferredInput` and `LastInputTypeChanged` live (mapping `Gamepad1`-`Gamepad8` and `MicroGamepad` to `"gamepad"`), switching automatically when the player picks up a controller, touches the screen, or reaches for the mouse and keyboard:

```luau
local promptText = Flux.computed(function()
	return if Flux.Responsive.input() == "gamepad" then "Press [A]" else "Click to Continue"
end)
```

## Accessibility Nodes

### Text Size {#text-size}

`Flux.Responsive.textSize` (`Node<"Medium" | "Large" | "Larger" | "Largest">`) tracks [`GuiService.PreferredTextSize`](https://create.roblox.com/docs/reference/engine/classes/GuiService#PreferredTextSize). Roblox scales text rendering automatically for this setting. Use `textSize` to give surrounding containers extra breathing room, not to multiply `TextSize` a second time.

### Reduced Motion {#reduced-motion}

`Flux.Responsive.reducedMotion` (`Node<boolean>`) tracks [`GuiService.ReducedMotionEnabled`](https://create.roblox.com/docs/reference/engine/classes/GuiService#ReducedMotionEnabled). When `true`, prefer instant state changes or subtle opacity fades over large movement or scale animations.

### Preferred Transparency {#preferred-transparency}

`Flux.Responsive.preferredTransparency` (`Node<number>`) tracks [`GuiService.PreferredTransparency`](https://create.roblox.com/docs/reference/engine/classes/GuiService#PreferredTransparency) from `0` (fully opaque backgrounds) to `1` (default). Multiply translucent background transparencies by this node to respect the player's contrast preference:

```luau
Flux.new "Frame" {
	BackgroundTransparency = function()
		return 0.35 * Flux.Responsive.preferredTransparency()
	end,
}
```

## Configuration {#configuration}

`Flux.Responsive.config` is a plain table read when `scale` and `breakpoint` first evaluate. Mutate it once at startup **before** reading `Flux.Responsive.scale` or `Flux.Responsive.breakpoint` to customize the default reference resolution, scale mode, clamps, or breakpoint widths:

```luau
Flux.Responsive.config.reference = Vector2.new(1280, 720)
Flux.Responsive.config.mode = "height" -- "min" (default) | "width" | "height" | "max"
Flux.Responsive.config.min = 0.5
Flux.Responsive.config.max = 2
Flux.Responsive.config.breakpoints = { phone = 700, tablet = 1100 }
```

### Per-Surface Overrides {#per-surface-overrides}

Use `Flux.Responsive.scaleOf(partialConfig?)` and `Flux.Responsive.breakpointOf(partialConfig?)` to create derived nodes with custom thresholds or a custom `viewport` source (such as a `SurfaceGui` or Studio `DockWidgetPluginGui`):

```luau
local dockSize = Flux.property(dockWidget, "AbsoluteSize")

local dockScale = Flux.Responsive.scaleOf({
	viewport = dockSize,
	reference = Vector2.new(400, 600),
})

local dockBreakpoint = Flux.Responsive.breakpointOf({
	viewport = dockSize,
	breakpoints = { phone = 320, tablet = 480 },
})
```
