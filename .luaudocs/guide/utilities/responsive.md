---
title: Responsive
description: Shared reactive nodes for viewport size, UI scale, breakpoints, device platform, active input mode, and player accessibility preferences.
outline: deep
sidebar_position: 1
---

# Responsive

`Flux.Responsive`{luau} exposes the screen, input device, and player accessibility settings as shared reactive [nodes](/guide/concepts/signals)—ready to read or bind directly with zero setup:

```luau
Flux.new "ScreenGui" {
    Parent = playerGui,

    Flux.new "Frame" {
        Size = UDim2.fromOffset(800, 600),
        Flux.new "UIScale" { Scale = Flux.Responsive.scale },
    },
}
```

> [!TIP]
> For safe areas (the Roblox topbar, device notches, and rounded corners), configure Roblox's built-in [`ScreenGui.ScreenInsets`](https://create.roblox.com/docs/en-us/reference/engine/classes/ScreenGui#ScreenInsets) (`CoreUISafeInsets`{luau} or `DeviceSafeInsets`{luau}) and `ScreenGui.SafeAreaCompatibility`{luau}.

## Screen & Layout Nodes

### Viewport {#viewport}

`Flux.Responsive.viewport`{luau} (`Node<Vector2>`{luau}) tracks `workspace.CurrentCamera.ViewportSize`{luau} live on the client (and defaults to `1920×1080`{luau} off-client):

```luau
local isPortrait = Flux.computed(function()
    local vp = Flux.Responsive.viewport()
    return vp.Y > vp.X
end)
```

### Scale {#scale}

`Flux.Responsive.scale`{luau} (`Node<number>`{luau}) computes a UI scale factor from `viewport`{luau} where `1.0`{luau} matches `config.reference`{luau} (`1920×1080`{luau} by default, using `"min"`{luau} fit mode so UI never overflows):

```luau
Flux.new "UIScale" { Scale = Flux.Responsive.scale }
```

### Breakpoint {#breakpoint}

`Flux.Responsive.breakpoint`{luau} (`Node<"phone" | "tablet" | "desktop">`{luau}) classifies the viewport width (`< 600`{luau} phone, `< 1024`{luau} tablet, `≥ 1024`{luau} desktop by default). Pair it with [`Flux.switch`](/guide/concepts/conditionals#switching-between-many-branches) to swap layouts by screen width:

```luau
Flux.switch(Flux.Responsive.breakpoint) {
    phone = function() return CompactLayout() end,
    tablet = function() return CompactLayout() end,
    desktop = function() return WideLayout() end,
}
```

### Display Size {#display-size}

`Flux.Responsive.displaySize`{luau} (`Node<"Small" | "Medium" | "Large">`{luau}) mirrors [`GuiService.ViewportDisplaySize`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiService#ViewportDisplaySize), indicating physical screen size (`"Small"`{luau} for phones/handhelds, `"Medium"`{luau} for monitors/laptops, `"Large"`{luau} for TVs/ten-foot interfaces).

## Device & Input Nodes

### Platform {#platform}

`Flux.Responsive.platform`{luau} (`Node<"pc" | "mobile" | "console" | "vr">`{luau}) reflects the active device class on the client, updating live if the player connects a keyboard/mouse or enters VR (`"pc"`{luau} off-client):

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

`Flux.Responsive.input`{luau} (`Node<"keyboard" | "touch" | "gamepad">`{luau}) tracks `UserInputService.PreferredInput`{luau} live on the client, switching automatically when the player picks up a controller, touches the screen, or reaches for the mouse/keyboard:

```luau
local promptText = Flux.computed(function()
    return if Flux.Responsive.input() == "gamepad" then "Press [A]" else "Click to Continue"
end)
```

## Accessibility Nodes

### Text Size {#text-size}

`Flux.Responsive.textSize`{luau} (`Node<"Medium" | "Large" | "Larger" | "Largest">`{luau}) tracks [`GuiService.PreferredTextSize`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiService#PreferredTextSize). Roblox automatically scales text rendering for this setting—use `textSize`{luau} to give surrounding containers extra breathing room, not to multiply `TextSize`{luau} a second time.

### Reduced Motion {#reduced-motion}

`Flux.Responsive.reducedMotion`{luau} (`Node<boolean>`{luau}) tracks [`GuiService.ReducedMotionEnabled`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiService#ReducedMotionEnabled). When `true`{luau}, prefer instant state changes or subtle opacity fades over large movement or scale animations.

### Preferred Transparency {#preferred-transparency}

`Flux.Responsive.preferredTransparency`{luau} (`Node<number>`{luau}) tracks [`GuiService.PreferredTransparency`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiService#PreferredTransparency) from `0`{luau} (fully opaque backgrounds) to `1`{luau} (default). Multiply translucent background transparencies by this node to respect the player's contrast preference:

```luau
Flux.new "Frame" {
    BackgroundTransparency = function()
        return 0.35 * Flux.Responsive.preferredTransparency()
    end,
}
```

## Configuration {#configuration}

Mutate `Flux.Responsive.config`{luau} once at startup before building your UI to customize the default reference resolution, scale mode, clamps, or breakpoint widths:

```luau
Flux.Responsive.config.reference = Vector2.new(1280, 720)
Flux.Responsive.config.mode = "height" -- "min" (default) | "width" | "height" | "max"
Flux.Responsive.config.min = 0.5
Flux.Responsive.config.max = 2
Flux.Responsive.config.breakpoints = { phone = 700, tablet = 1100 }
```

### Per-Surface Overrides {#per-surface-overrides}

Use `Flux.Responsive.scaleOf(partialConfig?)`{luau} and `Flux.Responsive.breakpointOf(partialConfig?)`{luau} to create derived nodes with custom thresholds or a custom `viewport`{luau} source (such as a `SurfaceGui`{luau} or Studio `DockWidgetPluginGui`{luau}):

```luau
local dockSize = Flux.property(dockWidget, "AbsoluteSize")

local dockScale = Flux.Responsive.scaleOf {
    viewport = dockSize,
    reference = Vector2.new(400, 600),
}

local dockBreakpoint = Flux.Responsive.breakpointOf {
    viewport = dockSize,
    breakpoints = { phone = 320, tablet = 480 },
}
```
