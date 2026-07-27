---
title: Layout
description: Terse helpers for padding, corners, strokes, constraints, and UI layouts that drop straight into a Flux tree.
outline: deep
---

# Layout

Roblox arranges, constrains, and decorates UI through child instances: `UIListLayout`, `UIPadding`, `UICorner`, and friends. Writing them out longhand is verbose, especially the ones whose properties are `UDim`s or Enums. Flux's layout helpers are thin, typed wrappers that return those instances, so they drop straight into a children list alongside everything else:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

new "Frame" {
    Size = UDim2.fromOffset(300, 0),
    AutomaticSize = Enum.AutomaticSize.Y,

    Flux.padding(16),
    Flux.list { gap = 8 },

    new "TextLabel" { Text = "First" },
    new "TextLabel" { Text = "Second" },
}
```

Because each helper just **returns an instance**, it composes with the normal builder: `forValue`, selectors, and `_CLEAN` all keep working, and the parent `Frame` keeps full strict-typed property autocomplete. The helpers are also available under the `Flux.Layout`{luau} namespace.

## Conventions

Three rules apply across every helper:

- **Bare numbers are offset pixels.** `Flux.padding(8)`{luau} and `gap = 8`{luau} become `UDim.new(0, 8)`{luau}. Pass a `UDim`{luau} explicitly if you want scale.
- **Friendly strings instead of Enums.** `direction = "x"`{luau}, `align = "center"`{luau}, `Flux.flex("fill")`{luau}: terser than the full `Enum`, and still strictly typed. You can pass a raw `Enum`{luau} anywhere a string is accepted.
- **Any value can be reactive.** A `Node`{luau} or a function works wherever a static value does (enum strings included) and binds reactively, so `Flux.padding(Flux.safeArea)`{luau}, `Flux.list { gap = animatedGap }`{luau}, and a `direction` that flips with [`Flux.Responsive.breakpoint`](/guide/utilities/responsive#breakpoint) all just work, and clean up when the instance is destroyed. (A reactive enum prop can't be "unset", so it writes the engine default when its value is `nil`{luau} or invalid.)

## `padding`

Returns a [`UIPadding`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIPadding). Accepts one length for all sides, a per-side table, or a reactive source (node or function) yielding a length or a `{top,bottom,left,right}`{luau} struct:

```luau
Flux.padding(8)                      -- all four sides
Flux.padding { x = 16, y = 8 }       -- horizontal / vertical
Flux.padding { top = 8, left = 16 }  -- only the sides you name
Flux.padding(Flux.safeArea)          -- bind a {top,bottom,left,right} node
Flux.padding(function()              -- any computation works too
    return 8 * Flux.scale()
end)
```

## `corner`

Returns a [`UICorner`](https://create.roblox.com/docs/en-us/reference/engine/classes/UICorner). The radius is offset pixels or a `UDim`{luau}, optionally reactive; call it bare for the engine default (8 px):

```luau
Flux.corner()          -- default 8 px rounding
Flux.corner(12)        -- CornerRadius = UDim.new(0, 12)
Flux.corner(UDim.new(0.5, 0))  -- fully round (pill / circle)
```

## `stroke`

Returns a [`UIStroke`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIStroke):

```luau
Flux.stroke {
    thickness = 2,        -- px
    color = accentColor,  -- static or reactive Color3
    transparency = 0.25,
    mode = "border",      -- "contextual" (default) | "border"
    joins = "round",      -- "round" (default) | "bevel" | "miter"
}
```

## `list`

Returns a [`UIListLayout`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIListLayout) (inheriting Flux's `SortOrder = LayoutOrder`{luau} [default](/guide/roblox/defaults)).

```luau
Flux.list {
    gap = 8,             -- spacing between items (offset px)
    direction = "x",     -- "x" (horizontal) | "y" (vertical, default)
    align = "center",    -- cross-axis value
    justify = "between", -- main-axis value (along `direction`)
    wraps = true,
    lineAlign = "start", -- item alignment within a wrapped line
}
```

`align` and `justify` follow flexbox semantics: `align` is the **cross** axis and `justify` the **main** axis (the one items flow along). Because their target axis depends on `direction`, they take axis-agnostic strings:

- `"start" | "center" | "end"`{luau}: align items along the axis.
- `"between" | "around" | "evenly"`{luau}: distribute the free space between, around, or evenly amongst items ([`UIFlexAlignment`](https://create.roblox.com/docs/en-us/reference/engine/enums/UIFlexAlignment)), the flexbox `space-*` values.
- `"stretch"`{luau} (alias `"fill"`{luau}): resize items to fill the axis; on the cross axis this is CSS's `align-items: stretch`.

To set an axis directly, or to pass a raw `Enum`{luau}, use `horizontalAlign` / `verticalAlign` instead. When `wraps` is on, `lineAlign` (`"start" | "center" | "end" | "stretch" | "automatic"`{luau}) aligns items within their own line.

Every value may be reactive, including `direction`: `align`/`justify` re-route to their new axes when it flips:

```luau
Flux.list {
    direction = function() -- phones stack vertically, desktop flows across
        return if Flux.Responsive.breakpoint() == "phone" then "y" else "x"
    end,
    gap = 8,
    justify = "between",
}
```

## `grid`

Returns a [`UIGridLayout`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIGridLayout). `cell` and `gap` accept a `Vector2`{luau} or number (offset px) or a `UDim2`{luau}:

```luau
Flux.grid {
    cell = Vector2.new(100, 100),  -- CellSize
    gap = 8,                       -- CellPadding
    fill = "x",                    -- "x" | "y"
    align = "center",              -- HorizontalAlignment
    justify = "center",            -- VerticalAlignment
    maxCells = 4,                  -- FillDirectionMaxCells
}
```

Unlike [`list`](#list), `grid`'s `align` and `justify` always map to the **horizontal** and **vertical** axes respectively (not the direction-relative cross/main pair) since a grid flows along both axes at once, and they take only the alignment strings `"start" | "center" | "end"`{luau}.

## `aspectRatio`

Returns a [`UIAspectRatioConstraint`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIAspectRatioConstraint):

```luau
Flux.aspectRatio(16 / 9)
Flux.aspectRatio(1, "scale", "height")  -- ratio, aspectType, dominantAxis
```

`aspectType` accepts `"fit"`{luau} / `"scale"`{luau}; `dominantAxis` accepts `"width"`{luau} / `"height"`{luau}.

::: tip Where is `sizeConstraint`?
`UISizeConstraint`'s two `Vector2`{luau} properties need no conversion, so the longhand is just as terse, and reactive values already bind natively:

```luau
new "UISizeConstraint" { MinSize = Vector2.new(200, 100), MaxSize = maxSize }
```

:::

## `flex`

Returns a [`UIFlexItem`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIFlexItem) for items inside a flex `UIListLayout`. `mode` defaults to `"fill"`{luau}:

```luau
new "Frame" {
    Flux.list { direction = "x" },

    new "TextLabel" { Text = "Fixed" },
    new "Frame" { Flux.flex() },  -- "fill" (default) | "grow" | "shrink" | "none"
}
```

> [!NOTE]
> These helpers create Roblox instances, so they run under Roblox (not headless Luau). A bad friendly string warns and falls back to a sensible default rather than erroring, but in `--!strict`{luau} mode the typed string-literal unions catch the typo before it ever runs.
