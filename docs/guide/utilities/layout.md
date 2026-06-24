---
title: Layout
description: Terse helpers for padding, constraints, and UI layouts that drop straight into a Flux tree.
outline: deep
---

# Layout

Roblox arranges and constrains UI through child instances: `UIListLayout`, `UIPadding`, `UIAspectRatioConstraint`, and friends. Writing them out longhand is verbose, especially the ones whose properties are `UDim`s. Flux's layout helpers are thin, typed wrappers that return those instances, so they drop straight into a children list alongside everything else:

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

Because each helper just **returns an instance**, it composes with the normal builder: `forValue`, selectors, and `__CLEAN` all keep working, and the parent `Frame` keeps full strict-typed property autocomplete. The helpers are also available under the `Flux.Layout`{luau} namespace.

## Conventions

Three rules apply across every helper:

- **Bare numbers are offset pixels.** `Flux.padding(8)`{luau} and `gap = 8`{luau} become `UDim.new(0, 8)`{luau}. Pass a `UDim`{luau} explicitly if you want scale.
- **Friendly strings instead of Enums.** `direction = "x"`{luau}, `align = "center"`{luau}, `Flux.flex("fill")`{luau}: terser than the full `Enum`, and still strictly typed. You can pass a raw `Enum`{luau} anywhere a string is accepted.
- **Any value can be reactive.** A `Node`{luau} or a function works wherever a static value does, and binds reactively, so `Flux.padding(Flux.safeArea)`{luau} and `Flux.list { gap = animatedGap }`{luau} just work, and clean up when the instance is destroyed.

## `padding`

Returns a [`UIPadding`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIPadding). Accepts one length for all sides, a per-side table, or a reactive struct node:

```luau
Flux.padding(8)                      -- all four sides
Flux.padding { x = 16, y = 8 }       -- horizontal / vertical
Flux.padding { top = 8, left = 16 }  -- only the sides you name
Flux.padding(Flux.safeArea)          -- bind a {top,bottom,left,right} node
```

## `list`

Returns a [`UIListLayout`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIListLayout) (inheriting Flux's `SortOrder = LayoutOrder`{luau} [default](/guide/roblox/defaults)).

```luau
Flux.list {
    gap = 8,             -- spacing between items (offset px)
    direction = "x",     -- "x" (horizontal) | "y" (vertical, default)
    align = "center",    -- cross-axis alignment
    justify = "start",   -- main-axis alignment (along `direction`)
    wraps = true,
}
```

`align` and `justify` follow flexbox semantics: `align` is the **cross** axis and `justify` the **main** axis (the one items flow along). Because their target axis depends on `direction`, they take the axis-agnostic strings `"start" | "center" | "end"`{luau}. To set an axis directly, or to pass a raw `Enum`{luau}, use `horizontalAlign` / `verticalAlign` instead.

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

Unlike [`list`](#list), `grid`'s `align` and `justify` always map to the **horizontal** and **vertical** axes respectively (not the direction-relative cross/main pair) since a grid flows along both axes at once.

## `aspectRatio`

Returns a [`UIAspectRatioConstraint`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIAspectRatioConstraint):

```luau
Flux.aspectRatio(16 / 9)
Flux.aspectRatio(1, "scale", "height")  -- ratio, aspectType, dominantAxis
```

`aspectType` accepts `"fit"`{luau} / `"scale"`{luau}; `dominantAxis` accepts `"width"`{luau} / `"height"`{luau}.

## `sizeConstraint`

Returns a [`UISizeConstraint`](https://create.roblox.com/docs/en-us/reference/engine/classes/UISizeConstraint). Either bound may be omitted:

```luau
Flux.sizeConstraint(Vector2.new(200, 100), Vector2.new(600, 400))
Flux.sizeConstraint(nil, Vector2.new(600, 400))  -- max only
```

Pure `UIScale`-based scaling shrinks everything uniformly; pairing it with a `sizeConstraint` keeps small screens from collapsing UI below a usable size. See [Responsive](/guide/utilities/responsive#scale).

## `flex`

Returns a [`UIFlexItem`](https://create.roblox.com/docs/en-us/reference/engine/classes/UIFlexItem) for items inside a flex `UIListLayout`:

```luau
new "Frame" {
    Flux.list { direction = "x" },

    new "TextLabel" { Text = "Fixed" },
    new "Frame" { Flux.flex("fill") },  -- "fill" | "grow" | "shrink" | "none"
}
```

> [!NOTE]
> These helpers create Roblox instances, so they run under Roblox (not headless Luau). A bad friendly string warns and falls back to a sensible default rather than erroring, but in `--!strict`{luau} mode the typed string-literal unions catch the typo before it ever runs.
