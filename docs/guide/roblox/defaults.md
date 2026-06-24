---
title: Defaults
description: The default property overrides Flux applies to newly created instances.
outline: deep
---

# Defaults

Many of Roblox's built-in instance defaults are legacy choices that nearly every project overrides: parts spawn unanchored in Plastic, GUI objects draw borders, buttons auto-color, and layouts sort by name. To cut that boilerplate, `Flux.new`{lua} applies a curated set of **default property overrides** immediately after creating the instance, before your own properties are assigned.

> [!IMPORTANT]
> This changes behavior compared to `Instance.new`{lua}: `Flux.new "Part" {}`{luau} creates an **anchored**, SmoothPlastic part, and `Flux.new "TextButton" {}`{luau} does **not** auto-color when pressed. If a freshly created instance behaves unexpectedly, check the table below.

Your own properties always win; defaults are applied first and overwritten by anything in your properties table. `Flux.edit`{lua} never applies defaults; they only apply to instances Flux creates.

## Default Overrides

| Class                                                           | Overrides                                                                                              |
| :-------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------- |
| `Part`                                                          | `Anchored = true`, `Material = SmoothPlastic`, `Size = (1, 1, 1)`                                      |
| `ScreenGui`, `BillboardGui`                                     | `ResetOnSpawn = false`, `ZIndexBehavior = Sibling`                                                     |
| `SurfaceGui`                                                    | `ResetOnSpawn = false`, `ZIndexBehavior = Sibling`, `PixelsPerStud = 50`, `SizingMode = PixelsPerStud` |
| `Frame`, `ImageLabel`, `VideoFrame`, `ViewportFrame`            | White `BackgroundColor3`, black `BorderColor3`, `BorderSizePixel = 0`                                  |
| `ScrollingFrame`                                                | Same as `Frame` + black `ScrollBarImageColor3`                                                         |
| `ImageButton`                                                   | Same as `Frame` + `AutoButtonColor = false`                                                            |
| `TextLabel`                                                     | Same as `Frame` + `Font = SourceSans`, `Text = ""`, black `TextColor3`                                 |
| `TextBox`                                                       | Same as `TextLabel` + `ClearTextOnFocus = false`                                                       |
| `TextButton`                                                    | Same as `TextLabel` + `AutoButtonColor = false`                                                        |
| `UIListLayout`, `UIGridLayout`, `UITableLayout`, `UIPageLayout` | `SortOrder = LayoutOrder`                                                                              |

`CanvasGroup` is intentionally left at Roblox's own defaults (it appears in `Defaults.luau` with no overrides), so a `Flux.new "CanvasGroup" {}`{luau} matches `Instance.new("CanvasGroup")`{luau}.

The authoritative list lives in [`src/Defaults.luau`](https://github.com/kohltastrophe/flux/blob/main/src/Defaults.luau).

## Disabling Defaults

Set `Flux.Flags.defaults = false`{luau} once at startup to disable the system globally:

```luau
local Flux = require(ReplicatedStorage.Flux)
Flux.Flags.defaults = false

-- From here on, new "Part" {} behaves exactly like Instance.new("Part")
```

## Customizing Defaults

`Flux.Defaults` is a plain table; edit existing entries or register your own classes at startup to apply your project's conventions everywhere:

```luau
Flux.Defaults.TextLabel.Font = Enum.Font.GothamMedium
Flux.Defaults.UICorner = { CornerRadius = UDim.new(0, 8) }
```

To opt out of a default without disabling the whole system, set it to `nil`{luau}: `Flux.Defaults.Part.Anchored = nil`{luau} drops just the anchoring override while keeping the rest, and `Flux.Defaults.Part = nil`{luau} clears the entire class.
