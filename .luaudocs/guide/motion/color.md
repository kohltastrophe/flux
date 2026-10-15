---
title: Color
description: A perceptual color toolkit built on the same Oklab space that powers Flux animations.
outline: deep
sidebar_position: 3
---

# Color

`Flux.Color`{luau} exposes the **Oklab perceptual color space** used by Flux animations as a standalone toolkit for lightening, saturating, blending, and checking contrast on [`Color3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Color3) values.

```luau
local Color = Flux.Color
local brand = Color3.fromRGB(82, 120, 255)

local hovered = Color.lighten(brand, 0.08)
local pressed = Color.lighten(brand, -0.08) -- negative darkens
local text = Color.readable(brand)
```

Every function takes and returns a standard `Color3`{luau} mapped into the displayable sRGB gamut.

## Manipulation

| Function                            | Effect                                                          |
| :---------------------------------- | :-------------------------------------------------------------- |
| `Color.lighten(c, amount)`{luau}    | Shifts perceptual lightness by `amount` (negative darkens)      |
| `Color.saturate(c, amount)`{luau}   | Shifts chroma by `amount` (negative desaturates, stops at gray) |
| `Color.rotateHue(c, degrees)`{luau} | Rotates hue around the Oklab wheel in degrees                   |
| `Color.grayscale(c)`{luau}          | Removes all chroma while preserving perceptual lightness        |

Because Oklab is perceptually uniform, `Color.lighten(c, 0.08)`{luau} produces the same perceived step whether `c`{luau} is dark or light:

```luau
local brand = Color3.fromRGB(82, 120, 255)

local hovered = Color.lighten(brand, 0.08)
local pressed = Color.lighten(brand, -0.08)
local muted = Color.saturate(brand, -0.05)
local accent = Color.rotateHue(brand, 180) -- complementary hue
```

## Blending

`Color.mix(a, b, t)`{luau} interpolates between `a`{luau} (`t = 0`{luau}) and `b`{luau} (`t = 1`{luau}) in Oklab—the exact path traveled by [`Flux.spring`](/guide/motion/spring) and [`Flux.tween`](/guide/motion/tween). `t`{luau} is unclamped, so values outside `[0, 1]` extrapolate while staying gamut-mapped:

```luau
local midpoint = Color.mix(Color3.new(1, 0, 0), Color3.new(0, 0, 1), 0.5)
```

## Accessibility

Built on WCAG relative luminance:

| Function                                  | Returns                                                  |
| :---------------------------------------- | :------------------------------------------------------- |
| `Color.luminance(c)`{luau}                | Relative luminance from `0` (black) to `1` (white)       |
| `Color.contrast(a, b)`{luau}              | Contrast ratio from `1` (identical) to `21` (black/white)|
| `Color.readable(bg, dark?, light?)`{luau} | Whichever candidate (`dark` or `light`) reads better     |

`Color.readable`{luau} defaults to black and white, or accepts custom dark/light brand tints:

```luau
local label = Flux.new "TextLabel" {
    BackgroundColor3 = brand,
    TextColor3 = Color.readable(brand),
}
```

## Working in Oklab Directly

To chain several transforms without converting `Color3`{luau} ↔ Oklab at every step, use `Color.Oklab`{luau}, which operates on raw Oklab [`Vector3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector3) values (`X` = lightness, `Y`/`Z` = `a`/`b` chroma axes):

```luau
local lab = Color.Oklab.fromRGB(brand)
lab = Color.Oklab.lighten(lab, 0.1)
lab = Color.Oklab.saturate(lab, 0.05)
lab = Color.Oklab.rotateHue(lab, 20)
local result = Color.Oklab.toRGB(lab)
```

| Function                                                                        | Converts                                      |
| :------------------------------------------------------------------------------ | :-------------------------------------------- |
| `Color.Oklab.fromRGB(c)`{luau} / `Color.Oklab.toRGB(lab, clamped?)`{luau}       | sRGB `Color3` ↔ Oklab `Vector3`               |
| `Color.Oklab.fromLinear(c)`{luau} / `Color.Oklab.toLinear(lab, clamped?)`{luau} | Linear sRGB `Color3` ↔ Oklab `Vector3`        |
| `Color.sRGB.fromLinear(c)`{luau} / `Color.sRGB.toLinear(c)`{luau}               | sRGB `Color3` ↔ Linear sRGB `Color3`          |

When an Oklab color falls outside the displayable sRGB gamut, `toRGB`{luau} and `toLinear`{luau} map it back to the gamut boundary while preserving hue and lightness ([Björn Ottosson's gamut clipping](https://bottosson.github.io/posts/gamutclipping/)). Pass `clamped = false`{luau} for the raw, unclipped conversion.
