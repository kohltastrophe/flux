---
title: Responsive
description: Reactive viewport, scale, breakpoint, and safe-area values for building UI that adapts to any screen.
outline: deep
---

# Responsive

Roblox UI authored in fixed offset pixels looks right on the screen you built it on and wrong everywhere else. Flux's responsive layer exposes the screen as a set of **reactive values you read** (`Flux.viewport`{lua}, `Flux.scale`{lua}, `Flux.breakpoint`{lua}, and `Flux.safeArea`{lua}), so your layout reacts to the device the same way every other binding reacts to state.

Everything here is derived from one shared `Flux.viewport`{lua} node, kept in sync with the active camera. There are no factories to call and nothing to mount: read the value, bind it, done. (They are also available under the `Flux.Responsive`{lua} namespace.)

## Scale

`Flux.scale`{lua} is a `Node<number>`{luau} where `1.0`{luau} means the viewport matches the reference resolution. Bind it to a [`UIScale`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIScale) and your whole UI grows and shrinks proportionally:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

new "ScreenGui" {
    Parent = playerGui,

    new "Frame" {
        Size = UDim2.fromOffset(800, 600),

        -- One UIScale scales the entire subtree to fit the screen.
        new "UIScale" { Scale = Flux.scale },
    },
}
```

Because reactive nodes support [operator overloading](/guide/concepts/signals), you can also fold the factor directly into a calculation:

```luau
new "TextLabel" {
    -- Scale a fixed design size by the current factor.
    Size = function()
        return UDim2.fromOffset(200 * Flux.scale, 50 * Flux.scale)
    end,
}
```

By default `scale` is computed as `math.min(viewport.X / reference.X, viewport.Y / reference.Y)`{luau}: the **fit** mode, which guarantees nothing ever overflows the screen. The reference resolution defaults to `1920×1080`{luau} and there are no clamps. See [Configuration](#configuration) to change any of this.

## Breakpoint

`Flux.breakpoint`{lua} is a `Node<"phone" | "tablet" | "desktop">`{luau} derived from viewport **width**. Use it to switch _layout_, not just shrink it. Pair it with [`Flux.switch`](/guide/concepts/conditionals):

```luau
Flux.switch(Flux.breakpoint) {
    phone = function()
        return CompactLayout()
    end,
    tablet = function()
        return CompactLayout()
    end,
    desktop = function()
        return WideLayout()
    end,
}
```

> [!NOTE]
> Breakpoints are **size classes, not hardware detection**: they come from viewport width, so a small windowed desktop client falls into `"phone"`{luau}. That is usually exactly what you want: a phone-sized window deserves the phone layout. The default thresholds are `< 600`{luau} (phone), `600–1024`{luau} (tablet), and `≥ 1024`{luau} (desktop).

## Safe area

`Flux.safeArea`{lua} is a `Node<{ top: number, bottom: number, left: number, right: number }>`{luau} of inset pixels from the Roblox topbar and reserved Core-UI regions ([`GuiService:GetGuiInset()`](https://create.roblox.com/docs/en-us/reference/engine/classes/GuiService#GetGuiInset)). The struct maps one-to-one onto a [`UIPadding`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIPadding), and [`Flux.padding`](/guide/utilities/layout#padding) accepts the node directly:

```luau
new "Frame" {
    Size = UDim2.fromScale(1, 1),

    -- Keep content clear of the topbar / notch, reactively.
    Flux.padding(Flux.safeArea),

    -- ...content...
}
```

> [!TIP]
> Device notches and rounded corners are handled declaratively by [`ScreenGui.ScreenInsets`](https://create.roblox.com/docs/en-us/reference/engine/classes/ScreenGui#ScreenInsets). `Flux.safeArea`{lua} covers the topbar/Core-UI inset.

## Viewport

`Flux.viewport`{lua} is the `Node<Vector2>`{luau} everything else derives from: the current `ViewportSize`{luau} of `workspace.CurrentCamera`{luau}, kept in sync as the window resizes or the camera changes. Read it when you need the raw size:

```luau
local isPortrait = Flux(function()
    return Flux.viewport().Y > Flux.viewport().X
end)
```

## Configuration

Tuning lives in the global `Flux.Responsive.config`{luau} table. Set it **once at startup**, before your UI is built:

```luau
Flux.Responsive.config.reference = Vector2.new(1280, 720)
Flux.Responsive.config.mode = "height"
Flux.Responsive.config.min = 0.5  -- never shrink below half size
Flux.Responsive.config.max = 2    -- never grow past double
Flux.Responsive.config.breakpoints = { phone = 700, tablet = 1100 }
```

| Field         | Default                    | Meaning                                                                   |
| :------------ | :------------------------- | :------------------------------------------------------------------------ |
| `reference`   | `Vector2(1920,1080)`       | The resolution at which `scale` is `1.0`.                                 |
| `mode`        | `"min"`                    | `"min"` (fit) · `"width"` · `"height"` · `"max"` (cover) · `"diagonal"`.  |
| `min` / `max` | `nil`                      | Optional clamps on the scale factor.                                      |
| `breakpoints` | `{phone=600, tablet=1024}` | Upper-bound widths for `phone` and `tablet`; anything wider is `desktop`. |

### Per-surface overrides

For a second reference resolution or a `SurfaceGui` with a different effective size, use the factory escape hatches. They take a partial config (merged over your global `Flux.Responsive.config`{lua}, so unspecified fields inherit whatever you set there), and return a fresh node:

```luau
-- A scale node tuned for a wide HUD, width-driven and clamped.
local hudScale = Flux.Responsive.scaleOf {
    mode = "width",
    min = 0.75,
}

local tabletFirst = Flux.Responsive.breakpointOf {
    breakpoints = { phone = 480, tablet = 900 },
}
```

### Pure helpers

The derivation math is also exposed as pure functions that take plain numbers, handy for one-off calculations and unit tests:

```luau
Flux.Responsive.scaleFor(1280, 720)        -- → number
Flux.Responsive.breakpointFor(800)         -- → "tablet"
Flux.Responsive.scaleFor(1280, 720, { mode = "width" })
```

> [!NOTE]
> The reactive nodes read the engine (camera, `GuiService`), so they only update under Roblox. The pure `scaleFor`{luau} / `breakpointFor`{luau} helpers and all derivation logic run anywhere, including headless Luau, which is how Flux tests them.
