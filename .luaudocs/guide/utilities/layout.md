---
title: Layout
description: Terse helpers for padding, corners, strokes, gradients, constraints, and UI layouts that drop straight into a Flux tree.
outline: deep
sidebar_position: 2
---

# Layout

Flux's layout helpers (`Flux.padding`, `Flux.corner`, `Flux.stroke`, `Flux.list`, `Flux.grid`, `Flux.flex`, `Flux.scale`, `Flux.gradient`, `Flux.aspectRatio`, `Flux.sizeConstraint`, `Flux.textSizeConstraint`) are concise, strictly typed wrappers that return standard Roblox layout and modifier instances directly inside a children table:

```luau
Flux.new "Frame" {
	Size = UDim2.fromOffset(300, 0),
	AutomaticSize = Enum.AutomaticSize.Y,

	Flux.padding(16),
	Flux.corner(12),
	Flux.list({ gap = 8 }),

	Flux.new "TextLabel" { Text = "First" },
	Flux.new "TextLabel" { Text = "Second" },
}
```

Three conventions apply across every helper:

- **Bare numbers are offset pixels.** `Flux.padding(8)` and `gap = 8` become `UDim.new(0, 8)`. Pass a `UDim` explicitly when you want scale.
- **Short string aliases instead of Enums.** `direction = "x"`, `joins = "round"`, and `Flux.flex("fill")` are strictly typed and accept raw `EnumItem`s too (`align` and `justify` on `Flux.list` use flexbox string aliases so they can map across `HorizontalAlignment`, `VerticalAlignment`, `UIFlexAlignment`, and `ItemLineAlignment`).
- **Any argument can be reactive.** Pass a [Signal](/guide/concepts/signals), [Computed](/guide/concepts/computeds), or function `() -> T` anywhere a static value is accepted.

## `padding` {#padding}

`Flux.padding(value)` returns a [`UIPadding`](https://create.roblox.com/docs/reference/engine/classes/UIPadding). Accepts a single length for all sides, a `{ top, bottom, left, right, x, y }` table, or a reactive source yielding a length or `{ top, bottom, left, right, x, y }` table:

```luau
Flux.padding(8)                       -- all four sides (8 px)
Flux.padding({ x = 16, y = 8 })       -- horizontal / vertical
Flux.padding({ top = 8, left = 16 })  -- individual sides
Flux.padding(function()
	return 8 * Flux.Responsive.scale()
end)
```

## `corner` {#corner}

`Flux.corner(radius?)` returns a [`UICorner`](https://create.roblox.com/docs/reference/engine/classes/UICorner). Pass offset pixels, a `UDim`, or a per-corner table `{ topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right, radius }` (omitted corners fall back to `radius` or `8` px; omit the argument altogether for `8` px):

```luau
Flux.corner()                          -- default 8 px rounding
Flux.corner(12)                        -- CornerRadius = UDim.new(0, 12)
Flux.corner(UDim.new(0.5, 0))          -- pill / circle
Flux.corner({ top = 12, bottom = 0 })  -- round only the top corners
```

## `stroke` {#stroke}

`Flux.stroke(config?)` returns a [`UIStroke`](https://create.roblox.com/docs/reference/engine/classes/UIStroke):

```luau
Flux.stroke({
	thickness = 2,        -- px
	color = accentColor,  -- static or reactive Color3
	transparency = 0.25,
	mode = "border",      -- "contextual" (default) | "border"
	joins = "round",      -- "round" (default) | "bevel" | "miter"
	position = "inner",   -- "outer" (default) | "center" | "inner"
	offset = 0,           -- border offset in px or UDim
})
```

## `list` {#list}

`Flux.list(config?)` returns a [`UIListLayout`](https://create.roblox.com/docs/reference/engine/classes/UIListLayout) with `SortOrder = LayoutOrder` and flexbox-style `align` (cross-axis) and `justify` (main-axis) options:

```luau
Flux.list({
	gap = 8,             -- spacing between items (px or UDim)
	direction = "x",     -- "x" (horizontal) | "y" (vertical, default)
	align = "center",    -- cross-axis alignment
	justify = "between", -- main-axis alignment/distribution
	wraps = true,
	lineAlign = "start", -- "automatic" | "start" | "center" | "end" | "stretch"
})
```

`align` and `justify` accept:
- `"start" | "center" | "end"` to align items along the axis.
- `"between" | "around" | "evenly"` to distribute free space ([`UIFlexAlignment`](https://create.roblox.com/docs/reference/engine/enums/UIFlexAlignment)).
- `"stretch" | "fill"` to stretch items to fill the axis, or `"none"` to clear `UIFlexAlignment`.

When `direction` is reactive, `align` and `justify` re-route to their new axes automatically whenever `direction` flips. Use `horizontalAlign` and `verticalAlign` to pin a specific axis directly.

## `grid` {#grid}

`Flux.grid(config?)` returns a [`UIGridLayout`](https://create.roblox.com/docs/reference/engine/classes/UIGridLayout) with `SortOrder = LayoutOrder`. `cell` and `gap` accept a `number` (square offset px), `Vector2` (offset px), or `UDim2`:

```luau
Flux.grid({
	cell = Vector2.new(100, 100), -- CellSize
	gap = 8,                      -- CellPadding
	fill = "x",                   -- "x" (default) | "y"
	align = "center",             -- HorizontalAlignment ("start" | "center" | "end")
	justify = "center",           -- VerticalAlignment ("start" | "center" | "end")
	maxCells = 4,                 -- FillDirectionMaxCells
})
```

## `flex` {#flex}

`Flux.flex(config?)` returns a [`UIFlexItem`](https://create.roblox.com/docs/reference/engine/classes/UIFlexItem) for children inside a `UIListLayout`. Pass a mode preset (`"fill"` default, `"grow"`, `"shrink"`, `"none"`, `"custom"`, or `Enum.UIFlexMode`), a numeric `GrowRatio` weight, a `{ mode?, grow?, shrink?, lineAlign? }` table, or a reactive source.

```luau
Flux.new "Frame" {
	Flux.list({ direction = "x", gap = 8 }),

	Flux.new "TextLabel" { Text = "Fixed" },
	Flux.new "Frame" { Flux.flex() },                                 -- "fill" remaining space
	Flux.new "Frame" { Flux.flex(2) },                                -- Custom mode, GrowRatio = 2
	Flux.new "Frame" { Flux.flex({ shrink = 1, lineAlign = "end" }) },-- Custom mode with shrink & alignment
}
```

When you pass a table with `grow` or `shrink` and omit `mode`, `mode` defaults to `"custom"`. When a reactive `Flux.flex(source)` source switches away from a number to a preset string or `nil`, `GrowRatio` resets to `0`.

## `scale` {#scale}

`Flux.scale(scale?)` returns a [`UIScale`](https://create.roblox.com/docs/reference/engine/classes/UIScale) with `Scale` (`1` by default). Pass a static number or a reactive node/getter (`Flux.Reactive<number>`):

```luau
local openScale = Flux.spring(function()
	return if isOpen() then 1 else 0.9
end, 4, 0.8)

Flux.new "Frame" {
	Size = UDim2.fromOffset(200, 120),
	__CLEAN = { openScale },
	Flux.scale(openScale),
}
```

## `gradient` {#gradient}

`Flux.gradient(config?)` returns a [`UIGradient`](https://create.roblox.com/docs/reference/engine/classes/UIGradient). `color` and `transparency` accept a single value, an array of stops spread evenly from `0` to `1`, or a `ColorSequence` / `NumberSequence`:

```luau
Flux.gradient({
	color = { Color3.fromRGB(80, 140, 255), Color3.fromRGB(160, 80, 255) },
	transparency = { 0, 0.25 },
	rotation = 45,
	offset = Vector2.new(0, 0),
	enabled = true,
})
```

## Constraints

### `aspectRatio` {#aspectratio}

`Flux.aspectRatio(ratio, aspectType?, dominantAxis?)` returns a [`UIAspectRatioConstraint`](https://create.roblox.com/docs/reference/engine/classes/UIAspectRatioConstraint):

```luau
Flux.aspectRatio(16 / 9)
Flux.aspectRatio(1, "scale", "height") -- aspectType: "fit" | "scale", dominantAxis: "width" | "height"
```

### `sizeConstraint` {#sizeconstraint}

`Flux.sizeConstraint(config?)` returns a [`UISizeConstraint`](https://create.roblox.com/docs/reference/engine/classes/UISizeConstraint). Set whole `Vector2` bounds with `min` / `max` or single-axis bounds with `minWidth`, `minHeight`, `maxWidth`, and `maxHeight`:

```luau
Flux.sizeConstraint({
	minWidth = 200,
	maxWidth = 600,
	maxHeight = 400,
})
```

### `textSizeConstraint` {#textsizeconstraint}

`Flux.textSizeConstraint(config?)` returns a [`UITextSizeConstraint`](https://create.roblox.com/docs/reference/engine/classes/UITextSizeConstraint) bounding text size between `min` and `max` pixels:

```luau
Flux.textSizeConstraint({ min = 12, max = 28 })
```
