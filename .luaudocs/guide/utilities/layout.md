---
title: Layout
description: Terse helpers for padding, corners, strokes, gradients, constraints, and UI layouts that drop straight into a Flux tree.
outline: deep
sidebar_position: 2
---

# Layout

Flux's layout helpers (`Flux.padding`{luau}, `Flux.corner`{luau}, `Flux.stroke`{luau}, `Flux.list`{luau}, `Flux.grid`{luau}, `Flux.flex`{luau}, `Flux.gradient`{luau}, `Flux.aspectRatio`{luau}, `Flux.sizeConstraint`{luau}, `Flux.textSizeConstraint`{luau}) are concise, strictly typed wrappers that return standard Roblox layout and modifier instances directly inside a children table:

```luau
Flux.new "Frame" {
    Size = UDim2.fromOffset(300, 0),
    AutomaticSize = Enum.AutomaticSize.Y,

    Flux.padding(16),
    Flux.corner(12),
    Flux.list { gap = 8 },

    Flux.new "TextLabel" { Text = "First" },
    Flux.new "TextLabel" { Text = "Second" },
}
```

Three conventions apply across every helper:

- **Bare numbers are offset pixels.** `Flux.padding(8)`{luau} and `gap = 8`{luau} become `UDim.new(0, 8)`{luau}. Pass a `UDim`{luau} explicitly when you want scale.
- **Friendly strings instead of Enums.** `direction = "x"`{luau}, `align = "center"`{luau}, `Flux.flex("fill")`{luau} are strictly typed and accept raw `EnumItem`{luau}s as well.
- **Any argument can be reactive.** Pass a [Signal](/guide/concepts/signals), [Computed](/guide/concepts/computeds), or function `() -> T`{luau} anywhere a static value is accepted.

## `padding` {#padding}

`Flux.padding(value)`{luau} returns a [`UIPadding`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIPadding). Accepts a single length for all sides, a `{ top, bottom, left, right, x, y }`{luau} table, or a reactive source yielding a length or `{ top, bottom, left, right }`{luau} struct:

```luau
Flux.padding(8)                      -- all four sides (8 px)
Flux.padding { x = 16, y = 8 }       -- horizontal / vertical
Flux.padding { top = 8, left = 16 }  -- individual sides
Flux.padding(function()
    return 8 * Flux.Responsive.scale()
end)
```

## `corner` {#corner}

`Flux.corner(radius?)`{luau} returns a [`UICorner`](https://create.roblox.com/docs/en-us/reference/engine/classes/UICorner). Pass offset pixels, a `UDim`{luau}, or a per-corner table `{ topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right, radius }`{luau}; omit the argument for the engine default (`8`{luau} px):

```luau
Flux.corner()                        -- default 8 px rounding
Flux.corner(12)                      -- CornerRadius = UDim.new(0, 12)
Flux.corner(UDim.new(0.5, 0))        -- pill / circle
Flux.corner { top = 12, bottom = 0 } -- round only the top corners
```

## `stroke` {#stroke}

`Flux.stroke(config?)`{luau} returns a [`UIStroke`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIStroke):

```luau
Flux.stroke {
    thickness = 2,        -- px
    color = accentColor,  -- static or reactive Color3
    transparency = 0.25,
    mode = "border",      -- "contextual" (default) | "border"
    joins = "round",      -- "round" (default) | "bevel" | "miter"
    position = "inner",   -- "outer" (default) | "center" | "inner"
    offset = 0,           -- border offset in px or UDim
}
```

## `list` {#list}

`Flux.list(config?)`{luau} returns a [`UIListLayout`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIListLayout) with `SortOrder = LayoutOrder`{luau} and flexbox-style `align`{luau} (cross-axis) and `justify`{luau} (main-axis) options:

```luau
Flux.list {
    gap = 8,             -- spacing between items (px or UDim)
    direction = "x",     -- "x" (horizontal) | "y" (vertical, default)
    align = "center",    -- cross-axis alignment
    justify = "between", -- main-axis alignment/distribution
    wraps = true,
    lineAlign = "start", -- "automatic" | "start" | "center" | "end" | "stretch"
}
```

`align`{luau} and `justify`{luau} accept:
- `"start" | "center" | "end"`{luau}: align items along the axis.
- `"between" | "around" | "evenly"`{luau}: distribute free space ([`UIFlexAlignment`](https://create.roblox.com/docs/en-us/reference/engine/enums/UIFlexAlignment)).
- `"stretch" | "fill"`{luau}: stretch items to fill the axis.

When `direction`{luau} is reactive, `align`{luau} and `justify`{luau} automatically re-route to their new axes when `direction`{luau} flips. Use `horizontalAlign`{luau} and `verticalAlign`{luau} to pin a specific axis directly.

## `grid` {#grid}

`Flux.grid(config?)`{luau} returns a [`UIGridLayout`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIGridLayout). `cell`{luau} and `gap`{luau} accept a `number`{luau} (square offset px), `Vector2`{luau} (offset px), or `UDim2`{luau}:

```luau
Flux.grid {
    cell = Vector2.new(100, 100), -- CellSize
    gap = 8,                      -- CellPadding
    fill = "x",                   -- "x" (default) | "y"
    align = "center",             -- HorizontalAlignment ("start" | "center" | "end")
    justify = "center",           -- VerticalAlignment ("start" | "center" | "end")
    maxCells = 4,                 -- FillDirectionMaxCells
}
```

## `flex` {#flex}

`Flux.flex(mode?)`{luau} returns a [`UIFlexItem`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIFlexItem) for children inside a `UIListLayout`{luau}. `mode`{luau} defaults to `"fill"`{luau} (`"fill" | "grow" | "shrink" | "none"`{luau}):

```luau
Flux.new "Frame" {
    Flux.list { direction = "x", gap = 8 },

    Flux.new "TextLabel" { Text = "Fixed" },
    Flux.new "Frame" { Flux.flex() }, -- expands to fill remaining space
}
```

## `gradient` {#gradient}

`Flux.gradient(config?)`{luau} returns a [`UIGradient`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIGradient). `color`{luau} and `transparency`{luau} accept a single value, an array of stops spread evenly from `0`{luau} to `1`{luau}, or a `ColorSequence`{luau} / `NumberSequence`{luau}:

```luau
Flux.gradient {
    color = { Color3.fromRGB(80, 140, 255), Color3.fromRGB(160, 80, 255) },
    transparency = { 0, 0.25 },
    rotation = 45,
}
```

## Constraints

### `aspectRatio` {#aspectratio}

`Flux.aspectRatio(ratio, aspectType?, dominantAxis?)`{luau} returns a [`UIAspectRatioConstraint`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIAspectRatioConstraint):

```luau
Flux.aspectRatio(16 / 9)
Flux.aspectRatio(1, "scale", "height") -- aspectType: "fit" | "scale", dominantAxis: "width" | "height"
```

### `sizeConstraint` {#sizeconstraint}

`Flux.sizeConstraint(config?)`{luau} returns a [`UISizeConstraint`](https://create.roblox.com/docs/en-us/reference/engine/classes/UISizeConstraint). Set whole `Vector2`{luau} bounds with `min`{luau} / `max`{luau} or single-axis bounds with `minWidth`{luau}, `minHeight`{luau}, `maxWidth`{luau}, and `maxHeight`{luau}:

```luau
Flux.sizeConstraint {
    minWidth = 200,
    maxWidth = 600,
    maxHeight = 400,
}
```

### `textSizeConstraint` {#textsizeconstraint}

`Flux.textSizeConstraint(config?)`{luau} returns a [`UITextSizeConstraint`](https://create.roblox.com/docs/en-us/reference/engine/classes/UITextSizeConstraint) bounding text size between `min`{luau} and `max`{luau} pixels:

```luau
Flux.textSizeConstraint { min = 12, max = 28 }
```
