---
title: Defaults
description: The default property overrides Flux applies to newly created instances.
outline: deep
sidebar_position: 3
---

# Defaults

`Flux.new` applies a curated set of default property overrides immediately after creating an [`Instance`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance), before your own properties table is applied: parts start anchored in `SmoothPlastic`, GUI objects have `BorderSizePixel = 0`, buttons disable `AutoButtonColor`, and layouts sort by `LayoutOrder`.

Your own properties always override these defaults, and [`Flux.edit`](/guide/roblox/hydration) never applies defaults to existing instances.

## Default Overrides

| Class | Overrides Applied by `Flux.new` |
| :--- | :--- |
| **`Part`** | `Anchored = true`, `Material = Enum.Material.SmoothPlastic`, `Size = vector.create(1, 1, 1)` |
| **`ScreenGui`**, **`BillboardGui`** | `ResetOnSpawn = false`, `ZIndexBehavior = Enum.ZIndexBehavior.Sibling` |
| **`SurfaceGui`** | `ResetOnSpawn = false`, `ZIndexBehavior = Enum.ZIndexBehavior.Sibling`, `PixelsPerStud = 50`, `SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud` |
| **`Frame`**, **`ImageLabel`**, **`VideoFrame`**, **`ViewportFrame`** | `BackgroundColor3 = Color3.new(1, 1, 1)`, `BorderColor3 = Color3.new(0, 0, 0)`, `BorderSizePixel = 0` |
| **`ScrollingFrame`** | Same as `Frame` + `ScrollBarImageColor3 = Color3.new(0, 0, 0)` |
| **`ImageButton`** | Same as `Frame` + `AutoButtonColor = false` |
| **`TextLabel`** | Same as `Frame` + `Font = Enum.Font.SourceSans`, `Text = ""`, `TextColor3 = Color3.new(0, 0, 0)` |
| **`TextBox`** | Same as `TextLabel` + `ClearTextOnFocus = false` |
| **`TextButton`** | Same as `TextLabel` + `AutoButtonColor = false` |
| **`UIListLayout`**, **`UIGridLayout`**, **`UITableLayout`**, **`UIPageLayout`** | `SortOrder = Enum.SortOrder.LayoutOrder` |

The authoritative table lives in [`src/Edit.luau`](https://github.com/kohltastrophe/flux/blob/main/src/Edit.luau).

## Disabling Defaults

Set `Flux.Flags.defaults = false` at startup to disable the visual default overrides in `Flux.Defaults` globally:

```luau
Flux.Flags.defaults = false
```

> [!NOTE]
> `AutoButtonColor = false` on `TextButton` and `ImageButton` is applied even when `Flux.Flags.defaults = false`, since it controls button behavior rather than visual styling. Pass `AutoButtonColor = true` in the properties table when you want the engine's default tinting.

## Customizing Defaults

`Flux.Defaults` is a mutable table keyed by class name. Edit existing entries or add new class defaults at startup:

```luau
Flux.Defaults.TextLabel.Font = Enum.Font.GothamMedium
Flux.Defaults.UICorner = { CornerRadius = UDim.new(0, 8) }

-- Remove a single default override or clear an entire class:
Flux.Defaults.Part.Anchored = nil
Flux.Defaults.Part = nil
```
