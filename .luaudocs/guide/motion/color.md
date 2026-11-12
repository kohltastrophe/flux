---
title: Color
description: A perceptual color toolkit built on the same Oklab space that powers Flux animations.
outline: deep
sidebar_position: 3
---

# Color

`Flux.Color` exposes the **Oklab perceptual color space** used by Flux animations as a standalone toolkit for lightening, saturating, blending, and checking contrast on [`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3) values.

```luau
local Color = Flux.Color
local brand = Color3.fromRGB(82, 120, 255)

local hovered = Color.lighten(brand, 0.08)
local pressed = Color.lighten(brand, -0.08) -- negative darkens
local text = Color.readable(brand)
```

Manipulation and blending functions take and return standard `Color3` values mapped into the displayable sRGB gamut (`luminance` and `contrast` return numbers, and `Color.Oklab.*` works on `Vector3` coordinates).

## Manipulation

| Function | Effect |
| :--- | :--- |
| **`Color.lighten(c, amount)`** | Shifts perceptual lightness by `amount` (negative darkens) |
| **`Color.saturate(c, amount)`** | Shifts chroma by `amount` (negative desaturates, stops at gray; neutral grays have no hue axis so saturating pure gray is a no-op) |
| **`Color.rotateHue(c, degrees)`** | Rotates hue around the Oklab wheel in degrees |
| **`Color.grayscale(c)`** | Removes all chroma while preserving perceptual lightness |

Because Oklab is perceptually uniform, `Color.lighten(c, 0.08)` produces the same perceived step whether `c` is dark or light:

```luau
local brand = Color3.fromRGB(82, 120, 255)

local hovered = Color.lighten(brand, 0.08)
local pressed = Color.lighten(brand, -0.08)
local muted = Color.saturate(brand, -0.05)
local accent = Color.rotateHue(brand, 180) -- complementary hue
```

## Blending

`Color.mix(a, b, t)` interpolates between `a` (`t = 0`) and `b` (`t = 1`) in Oklab with gamut clipping (`t` is unclamped, so values outside `[0, 1]` extrapolate while staying gamut-mapped; [`Flux.spring`](/guide/motion/spring) and [`Flux.tween`](/guide/motion/tween) travel the same Oklab path using unclipped `toRGB(lab, false)` per frame on `Color3` for speed):

```luau
local midpoint = Color.mix(Color3.new(1, 0, 0), Color3.new(0, 0, 1), 0.5)
```

## Accessibility

Built on WCAG relative luminance:

| Function | Returns |
| :--- | :--- |
| **`Color.luminance(c)`** | Relative luminance from `0` (black) to `1` (white) |
| **`Color.contrast(a, b)`** | Contrast ratio from `1` (identical) to `21` (black/white) |
| **`Color.readable(bg, dark?, light?)`** | Whichever candidate (`dark` or `light`) reads better |

`Color.readable` defaults to black and white, or accepts custom dark and light brand tints:

```luau
local label = Flux.new "TextLabel" {
	BackgroundColor3 = brand,
	TextColor3 = Color.readable(brand),
}
```

## Working in Oklab Directly

To chain several transforms without converting `Color3` to and from Oklab at every step, use `Color.Oklab`, which operates on raw Oklab [`Vector3`](https://create.roblox.com/docs/reference/engine/datatypes/Vector3) values (`X` = lightness, `Y`/`Z` = `a`/`b` chroma axes):

```luau
local lab = Color.Oklab.fromRGB(brand)
lab = Color.Oklab.lighten(lab, 0.1)
lab = Color.Oklab.saturate(lab, 0.05)
lab = Color.Oklab.rotateHue(lab, 20)
local result = Color.Oklab.toRGB(lab)
```

`Color.Oklab` also includes `lighten`, `saturate`, `rotateHue`, `grayscale`, and `mix` directly on Oklab `Vector3` values, alongside the color-space converters:

| Function | Converts |
| :--- | :--- |
| **`Color.Oklab.fromRGB(c)` / `Color.Oklab.toRGB(lab, clamped?)`** | sRGB `Color3` ↔ Oklab `Vector3` |
| **`Color.Oklab.fromLinear(c)` / `Color.Oklab.toLinear(lab, clamped?)`** | Linear sRGB `Color3` ↔ Oklab `Vector3` |
| **`Color.sRGB.fromLinear(c)` / `Color.sRGB.toLinear(c)`** | sRGB `Color3` ↔ Linear sRGB `Color3` |

When an Oklab color falls outside the displayable sRGB gamut, `toRGB` and `toLinear` map it back to the gamut boundary while preserving hue and lightness ([Björn Ottosson's gamut clipping](https://bottosson.github.io/posts/gamutclipping/)). Pass `clamped = false` for the raw, unclipped conversion.
